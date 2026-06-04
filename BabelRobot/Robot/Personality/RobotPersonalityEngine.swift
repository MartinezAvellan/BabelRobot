//
//  RobotPersonalityEngine.swift
//  BabelRobot
//
//  The Robot Personality Engine: gives the robot a life of its own, separate
//  from the main LLM. It turns lifecycle events (prompt sent, first token, done,
//  failed, idle, …) into a `RobotBehaviorDecision` — an emotion, an intensity,
//  an animation and a hold duration — and projects that onto a `RobotFaceState`
//  the existing renderer draws.
//
//  Design rules (see the feature spec):
//   • It NEVER answers the user. It only decides how the robot behaves.
//   • Deterministic rules run first and are always sufficient on their own.
//   • An optional tiny model classifier exists but is DISABLED by default and is
//     only consulted for ambiguous, content-bearing moments.
//   • Transient reactions auto-clear back to neutral; sticky ones (thinking,
//     focused, sleeping) hold until the next event supersedes them.
//
//  Integration: this is an opt-in, additive layer. The legacy
//  `RobotEmotionEngine`/`RobotBehaviorEngine` path is untouched; a host can adopt
//  this engine by feeding it the same lifecycle events and reading
//  `displayState` for the face. See README "Robot Personality Engine".
//

import Foundation
import Observation

@MainActor
@Observable
final class RobotPersonalityEngine {

    // MARK: - Public, observable state

    /// The current full decision (emotion + intensity + animation + duration).
    private(set) var decision: RobotBehaviorDecision = .neutral

    /// The face the renderer should draw right now. While a transient reaction
    /// is active it reflects that emotion; otherwise it falls back to the ambient
    /// base state (idle / watching / sleeping).
    var displayState: RobotFaceState {
        activeReaction?.faceState ?? baseState.faceState
    }

    /// Fired whenever `decision`/`displayState` may have changed, so a host can
    /// re-sync the face animator. Mirrors the legacy engines' `onChange` seam.
    var onChange: (() -> Void)?

    /// Live configuration. Swapping presets at runtime is safe.
    var config: RobotPersonalityConfig {
        didSet { if config != oldValue { reevaluateAmbient() } }
    }

    // MARK: - Private state

    /// The current transient reaction (happy, confused, …), or `nil` when the
    /// robot is at its ambient baseline.
    private var activeReaction: RobotBehaviorDecision?

    /// The ambient baseline emotion (neutral while awake, sleeping when idle).
    private var baseState: RobotEmotionState = .neutral

    /// The task type the host last reported (biases some reactions).
    private var taskType: RobotTaskType = .idle

    /// Auto-clear timer for transient reactions.
    private var clearTask: Task<Void, Never>?

    /// In-flight classification, cancelled if a newer event arrives.
    private var classifyTask: Task<Void, Never>?

    private let classifier: RobotEmotionClassifier

    // MARK: - Init

    /// - Parameters:
    ///   - config: traits + (disabled-by-default) model classifier settings.
    ///     `nil` uses `RobotPersonalityConfig.default`.
    ///   - classifier: strategy used to choose decisions. `nil` uses the
    ///     deterministic rules; pass a `ModelEmotionClassifier` (with a runner)
    ///     to opt into the tiny-model path.
    ///
    /// The defaults are resolved inside this `@MainActor` initializer rather than
    /// as default arguments, so referencing them never crosses into a nonisolated
    /// default-argument context under main-actor-by-default isolation.
    init(
        config: RobotPersonalityConfig? = nil,
        classifier: RobotEmotionClassifier? = nil
    ) {
        self.config = config ?? .default
        self.classifier = classifier ?? DeterministicEmotionClassifier()
    }

    // MARK: - Event hooks (called from the AI bridge / companion)
    //
    // These mirror the lifecycle the existing app already emits, so adopting the
    // engine is a matter of forwarding the same moments.

    func appeared()              { handle(.appeared) }
    func userPrompted(_ text: String?) { handle(.userPrompted, userInput: text) }
    func generationStarted()     { handle(.generationStarted) }
    func firstTokenReceived()    { handle(.firstTokenReceived) }
    func generationSucceeded(userInput: String? = nil) {
        handle(.generationSucceeded, userInput: userInput)
    }
    func generationFailed(response: String? = nil) {
        handle(.generationFailed, assistantResponse: response)
    }
    func warn()                  { handle(.warningRaised) }
    func idleElapsed()           { handle(.idleElapsed) }
    func interacted()            { handle(.interacted) }

    /// Update the kind of task in progress (affects how some events read).
    func setTask(_ task: RobotTaskType) { taskType = task }

    /// Forcefully drop any transient reaction and return to the ambient baseline.
    func reset() {
        clearTask?.cancel(); clearTask = nil
        classifyTask?.cancel(); classifyTask = nil
        activeReaction = nil
        baseState = .neutral
        publish()
    }

    // MARK: - Core handling

    /// Build the input for `event`, classify it, and apply the resulting
    /// decision. Disabled-feature is a no-op so hosts can wire it eagerly.
    func handle(
        _ event: RobotLifecycleEvent,
        userInput: String? = nil,
        assistantResponse: String? = nil
    ) {
        guard config.isEnabled else { return }

        let input = RobotPersonalityInput(
            event: event,
            userInput: userInput,
            assistantResponse: assistantResponse,
            currentState: displayState,
            taskType: taskType
        )

        // Ambient (sleep/wake) is updated synchronously so the base face is
        // always correct even if classification is async.
        applyAmbient(for: event)

        // Newer event wins: cancel any pending classification.
        classifyTask?.cancel()
        classifyTask = Task { [weak self] in
            guard let self else { return }
            let decision = await self.classifier.classify(input, config: self.config)
            if Task.isCancelled { return }
            self.apply(decision)
        }
    }

    // MARK: - Applying decisions

    private func apply(_ decision: RobotBehaviorDecision) {
        clearTask?.cancel(); clearTask = nil

        if decision.emotion == .sleeping {
            // Sleeping is an ambient base, not a transient reaction.
            baseState = .sleeping
            activeReaction = nil
            publish(decision)
            return
        }

        if decision.emotion == .neutral {
            // Back to baseline; let the ambient state show through.
            activeReaction = nil
            publish(decision)
            return
        }

        activeReaction = decision

        // Sticky emotions (thinking/focused) hold until the next event. Others
        // auto-clear after their duration, scaled gently by intensity.
        if !decision.emotion.isSticky, let base = decision.duration {
            let hold = base * (0.7 + 0.6 * decision.intensity) // 0.7x…1.3x
            scheduleClear(after: hold)
        }
        publish(decision)
    }

    private func applyAmbient(for event: RobotLifecycleEvent) {
        switch event {
        case .idleElapsed:
            baseState = .sleeping
        case .interacted, .appeared, .userPrompted, .generationStarted,
             .firstTokenReceived, .generationSucceeded, .generationFailed, .warningRaised:
            if baseState == .sleeping { baseState = .neutral }
        case .tick:
            break
        }
    }

    private func scheduleClear(after seconds: TimeInterval) {
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            guard let self else { return }
            self.activeReaction = nil
            self.publish(.neutral)
        }
    }

    private func reevaluateAmbient() {
        if !config.isEnabled { reset() } else { publish() }
    }

    /// Update the observable `decision` and notify the host.
    private func publish(_ newDecision: RobotBehaviorDecision? = nil) {
        let resolved = newDecision
            ?? activeReaction
            ?? RobotBehaviorDecision(emotion: baseState, intensity: 0.0)
        if resolved != decision {
            decision = resolved
        }
        onChange?()
    }
}
