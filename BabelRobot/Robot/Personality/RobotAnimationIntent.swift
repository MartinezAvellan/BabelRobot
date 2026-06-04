//
//  RobotAnimationIntent.swift
//  BabelRobot
//
//  The motion vocabulary the Personality Engine can ask the face to perform.
//  An *intent* is a request ("tilt your head"), not the animation itself — the
//  existing `RobotFaceAnimator` owns the actual SwiftUI motion. Keeping intents
//  separate lets the personality layer stay UI-free and fully testable.
//

import Foundation

/// A requested face animation. Raw values are stable camelCase strings so they
/// round-trip through the optional model classifier's JSON
/// (e.g. `{"animation": "headTilt", ...}`).
enum RobotAnimationIntent: String, CaseIterable, Equatable, Sendable, Codable {
    case blink
    case lookAtCursor
    case headTilt
    case pulse
    case smile
    case mouthSpeak
    case confusedLook
    case sleepBreathing
    case loadingPulse
    case errorShake

    /// A sensible default duration (ms) for the gesture when a rule or the model
    /// doesn't specify one. Sticky/ambient motions report `nil` (they run until
    /// the next emotion supersedes them).
    var defaultDurationMs: Int? {
        switch self {
        case .blink:         return 150
        case .lookAtCursor:  return nil   // continuous, ambient
        case .headTilt:      return 2_500
        case .pulse:         return 1_200
        case .smile:         return 2_000
        case .mouthSpeak:    return nil   // runs while speaking
        case .confusedLook:  return 3_000
        case .sleepBreathing: return nil  // continuous, ambient
        case .loadingPulse:  return nil   // runs while working
        case .errorShake:    return 700
        }
    }

    /// Whether the gesture is ambient (loops until replaced) rather than a
    /// one-shot reaction. Ambient gestures pair with `sticky` emotions.
    var isAmbient: Bool { defaultDurationMs == nil }
}
