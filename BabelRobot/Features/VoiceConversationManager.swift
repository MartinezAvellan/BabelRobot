//
//  VoiceConversationManager.swift
//  BabelRobot
//
//  Orchestrates one voice turn end-to-end:
//
//    click/hotkey → permissions → listen → transcribe → local LLM → speak → idle
//
//  It owns the speech, TTS, permission, and hotkey services and is wired to the
//  rest of the app through closures (no hard references), so it stays testable
//  and the LLM call remains the existing fully-local path.
//
//  Concurrency: only one turn at a time. Starting a new turn cancels any
//  in-flight listening, generation, and speech first.
//
//  Privacy: audio is never written to disk; transcripts are not persisted.
//  On-device speech is forced when the locale supports it; otherwise the UI
//  notes that Apple's speech system may be used. LLM inference stays local.
//

import SwiftUI
import Observation
import AVFoundation

@MainActor
@Observable
final class VoiceConversationManager {

    // MARK: - Services

    let permissions = MicrophonePermissionManager()
    let recognizer = SpeechRecognitionService()
    let tts = TextToSpeechService()
    let hotkey = VoiceHotkeyManager()

    // MARK: - State (observed by the UI)

    private(set) var state: VoiceConversationState = .idle
    private(set) var transcript = ""

    // MARK: - Settings (persisted)

    var enabled: Bool       { didSet { persist(); if !enabled { cancelActive() } } }
    var pushToTalk: Bool    { didSet { persist() } }
    var autoSpeak: Bool     { didSet { persist() } }
    var muted: Bool         { didSet { persist(); tts.muted = muted } }
    var volume: Double      { didSet { persist(); tts.volume = Float(volume) } }
    /// BCP-47 speech language, e.g. "en-US".
    var speechLanguage: String { didSet { persist() } }
    /// AVSpeechUtterance rate (≈0.3 slow … 0.7 fast; 0.5 default).
    var speechRate: Double  { didSet { persist(); tts.rate = Float(speechRate) } }
    /// Chosen voice identifier; nil → best default for the language.
    var voiceIdentifier: String? { didSet { persist(); tts.voiceIdentifier = voiceIdentifier } }

    private var locale: Locale { Locale(identifier: speechLanguage) }

    /// Buffers streamed tokens until a full sentence is ready to speak.
    private var pendingSentence = ""

    // MARK: - Wiring (set once at app start)

    /// Run the prompt on the local LLM, returning the full response or nil.
    var generate: ((String) async -> String?)?
    /// Streaming variant: forwards each token delta to `onChunk` (for
    /// speaking while the model is still writing). Returns the full response.
    var generateStreaming: ((String, @escaping @MainActor (String) -> Void) async -> String?)?
    /// Whether a model is currently loaded.
    var isModelLoaded: (() -> Bool)?
    /// Cancel any in-flight LLM generation.
    var cancelGeneration: (() -> Void)?
    /// Push the current robot face override to the companion.
    var applyFaceOverride: ((RobotFaceState?) -> Void)?
    /// Keep the companion awake during a turn.
    var keepAwake: (() -> Void)?

    private var turnTask: Task<Void, Never>?
    private var idleResetTask: Task<Void, Never>?

    /// True when the chosen language transcribes entirely on-device.
    var usesOnDeviceRecognition: Bool { recognizer.supportsOnDevice(locale: locale) }

