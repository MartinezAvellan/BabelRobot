//
//  RobotEmotionState.swift
//  BabelRobot
//
//  The personality layer's emotional vocabulary. This is intentionally richer
//  and more "felt" than `RobotFaceState` (which is a rendering concern): the
//  Personality Engine reasons in terms of emotions, then projects each one down
//  onto a concrete face the existing renderer already knows how to draw.
//
//  This type is part of the Robot Personality Engine and is completely
//  independent of the main LLM (`LocalLLMManager`). It never produces an answer
//  for the user — only how the robot should *feel* about what's happening.
//

import Foundation

/// A discrete emotion the robot can express. Raw values are stable, lowercase
/// strings so they round-trip through the optional model classifier's JSON
/// (e.g. `{"emotion": "concerned", ...}`).
enum RobotEmotionState: String, CaseIterable, Equatable, Sendable, Codable {
    case neutral
    case happy
    case excited
    case curious
    case thinking
    case confused
    case concerned
    case error
    case sleeping
    case focused
    case surprised

    // MARK: - Projection onto the renderable face

    /// The concrete `RobotFaceState` the existing face renderer should draw for
    /// this emotion. Several personality emotions deliberately collapse onto the
    /// same face — the *animation intent* and *intensity* carry the nuance.
    var faceState: RobotFaceState {
        switch self {
        case .neutral:   return .idle
        case .happy:     return .happy
        case .excited:   return .happy
        case .curious:   return .curious
        case .thinking:  return .thinking
        case .confused:  return .confused
        case .concerned: return .warning
        case .error:     return .error
        case .sleeping:  return .sleeping
        case .focused:   return .thinking
        case .surprised: return .curious
        }
    }

    /// The animation that most naturally accompanies this emotion. Rules and the
    /// model classifier may override it, but this is the sensible default.
    var defaultAnimation: RobotAnimationIntent {
        switch self {
        case .neutral:   return .blink
        case .happy:     return .smile
        case .excited:   return .pulse
        case .curious:   return .headTilt
        case .thinking:  return .loadingPulse
        case .confused:  return .confusedLook
        case .concerned: return .headTilt
        case .error:     return .errorShake
        case .sleeping:  return .sleepBreathing
        case .focused:   return .mouthSpeak
        case .surprised: return .pulse
        }
    }

    // MARK: - Persistence semantics

    /// `sticky` emotions hold until the next event supersedes them (the robot is
    /// busy or asleep). Non-sticky emotions are transient reactions that auto-
    /// clear back to `neutral` after their `durationMs` elapses.
    var isSticky: Bool {
        switch self {
        case .thinking, .focused, .sleeping: return true
        default:                             return false
        }
    }

    /// Rough emotional valence in -1...1 (negative = unhappy). Useful for
    /// blending, analytics, or future trait-based behavior.
    var valence: Double {
        switch self {
        case .happy:     return 0.9
        case .excited:   return 0.8
        case .curious:   return 0.4
        case .surprised: return 0.2
        case .neutral:   return 0.0
        case .thinking:  return 0.0
        case .focused:   return 0.1
        case .sleeping:  return 0.0
        case .confused:  return -0.3
        case .concerned: return -0.5
        case .error:     return -0.8
        }
    }

    /// A short, friendly caption suitable for an accessibility label or tooltip.
    var caption: String {
        switch self {
        case .neutral:   return "Calm"
        case .happy:     return "Happy"
        case .excited:   return "Excited"
        case .curious:   return "Curious"
        case .thinking:  return "Thinking"
        case .confused:  return "Puzzled"
        case .concerned: return "Concerned"
        case .error:     return "Something went wrong"
        case .sleeping:  return "Sleeping"
        case .focused:   return "Focused"
        case .surprised: return "Surprised"
        }
    }
}
