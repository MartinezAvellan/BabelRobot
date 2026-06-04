//
//  ModelEmotionClassifier.swift
//  BabelRobot
//
//  OPTIONAL, DISABLED-BY-DEFAULT emotion classifier backed by a tiny on-device
//  model (SmolLM2 135M/360M or Qwen 2.5 0.5B). It exists as *architecture*: the
//  prompt, the strict JSON contract, parsing, timeout, and a clean fallback are
//  all here, but no weights are loaded and no inference runs unless a host wires
//  a real `EmotionModelRunner` AND enables it in config.
//
//  Hard guarantees:
//   • It classifies emotion ONLY — it never generates an assistant answer.
//   • Without a runner (the default), it transparently uses the deterministic
//     rules, so the robot always has a face and latency never regresses.
//

import Foundation

/// The minimal seam a host must provide to actually run a tiny model. Kept tiny
/// and provider-agnostic so it can be backed by MLX (`LocalLLMManager`-style) or
/// anything else, and so this file has no heavy dependencies.
///
/// Implementations must NOT answer the user — only return raw model text for the
/// classification prompt. A `nil`/throw makes the classifier fall back to rules.
protocol EmotionModelRunner: Sendable {
    /// Run the classifier model on `prompt`, returning its raw completion (which
    /// should be the small JSON object described by `ModelEmotionClassifier`).
    func complete(
        prompt: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String
}

/// Emotion classifier that prefers a tiny model and falls back to rules.
struct ModelEmotionClassifier: RobotEmotionClassifier {

    /// The runner that performs inference. `nil` (the default) means "no model
    /// available" → always fall back to the deterministic rules.
    let runner: EmotionModelRunner?

    /// The rules used as a fallback and to seed/clamp the model's output.
    let fallback: DeterministicEmotionClassifier

    init(runner: EmotionModelRunner? = nil, fallback: DeterministicEmotionClassifier? = nil) {
        self.runner = runner
        self.fallback = fallback ?? DeterministicEmotionClassifier()
    }

    func classify(
        _ input: RobotPersonalityInput,
        config: RobotPersonalityConfig
    ) async -> RobotBehaviorDecision {
        let ruleDecision = fallback.decide(input, config: config)

        // Gate 1: feature + classifier must be explicitly enabled.
        guard config.usesModelClassifier, let runner else { return ruleDecision }

        // Gate 2: only spend tokens on ambiguous, content-bearing moments. Clear
        // lifecycle signals (start/success/fail/sleep) are already perfect from
        // the rules, so we don't pay model latency for them.
        guard shouldConsultModel(for: input) else { return ruleDecision }

        // Run with a strict timeout; on miss/throw, keep the rule decision so the
        // face never stalls waiting on the model.
        let prompt = Self.buildPrompt(for: input)
        do {
            let raw = try await withTimeout(config.classifier.timeout) {
                try await runner.complete(
                    prompt: prompt,
                    maxTokens: config.classifier.maxTokens,
                    temperature: config.classifier.temperature
                )
            }
            if let parsed = Self.parse(raw) {
                return parsed
            }
        } catch {
            // Swallow: classification is best-effort decoration, never critical.
        }
        return ruleDecision
    }

    /// Only consult the model when the user's words carry nuance the rules can't
    /// fully capture (long, content-bearing prompts).
    private func shouldConsultModel(for input: RobotPersonalityInput) -> Bool {
        guard input.event == .userPrompted || input.event == .generationSucceeded else { return false }
        let words = (input.userInput ?? "").split(whereSeparator: { $0.isWhitespace })
        return words.count >= 4
    }

    // MARK: - Prompt + strict JSON contract

    /// System instruction: the model is a *classifier*, not an assistant.
    static let systemPrompt = """
    You are the emotion module of a small desktop robot. You do NOT answer the \
    user. You only decide how the robot should feel about the current moment.
    Reply with ONE JSON object and nothing else, in exactly this shape:
    {"emotion": <one of: \(RobotEmotionState.allCases.map(\.rawValue).joined(separator: ", "))>, \
    "intensity": <0.0-1.0>, \
    "animation": <one of: \(RobotAnimationIntent.allCases.map(\.rawValue).joined(separator: ", "))>, \
    "durationMs": <integer milliseconds>}
    Keep durationMs between 500 and 4000. Do not add explanations.
    """

    static func buildPrompt(for input: RobotPersonalityInput) -> String {
        var lines = [systemPrompt, "", "Context:"]
        lines.append("- event: \(input.event.rawValue)")
        lines.append("- task: \(input.taskType.rawValue)")
        if let u = input.userInput, !u.isEmpty {
            lines.append("- user said: \"\(u.prefix(280))\"")
        }
        if let a = input.assistantResponse, !a.isEmpty {
            lines.append("- robot replied: \"\(a.prefix(280))\"")
        }
        lines.append("")
        lines.append("JSON:")
        return lines.joined(separator: "\n")
    }

    /// Parse the model's reply, tolerating leading/trailing prose by extracting
    /// the first balanced `{...}` object. Returns `nil` if nothing usable.
    static func parse(_ raw: String) -> RobotBehaviorDecision? {
        guard let json = firstJSONObject(in: raw),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RobotBehaviorDecision.self, from: data)
    }

    /// Extract the first top-level `{ ... }` substring from arbitrary text.
    private static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var idx = start
        while idx < text.endIndex {
            let ch = text[idx]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...idx]) }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    // MARK: - Timeout helper

    private enum ClassifierError: Error { case timedOut }

    /// Run `operation`, returning its result, or throw `timedOut` after `seconds`.
    private func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ClassifierError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw ClassifierError.timedOut }
            return first
        }
    }
}