    /// UI helpers.
    var isError: Bool { if case .error = state { return true } else { return false } }
    var isListeningState: Bool { state == .listening || state == .transcribing }

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: Key.enabled)
        pushToTalk = d.object(forKey: Key.pushToTalk) as? Bool ?? true
        autoSpeak = d.object(forKey: Key.autoSpeak) as? Bool ?? true
        muted = d.object(forKey: Key.muted) as? Bool ?? false
        volume = d.object(forKey: Key.volume) as? Double ?? 1.0
        speechLanguage = d.string(forKey: Key.language) ?? (Locale.current.identifier)
        speechRate = d.object(forKey: Key.rate) as? Double ?? Double(AVSpeechUtteranceDefaultSpeechRate)
        voiceIdentifier = d.string(forKey: Key.voice)

        tts.muted = muted
        tts.volume = Float(volume)
        tts.rate = Float(speechRate)
        tts.voiceIdentifier = voiceIdentifier

        recognizer.onFinal = { [weak self] text in self?.handleTranscript(text) }
        recognizer.onError = { [weak self] error in self?.fail(error) }
        tts.onStart = { [weak self] in self?.setState(.speaking) }
        tts.onFinish = { [weak self] in self?.finishTurn() }

        // Hotkey architecture is prepared but left disabled (see VoiceHotkeyManager).
        hotkey.onTrigger = { [weak self] in self?.toggleTalk() }
    }

    // MARK: - Public controls

    /// Primary entry point: the robot click, the Talk button, or the hotkey.
    func toggleTalk() {
        switch state {
        case .listening, .transcribing: stopListening()
        case .speaking:                 stopSpeaking()
        case .thinking:                 break          // let it finish
        default:                        startTalking()
        }
    }

    func startTalking() {
        guard enabled else { return }
        cancelActive()
        turnTask = Task { await beginTurn() }
    }

    func stopListening() {
        recognizer.stop()   // delivers onFinal with whatever we have
    }

    func stopSpeaking() {
        tts.stop()          // delivers onFinish → idle
    }

    func toggleMute() { muted.toggle() }

    /// Cancel any active listening / generation / speech (new turn or disable).
    func cancelActive() {
        idleResetTask?.cancel()
        turnTask?.cancel()
        recognizer.cancel()
        tts.stop()
        cancelGeneration?()
        setState(.idle)
    }

    func shutdown() {
        cancelActive()
        hotkey.disable()
    }

    // MARK: - Turn pipeline

    private func beginTurn() async {
        keepAwake?()

        if !permissions.bothGranted {
            setState(.requestingMicrophonePermission)
            do {
                try await permissions.requestAll()
            } catch {
                fail(error)
                return
            }
        }

        guard isModelLoaded?() == true else {
            fail(VoiceError.noModelLoaded)
            return
        }

        startListening()
    }

    private func startListening() {
        transcript = ""
        recognizer.silenceTimeout = 2.0
        recognizer.maxDuration = 30.0
        do {
            setState(.listening)
            try recognizer.start(locale: locale)
        } catch {
            fail(error)
        }
    }

    private func handleTranscript(_ text: String) {
        keepAwake?()
        guard text.isEmpty == false else {
            fail(VoiceError.noSpeechDetected)
            return
        }
        transcript = text
        setState(.transcribing)
        turnTask = Task { await generateAndSpeak(prompt: text) }
    }

    private func generateAndSpeak(prompt: String) async {
        guard isModelLoaded?() == true else {
            fail(VoiceError.noModelLoaded)
            return
        }
        // Override clears → the generation bridge drives thinking/speaking on
        // the companion as tokens stream.
        setState(.thinking)
        keepAwake?()

        let willSpeak = autoSpeak && !muted
        pendingSentence = ""
        if willSpeak {
            configureTTS()
            tts.startStream()   // tts.onStart will flip the face to .speaking
        }

        // Stream the response; speak each complete sentence as it arrives.
        let response = await generateStreaming?(prompt) { [weak self] chunk in
            guard let self, willSpeak else { return }
            self.pendingSentence += chunk
            for sentence in self.drainSentences() {
                self.tts.enqueue(sentence)
            }
        }

        if Task.isCancelled {
            if willSpeak { tts.stop() }
            return
        }
        guard let response, !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if willSpeak { tts.stop() }
            fail(VoiceError.generationFailed)
            return
        }

        if willSpeak {
            // Flush any trailing text and close the queue; onFinish → finishTurn.
            let rest = pendingSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { tts.enqueue(rest) }
            pendingSentence = ""
            tts.finishStream()
        } else {
            finishTurn()
        }
    }

    /// Push current voice settings onto the synthesizer before a turn.
    private func configureTTS() {
        tts.languageCode = speechLanguage
        tts.voiceIdentifier = voiceIdentifier
        tts.rate = Float(speechRate)
        tts.volume = Float(volume)
        tts.muted = muted
    }

    /// Pull speakable chunks out of `pendingSentence` as the model streams, so
    /// speech starts WHILE it's still writing (not after it finishes).
    ///
    /// We emit only on real sentence boundaries. Speaking each whole sentence
    /// keeps the synthesizer's prosody intact; splitting mid-clause (e.g. on
    /// commas) makes the playback stutter, because every separate utterance
    /// resets intonation and adds a micro-gap.
    private func drainSentences() -> [String] {
        var sentences: [String] = []
        let enders: Set<Character> = [".", "!", "?", "…", "\n"]

        // Emit every complete sentence immediately (no minimum length — a short
        // opening sentence must NOT block everything behind it).
        while let idx = pendingSentence.firstIndex(where: { enders.contains($0) }) {
            let upto = pendingSentence.index(after: idx)
            let sentence = String(pendingSentence[..<upto]).trimmingCharacters(in: .whitespacesAndNewlines)
            pendingSentence = String(pendingSentence[upto...])
            if !sentence.isEmpty { sentences.append(sentence) }
        }

        // Pathological run-on with no sentence punctuation at all: flush a large
        // chunk at the last space so we don't buffer forever. The threshold is
        // high so normal prose is never split mid-thought.
        if pendingSentence.count > 220, let sp = pendingSentence.lastIndex(of: " ") {
            let sentence = String(pendingSentence[..<sp]).trimmingCharacters(in: .whitespacesAndNewlines)
            pendingSentence = String(pendingSentence[pendingSentence.index(after: sp)...])
            if !sentence.isEmpty { sentences.append(sentence) }
        }
        return sentences
    }

    private func finishTurn() {
        keepAwake?()
        setState(.idle)
    }

    private func fail(_ error: Error) {
        recognizer.cancel()
        tts.stop()
        let message = (error as? VoiceError)?.errorDescription
            ?? (error as? LocalizedError)?.errorDescription
            ?? "Local generation failed. Please try again."
        setState(.error(message))
        scheduleIdleReset(after: 3)
    }

    // MARK: - State plumbing

    private func setState(_ newState: VoiceConversationState) {
        state = newState
        applyFaceOverride?(newState.faceOverride)
    }

    private func scheduleIdleReset(after seconds: Double) {
        idleResetTask?.cancel()
        idleResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if case .error = self.state { self.setState(.idle) }
        }
    }

    // MARK: - Persistence

    private enum Key {
        static let enabled = "voice.enabled"
        static let pushToTalk = "voice.pushToTalk"
        static let autoSpeak = "voice.autoSpeak"
        static let muted = "voice.muted"
        static let volume = "voice.volume"
        static let language = "voice.language"
        static let rate = "voice.rate"
        static let voice = "voice.voiceId"
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(enabled, forKey: Key.enabled)
        d.set(pushToTalk, forKey: Key.pushToTalk)
        d.set(autoSpeak, forKey: Key.autoSpeak)
        d.set(muted, forKey: Key.muted)
        d.set(volume, forKey: Key.volume)
        d.set(speechLanguage, forKey: Key.language)
        d.set(speechRate, forKey: Key.rate)
        d.set(voiceIdentifier, forKey: Key.voice)
    }
}
