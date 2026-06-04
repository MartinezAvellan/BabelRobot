//
//  RobotPersonalityConfig.swift
//  BabelRobot
//
//  Tunables for the Robot Personality Engine. Two concerns live here:
//
//   1. Personality *traits* — how expressive/sleepy the robot is. These affect
//      only the deterministic rules and gesture amplitude.
//   2. The optional on-device *emotion classifier* — a tiny model that may, in
//      the future, label emotions. It is DISABLED BY DEFAULT and must be turned
//      on explicitly; the engine never loads it unless `classifier.isEnabled`.
//

import Foundation

struct RobotPersonalityConfig: Equatable, Sendable {

    // MARK: - Traits

    /// Master switch for the whole feature. When `false`, callers should keep
    /// using the legacy `RobotEmotionEngine`/`RobotBehaviorEngine` path.
    /// Defaults to `false` because this is a future, opt-in feature.
    var isEnabled: Bool = false

    /// Scales gesture amplitude / reaction intensity, 0...1. Higher = livelier.
    var expressiveness: Double = 0.7

    /// How readily the robot shows transient reactions. At 0 it stays mostly
    /// neutral; at 1 it reacts to every cue. Used to gate low-signal events.
    var reactivity: Double = 0.8

    /// Seconds of no interaction before the robot drifts to sleep.
    var sleepDelay: TimeInterval = 5 * 60

    /// How long a "success" celebration (happy/excited) is held, in seconds.
    var celebrationDuration: TimeInterval = 2.0

    // MARK: - Optional model classifier

    /// Configuration for the optional, disabled-by-default emotion classifier.
    var classifier: ModelClassifierConfig = .init()

    /// Convenience: should the engine attempt to use the model classifier?
    /// True only when the feature is on AND the classifier is explicitly enabled.
    var usesModelClassifier: Bool { isEnabled && classifier.isEnabled }

    // MARK: - Presets

    /// The shipping default: feature off; sensible traits if turned on.
    static let `default` = RobotPersonalityConfig()

    /// Lively, fast-to-react personality (deterministic rules only).
    static let playful = RobotPersonalityConfig(
        isEnabled: true,
        expressiveness: 0.95,
        reactivity: 1.0,
        sleepDelay: 8 * 60
    )

    /// Reserved, low-key personality.
    static let calm = RobotPersonalityConfig(
        isEnabled: true,
        expressiveness: 0.45,
        reactivity: 0.5,
        sleepDelay: 3 * 60
    )
}

/// Settings for the optional lightweight emotion-classification model.
///
/// IMPORTANT: This describes *architecture only*. The classifier is disabled by
/// default and the engine will not download or load any weights unless a host
/// explicitly enables it and provides a runner. See `ModelEmotionClassifier`.
struct ModelClassifierConfig: Equatable, Sendable {

    /// Must be `true` (along with `RobotPersonalityConfig.isEnabled`) before any
    /// model is considered. Defaults to `false`.
    var isEnabled: Bool = false

    /// Which tiny model to use, when enabled.
    var model: Candidate = .smolLM2_135M

    /// Sampling temperature for the classifier. Kept low for stable labels.
    var temperature: Double = 0.2

    /// Hard cap on generated tokens — the classifier only emits a tiny JSON
    /// object, so this stays small to bound latency.
    var maxTokens: Int = 64

    /// If the model hasn't produced a decision within this budget, the engine
    /// falls back to the deterministic rules so the face never stalls.
    var timeout: TimeInterval = 0.25

    /// Curated small models suitable for *emotion classification only*. None of
    /// these ever generate an assistant answer.
    enum Candidate: String, CaseIterable, Equatable, Sendable, Codable {
        case smolLM2_135M
        case smolLM2_360M
        case qwen2_5_0_5B

        /// Hugging Face repository holding MLX-quantized weights.
        var huggingFaceId: String {
            switch self {
            case .smolLM2_135M: return "mlx-community/SmolLM2-135M-Instruct-4bit"
            case .smolLM2_360M: return "mlx-community/SmolLM2-360M-Instruct-4bit"
            case .qwen2_5_0_5B: return "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
            }
        }

        var displayName: String {
            switch self {
            case .smolLM2_135M: return "SmolLM2 135M"
            case .smolLM2_360M: return "SmolLM2 360M"
            case .qwen2_5_0_5B: return "Qwen 2.5 0.5B"
            }
        }

        /// Approximate resident footprint, MB — all tiny enough to coexist with
        /// the main model.
        var approximateRAMMB: Int {
            switch self {
            case .smolLM2_135M: return 120
            case .smolLM2_360M: return 320
            case .qwen2_5_0_5B: return 450
            }
        }
    }
}
