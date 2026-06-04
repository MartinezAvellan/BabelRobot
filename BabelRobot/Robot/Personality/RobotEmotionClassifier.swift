//
//  RobotEmotionClassifier.swift
//  BabelRobot
//
//  Strategy boundary for turning a `RobotPersonalityInput` into a
//  `RobotBehaviorDecision`. Two implementations ship:
//
//   • `DeterministicEmotionClassifier` — fast, dependency-free rules. Always on.
//   • `ModelEmotionClassifier`         — optional tiny on-device model that
//     classifies emotion ONLY. Disabled by default; falls back to the rules.
//
//  Keeping this a protocol means the engine doesn't care which is used, and the
//  model path can be added later without touching the engine or the renderer.
//

import Foundation

/// Produces a behavior decision for a moment in the robot's life.
///
/// Implementations must be pure with respect to their inputs (same input +
/// config → same decision) so behavior is predictable and testable.
protocol RobotEmotionClassifier: Sendable {
    func classify(
        _ input: RobotPersonalityInput,
        config: RobotPersonalityConfig
    ) async -> RobotBehaviorDecision
}

// MARK: - Deterministic rules (always available, zero extra cost)

/// The default classifier: a small, well-documented rule set. This is what
/// makes the robot feel alive without loading any model.
struct DeterministicEmotionClassifier: RobotEmotionClassifier {

    func classify(
        _ input: RobotPersonalityInput,
        config: RobotPersonalityConfig
    ) async -> RobotBehaviorDecision {
        decision(for: input, config: config)
    }

    /// Synchronous core — exposed so it can also serve as the fallback for the
    /// model classifier and be unit-tested without async.
    func decide(
        _ input: RobotPersonalityInput,
        config: RobotPersonalityConfig
    ) -> RobotBehaviorDecision {
        decision(for: input, config: config)
    }

    private func decision(
        for input: RobotPersonalityInput,
        config: RobotPersonalityConfig
    ) -> RobotBehaviorDecision {
        let strong = config.expressiveness.clamped(to: 0...1)
        let celebrationMs = Int(config.celebrationDuration * 1000)

        switch input.event {
        case .generationStarted:
            // Reasoning tasks read as "focused"; everything else as "thinking".
            let emotion: RobotEmotionState = input.taskType == .reasoning ? .focused : .thinking
            return RobotBehaviorDecision(emotion: emotion, intensity: 0.5 * strong)

        case .firstTokenReceived:
            // The robot starts talking: focused face with a speaking mouth.
            return RobotBehaviorDecision(
                emotion: .focused, intensity: 0.55 * strong, animation: .mouthSpeak
            )

        case .generationSucceeded:
            // Celebrate, scaled by how upbeat the user's last message felt.
            let excited = userSoundsExcited(input.userInput)
            let emotion: RobotEmotionState = excited ? .excited : .happy
            return RobotBehaviorDecision(
                emotion: emotion,
                intensity: (excited ? 0.9 : 0.7) * strong,
                animation: excited ? .pulse : .smile,
                durationMs: celebrationMs
            )

        case .generationFailed:
            // Friendly by default; only a hard/technical failure shows `error`.
            if responseLooksLikeHardError(input.assistantResponse) {
                return RobotBehaviorDecision(
                    emotion: .error, intensity: 0.9 * strong, animation: .errorShake, durationMs: 800
                )
            }
            return RobotBehaviorDecision(
                emotion: .confused, intensity: 0.7 * strong, animation: .confusedLook, durationMs: 3000
            )

        case .warningRaised:
            return RobotBehaviorDecision(
                emotion: .concerned, intensity: 0.6 * strong, animation: .headTilt, durationMs: 2500
            )

        case .idleElapsed:
            return RobotBehaviorDecision(emotion: .sleeping, intensity: 0.2, animation: .sleepBreathing)

        case .userPrompted:
            return reaction(toUserText: input.userInput, config: config)

        case .interacted, .appeared:
            // Waking / appearing: a brief curious beat, then back to neutral.
            return RobotBehaviorDecision(
                emotion: .curious, intensity: 0.4 * strong, animation: .headTilt, durationMs: 1200
            )

        case .tick:
            // Nothing notable — rest at neutral and quietly watch the cursor.
            return RobotBehaviorDecision(
                emotion: .neutral, intensity: 0.0, animation: .lookAtCursor
            )
        }
    }

    // MARK: - Text-driven reactions to a freshly submitted prompt

    private func reaction(
        toUserText text: String?,
        config: RobotPersonalityConfig
    ) -> RobotBehaviorDecision {
        let strong = config.expressiveness.clamped(to: 0...1)

        if userSoundsThankful(text) {
            return RobotBehaviorDecision(
                emotion: .happy, intensity: 0.8 * strong, animation: .smile, durationMs: 2000
            )
        }
        if userSoundsExcited(text) {
            return RobotBehaviorDecision(
                emotion: .excited, intensity: 0.85 * strong, animation: .pulse, durationMs: 1500
            )
        }
        if userIsAsking(text) {
            // A question → lean in, curious, then settle into thinking.
            return RobotBehaviorDecision(
                emotion: .curious, intensity: 0.6 * strong, animation: .headTilt, durationMs: 1500
            )
        }
        // A plain statement: acknowledge with a light thinking beat.
        return RobotBehaviorDecision(emotion: .thinking, intensity: 0.4 * strong)
    }

    // MARK: - Lightweight text heuristics (locale-aware: EN + PT + ES)

    private func userSoundsThankful(_ text: String?) -> Bool {
        guard let t = normalized(text) else { return false }
        let cues = ["thank", "thanks", "thx", "ty ", "appreciate",
                    "obrigad", "valeu", "gracias", "merci"]
        return cues.contains { t.contains($0) }
    }

    private func userIsAsking(_ text: String?) -> Bool {
        guard let t = normalized(text) else { return false }
        if t.contains("?") { return true }
        let starters = ["what", "why", "how", "when", "where", "who", "which",
                        "can ", "could ", "would ", "is ", "are ", "do ", "does ",
                        // Portuguese
                        "o que", "porque", "por que", "como", "quando", "onde",
                        "quem", "qual", "quais", "pode", "poderia",
                        // Spanish
                        "que ", "qué", "por qué", "como ", "cuando", "donde", "quien"]
        return starters.contains { t.hasPrefix($0) }
    }

    private func userSoundsExcited(_ text: String?) -> Bool {
        guard let t = normalized(text) else { return false }
        if t.contains("!") { return true }
        let cues = ["wow", "amazing", "awesome", "great job", "love it", "incrível",
                    "incrivel", "demais", "genial", "increíble"]
        return cues.contains { t.contains($0) }
    }

    private func responseLooksLikeHardError(_ text: String?) -> Bool {
        guard let t = normalized(text) else { return false }
        let cues = ["error", "failed", "exception", "out of memory", "traceback",
                    "could not", "couldn't", "erro", "falha"]
        return cues.contains { t.contains($0) }
    }

    private func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
