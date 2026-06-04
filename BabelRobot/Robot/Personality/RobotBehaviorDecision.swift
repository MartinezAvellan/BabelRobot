//
//  RobotBehaviorDecision.swift
//  BabelRobot
//
//  The single, self-contained output of the Robot Personality Engine: how the
//  robot should feel and move right now. It carries everything a renderer needs
//  and nothing about the assistant's answer.
//
//  It is `Codable` in exactly the shape the optional model classifier emits:
//
//      {
//        "emotion": "concerned",
//        "intensity": 0.7,
//        "animation": "headTilt",
//        "durationMs": 2500
//      }
//
//  `faceState` is *derived* from `emotion`, so it is not part of the JSON.
//

import Foundation

/// A complete, ready-to-render behavior decision.
struct RobotBehaviorDecision: Equatable, Sendable, Codable {

    /// What the robot feels.
    let emotion: RobotEmotionState

    /// How strongly, 0...1. Scales gesture amplitude and (optionally) hold time.
    let intensity: Double

    /// The motion the face should perform.
    let animation: RobotAnimationIntent

    /// How long to hold this reaction, in milliseconds. `nil` means "hold until
    /// superseded" (sticky / ambient emotions such as thinking or sleeping).
    let durationMs: Int?

    /// The concrete face the existing renderer should draw. Derived from
    /// `emotion`; never decoded or encoded.
    var faceState: RobotFaceState { emotion.faceState }

    /// Convenience: the hold duration as a `TimeInterval`, or `nil` if sticky.
    var duration: TimeInterval? {
        guard let durationMs else { return nil }
        return TimeInterval(durationMs) / 1000.0
    }

    /// The emotionally-neutral resting decision.
    static let neutral = RobotBehaviorDecision(
        emotion: .neutral,
        intensity: 0.0,
        animation: .blink,
        durationMs: nil
    )

    init(
        emotion: RobotEmotionState,
        intensity: Double,
        animation: RobotAnimationIntent? = nil,
        durationMs: Int? = nil
    ) {
        self.emotion = emotion
        self.intensity = intensity.clamped(to: 0...1)
        let resolvedAnimation = animation ?? emotion.defaultAnimation
        self.animation = resolvedAnimation
        // Fall back to the animation's own default hold time when unspecified.
        self.durationMs = durationMs ?? resolvedAnimation.defaultDurationMs
    }

    // MARK: - Codable (tolerant of the model's free-form JSON)

    private enum CodingKeys: String, CodingKey {
        case emotion, intensity, animation, durationMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let emotion = try c.decode(RobotEmotionState.self, forKey: .emotion)
        let intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.5
        // The model may omit the animation or send an unknown one — fall back to
        // the emotion's natural gesture rather than failing the whole decode.
        let animation = (try? c.decodeIfPresent(RobotAnimationIntent.self, forKey: .animation))
            .flatMap { $0 } ?? emotion.defaultAnimation
        let durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        self.init(
            emotion: emotion,
            intensity: intensity,
            animation: animation,
            durationMs: durationMs
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(emotion, forKey: .emotion)
        try c.encode(intensity, forKey: .intensity)
        try c.encode(animation, forKey: .animation)
        try c.encodeIfPresent(durationMs, forKey: .durationMs)
    }
}

// MARK: - Small numeric helper

extension Comparable {
    /// Clamp a value into a closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
