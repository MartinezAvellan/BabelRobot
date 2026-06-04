//
//  DesktopCompanionManager.swift
//  BabelRobot
//
//  Conductor for the desktop companion. Owns the floating panel, the face
//  animator, and the cursor / behavior / emotion engines, and fuses them into
//  one displayed `faceState`:
//
//      emotion (AI events)  ▸ overrides ▸  behavior (idle / sleep / cursor)
//
//  It runs the whole feature on a SINGLE timer (CursorTrackingService): that
//  tick drives gaze, proximity-wake, and the sleep check. When the companion
//  is hidden, the timer and all animations stop, so idle CPU stays near zero.
//
//  Lives at app scope, so it is independent of the main window and survives
//  the main window closing.
//
//  Future hooks (architecture only — intentionally unimplemented):
//   • Voice input          → see `onVoiceInput`
//   • Speech synthesis     → see `onSpeak`
//   • OCR / screen reading  → see `onScreenObservation`
//   • Multi-monitor        → `screenForCompanion()` is the seam to extend
//

import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
final class DesktopCompanionManager: NSObject, NSWindowDelegate {

    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case docked, free
        var id: String { rawValue }
        var label: String { self == .docked ? "Docked" : "Free" }
        /// In Free mode the user can drag the robot around the desktop.
        var isDraggable: Bool { self == .free }
    }

    // MARK: - Persisted settings

    var enabled: Bool        { didSet { persist(); applyEnabled() } }
    var mode: Mode           { didSet { persist(); applyMode() } }
    var followCursor: Bool   { didSet { persist(); behavior.followCursor = followCursor; refresh() } }
    var sleepWhenIdle: Bool  { didSet { persist(); behavior.sleepWhenIdle = sleepWhenIdle
                                        if !sleepWhenIdle { behavior.reset() }; refresh() } }
    var alwaysOnTop: Bool    { didSet { persist(); panel?.setAlwaysOnTop(alwaysOnTop) } }

    /// Opt-in: drive the face with the richer Robot Personality Engine (emotions,
    /// intensity, animations) instead of the basic emotion engine. Off → legacy
    /// behavior, byte-for-byte. On → also loads the Personality Model so emotions
    /// are classified by the tiny LLM (with a rules fallback).
    var livelyPersonality: Bool {
        didSet {
            persist()
            applyPersonalityConfig()
            if livelyPersonality {
                if !personalityModel.isLoaded { loadPersonalityModel() }
            } else {
                unloadPersonalityModel()
            }
            refresh()
        }
    }

    /// The Personality Model used to classify emotions. Persisted; reloads if a
    /// different one is picked while resident.
    var personalityModelSelection: LocalModelConfig {
        didSet {
            guard personalityModelSelection != oldValue else { return }
            persist()
            personalityModel.selectedModel = personalityModelSelection
            if livelyPersonality { loadPersonalityModel() }
        }
    }

    /// Mirrored from the SwiftUI environment.
    var reduceMotion = false { didSet { animator.reduceMotion = reduceMotion; refresh() } }

    // MARK: - Engines (shared face system)

    let animator = RobotFaceAnimator()
    let cursor = CursorTrackingService()
    let behavior = RobotBehaviorEngine()
    let emotion = RobotEmotionEngine()
    /// The tiny on-device model that classifies emotion (Personality Model). A
    /// separate MLX container from the main chat LLM — they coexist in memory.
    let personalityModel = PersonalityModelEngine()
    /// Richer, opt-in face driver (see `livelyPersonality`). When off it does
    /// nothing and the basic `emotion` engine drives the face as before. When on,
    /// it consults `personalityModel` at end-of-turn, falling back to rules.
    let personality: RobotPersonalityEngine

    /// The fused face the companion view renders.
    private(set) var faceState: RobotFaceState = .idle
    /// Smoothed head tilt (passthrough so the view tracks it via observation).
    var headTilt: Double { cursor.headTilt }

    /// Highest-priority face override, set by Voice Conversation mode for
    /// listening / transcribing / TTS-speaking. nil → let emotion/behavior win.
    var voiceState: RobotFaceState? { didSet { refresh() } }

    /// Face override from the Screenshot Understanding feature (curious /
    /// reading / thinking / speaking / result). Sits below voice but above the
    /// emotion/behavior engines. nil → not active.
    var screenshotState: RobotFaceState? { didSet { refresh() } }

    /// Real-time TTS loudness (0…1) for the tuner mouth while speaking aloud.
    var audioLevel: Float = 0

    /// When set, the companion shows a speech bubble with this text plus ✓/✗
    /// buttons, and the face becomes `.askConfirm` (red ✗ / green ✓ eyes).
    var confirmPrompt: String? {
        didSet {
            if confirmPrompt != nil { wake() }   // make sure the robot is awake/visible
            refresh()
        }
    }
    /// Called when the user taps ✓ / ✗ in the confirm bubble.
    var onConfirmAccept: (() -> Void)?
    var onConfirmDecline: (() -> Void)?

    /// Quick screenshot actions shown as buttons on the robot once OCR text is
    /// ready (empty = hidden). The view observes this.
    var screenshotActions: [ScreenshotAction] = []
    /// Called when the user taps one of those action buttons.
    var onScreenshotAction: ((ScreenshotAction) -> Void)?
    /// Called when the user taps ✗ to dismiss the action buttons (back to voice).
    var onScreenshotDismiss: (() -> Void)?

    /// Voice manager, so the robot can show Talk / Stop Listening / Stop / Mute
    /// buttons. Set in wireUp (the view reads it reactively).
    var voice: VoiceConversationManager?

    /// Invoked when the user clicks the robot (e.g. to start a voice turn).
    var onActivate: (() -> Void)?

    // MARK: - Future extension points (not implemented yet)

    /// Set to receive transcribed voice input → feed into the assistant.
    var onVoiceInput: ((String) -> Void)?
    /// Set to speak a response aloud (speech synthesis).
    var onSpeak: ((String) -> Void)?
    /// Set to receive OCR / screen-understanding observations.
    var onScreenObservation: ((String) -> Void)?

    // MARK: - Window

    private var panel: DesktopCompanionWindow?
    private let contentSize = CGSize(width: 240, height: 240)

    private var aiStateProvider: (() -> RobotFaceState)?
    private var aiContextProvider: (() -> (user: String?, assistant: String?))?

    private enum Key {
        static let enabled = "companion.enabled"
        static let mode = "companion.mode"
        static let follow = "companion.followCursor"
        static let sleep = "companion.sleepWhenIdle"
        static let onTop = "companion.alwaysOnTop"
        static let lively = "companion.livelyPersonality"
        static let personalityModel = "companion.personalityModelId"
        static let originX = "companion.originX"
        static let originY = "companion.originY"
    }

    // MARK: - Init

    override init() {
        let d = UserDefaults.standard
        // Default ON: the robot now lives only in the floating companion.
        enabled = d.object(forKey: Key.enabled) as? Bool ?? true
        mode = (d.string(forKey: Key.mode).flatMap { Mode(rawValue: $0) }) ?? .docked
        followCursor = d.object(forKey: Key.follow) as? Bool ?? true
        sleepWhenIdle = d.object(forKey: Key.sleep) as? Bool ?? true
        alwaysOnTop = d.object(forKey: Key.onTop) as? Bool ?? true
        livelyPersonality = d.object(forKey: Key.lively) as? Bool ?? false
        personalityModelSelection = (d.string(forKey: Key.personalityModel)
            .flatMap(PersonalityModelRegistry.model(withId:))) ?? PersonalityModelRegistry.default

        // The face engine consults the tiny model at end-of-turn, falling back
        // to deterministic rules whenever the model is off / not loaded / slow.
        personality = RobotPersonalityEngine(
            classifier: ModelEmotionClassifier(runner: personalityModel)
        )
        super.init()

        personalityModel.selectedModel = personalityModelSelection
        behavior.followCursor = followCursor
        behavior.sleepWhenIdle = sleepWhenIdle
        behavior.onChange = { [weak self] in self?.refresh() }
        emotion.onChange = { [weak self] in self?.refresh() }
        applyPersonalityConfig()
        personality.onChange = { [weak self] in self?.refresh() }
        cursor.onTick = { [weak self] mouse in self?.handleTick(mouse) }

        if enabled { applyEnabled() }
        // Bring the Personality Model resident if the feature was left on.
        if livelyPersonality { loadPersonalityModel() }
    }

    // MARK: - Personality Model lifecycle

    /// Build the engine config from the current toggles and apply it.
    private func applyPersonalityConfig() {
        guard livelyPersonality else { personality.config = .default; return }
        var cfg = RobotPersonalityConfig.playful
        cfg.classifier.isEnabled = true           // consult the tiny LLM at end-of-turn
        personality.config = cfg
    }

    /// Load the selected Personality Model (its own MLX container, alongside the
    /// main chat LLM). Safe to call repeatedly.
    func loadPersonalityModel() {
        let model = personalityModelSelection
        Task { await personalityModel.load(model) }
    }

    /// Free the Personality Model's memory.
    func unloadPersonalityModel() {
        Task { await personalityModel.unload() }
    }

    // MARK: - AI bridge

    /// Observe the assistant's face state and translate transitions into
    /// companion emotions. Re-arms itself after every change.
    ///
    /// `contextProvider` (optional) supplies the latest user prompt and assistant
    /// response so the Personality Model can read the conversation's emotional
    /// tone at end-of-turn. It is read only for classification, never to answer.
    func connectAI(
        stateProvider: @escaping () -> RobotFaceState,
        contextProvider: (() -> (user: String?, assistant: String?))? = nil
    ) {
        aiStateProvider = stateProvider
        aiContextProvider = contextProvider
        observeAI()
    }

    private func observeAI() {
        guard let provider = aiStateProvider else { return }
        let state = withObservationTracking {
            provider()
        } onChange: {
            Task { @MainActor [weak self] in self?.observeAI() }
        }
        handleAIState(state)
    }

    private func handleAIState(_ state: RobotFaceState) {
        // The basic emotion engine always runs (it's the fallback when the
        // personality engine is off). The personality engine is fed the same
        // moments; it no-ops while disabled. At end-of-turn we also pass the
        // conversation text so the Personality Model can read the tone.
        let ctx = aiContextProvider?()
        switch state {
        case .thinking, .loadingModel:
            emotion.prompted()
            // Pass the prompt so the model can read the user's tone while the
            // robot "thinks"; the reaction is a brief transient over thinking.
            personality.handle(.generationStarted, userInput: ctx?.user)
            behavior.noteInteraction()
        case .speaking:
            emotion.speaking();            personality.firstTokenReceived();   behavior.noteInteraction()
        case .happy:
            emotion.generationSucceeded()
            personality.handle(.generationSucceeded, userInput: ctx?.user, assistantResponse: ctx?.assistant)
            behavior.noteInteraction()
        case .error:
            emotion.generationFailed()
            personality.handle(.generationFailed, userInput: ctx?.user, assistantResponse: ctx?.assistant)
            behavior.noteInteraction()
        case .warning:
            emotion.warn();                personality.warn();                 behavior.noteInteraction()
        default:
            emotion.releaseSticky()
        }
    }

    /// Reset the idle/sleep clock without triggering activation (used by voice
    /// mode to keep the robot awake during a turn).
    func wake() { behavior.noteInteraction() }

    /// Called when the user clicks the robot: wake, then run the activation
    /// hook (e.g. start a voice turn).
    func activate() {
        wake()
        personality.interacted()
        onActivate?()
    }

    /// User tapped ✓ in the confirm bubble.
    func confirmAccept() {
        confirmPrompt = nil
        onConfirmAccept?()
    }

    /// User tapped ✗ in the confirm bubble.
    func confirmDecline() {
        confirmPrompt = nil
        onConfirmDecline?()
    }

    // MARK: - Show / hide

    private func applyEnabled() {
        enabled ? show() : hide()
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setAlwaysOnTop(alwaysOnTop)
        panel.isMovableByWindowBackground = mode.isDraggable
        panel.orderFrontRegardless()

        cursor.companionCenter = panelCenter()
        cursor.start(cadence: 1.0 / 30.0)
        behavior.reset()
        refresh()
    }

    private func hide() {
        cursor.stop()
        animator.stop()
        emotion.reset()
        personality.reset()
        panel?.orderOut(nil)
    }

    private func makePanel() -> DesktopCompanionWindow {
        let origin = restoredOrigin()
        let rect = NSRect(origin: origin, size: contentSize)
        let panel = DesktopCompanionWindow(contentRect: rect)
        panel.delegate = self
        let host = NSHostingView(rootView:
            DesktopCompanionView(manager: self).environment(\.palette, .dark))
        host.frame = NSRect(origin: .zero, size: contentSize)
        panel.contentView = host
        return panel
    }

    func shutdown() {
        cursor.stop()
        animator.stop()
        emotion.reset()
        personality.reset()
        personalityModel.shutdown()
        panel?.close()
        panel = nil
    }

    // MARK: - Settings application

    private func applyMode() {
        panel?.isMovableByWindowBackground = mode.isDraggable
    }

    // MARK: - The single tick

    private func handleTick(_ mouse: CGPoint) {
        // Keep the gaze math anchored to where the window actually is.
        cursor.companionCenter = panelCenter()

        // Wake when the pointer comes near the sleeping robot.
        if behavior.isAsleep, isNearCompanion(mouse) {
            behavior.noteInteraction()
        }

        // Drift to sleep after the quiet period (never mid-AI-task / reaction).
        let busy = emotion.activeState != nil
            || (personality.isActive && personality.hasActiveReaction)
        behavior.evaluate(blocked: busy)

        // While purely watching the cursor, push the smoothed gaze into the
        // face animator (which runs no gaze loop in this state).
        if faceState == .lookingAtCursor {
            animator.gaze = cursor.gaze
        }
    }

    // MARK: - State fusion

    private func refresh() {
        // When the personality engine is on AND actively reacting, it replaces
        // the basic `emotion` layer; otherwise we fall through to it. Either way
        // the ambient base (cursor-follow / sleep) still shows through at rest.
        let aiFace: RobotFaceState? = (personality.isActive && personality.hasActiveReaction)
            ? personality.displayState
            : emotion.activeState

        // A pending confirm beats everything: show the ✗ / ✓ face.
        let state = confirmPrompt != nil
            ? .askConfirm
            : (voiceState ?? screenshotState ?? aiFace ?? behavior.baseState)
        if state != faceState {
            faceState = state
            animator.update(for: state)
        }
        // Follow the cursor only while awake, watching, and motion is allowed.
        cursor.active = followCursor && !reduceMotion
            && state == .lookingAtCursor
        cursor.setCadence(cursor.active ? 1.0 / 30.0 : 1.0 / 4.0)
    }

    // MARK: - Geometry

    /// Seam for multi-monitor support (future): choose which screen hosts the
    /// companion. For now, the screen under the pointer or the main screen.
    private func screenForCompanion() -> NSScreen? {
        NSScreen.main
    }

    private func panelCenter() -> CGPoint {
        guard let f = panel?.frame else { return .zero }
        return CGPoint(x: f.midX, y: f.midY)
    }

    private func isNearCompanion(_ mouse: CGPoint, margin: CGFloat = 70) -> Bool {
        guard let f = panel?.frame else { return false }
        return f.insetBy(dx: -margin, dy: -margin).contains(mouse)
    }

    private func restoredOrigin() -> CGPoint {
        let d = UserDefaults.standard
        if d.object(forKey: Key.originX) != nil, d.object(forKey: Key.originY) != nil {
            let p = CGPoint(x: d.double(forKey: Key.originX), y: d.double(forKey: Key.originY))
            if let vf = screenForCompanion()?.visibleFrame,
               vf.insetBy(dx: -contentSize.width, dy: -contentSize.height).contains(p) {
                return p
            }
        }
        // Default: top-right of the main screen.
        guard let vf = screenForCompanion()?.visibleFrame else { return .zero }
        return CGPoint(x: vf.maxX - contentSize.width - 40,
                       y: vf.maxY - contentSize.height - 40)
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(enabled, forKey: Key.enabled)
        d.set(mode.rawValue, forKey: Key.mode)
        d.set(followCursor, forKey: Key.follow)
        d.set(sleepWhenIdle, forKey: Key.sleep)
        d.set(alwaysOnTop, forKey: Key.onTop)
        d.set(livelyPersonality, forKey: Key.lively)
        d.set(personalityModelSelection.id, forKey: Key.personalityModel)
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            guard let f = self.panel?.frame else { return }
            let d = UserDefaults.standard
            d.set(Double(f.origin.x), forKey: Key.originX)
            d.set(Double(f.origin.y), forKey: Key.originY)
            self.cursor.companionCenter = CGPoint(x: f.midX, y: f.midY)
        }
    }
}
