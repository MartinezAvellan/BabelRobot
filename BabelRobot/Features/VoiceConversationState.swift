//
//  VoiceConversationState.swift
//  BabelRobot
//
//  The state machine for a single voice conversation turn:
//
//    idle → requestingMicrophonePermission → listening → transcribing
//         → thinking → speaking → idle   (any step → error → idle)
//

import Foundation

enum VoiceConversationState: Equatable, Sendable {
    case idle
    case requestingMicrophonePermission
    case listening
    case transcribing
    case thinking
    case speaking
    case error(String)

    /// User-facing status line.
    var message: String {
        switch self {
        case .idle:                            return "Tap the robot or press Talk to speak."
        case .requestingMicrophonePermission:  return "Requesting microphone access…"
        case .listening:                       return "Listening…"
        case .transcribing:                    return "Transcribing…"
        case .thinking:                        return "Thinking…"
        case .speaking:                        return "Speaking…"
        case .error(let message):              return message
        }
    }

    /// True while a turn is active (used to gate "start a new turn").
    var isActive: Bool {
        switch self {
        case .idle, .error: return false
        default:            return true
        }
    }

    /// The robot face to show for this voice state. `nil` means "don't
    /// override" — let the LLM/behavior engines decide (used during thinking,
    /// where the generation bridge already drives thinking/speaking).
    var faceOverride: RobotFaceState? {
        switch self {
        case .listening:    return .listening
        case .transcribing: return .listening   // attentive / focused eyes
        case .speaking:     return .speaking     // TTS playback → animate mouth
        case .error:        return .confused
        case .idle, .requestingMicrophonePermission, .thinking:
            return nil
        }
    }
}
