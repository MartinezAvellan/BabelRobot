//
//  RobotFaceState.swift
//  BabelRobot
//
//  The expressive states of the robot face. Derived from the assistant /
//  model lifecycle by RobotAssistantViewModel.
//

import Foundation

enum RobotFaceState: Equatable, Sendable, CaseIterable {
    case idle
    case listening
    case thinking
    case speaking
    case happy
    case love
    case warning
    case error
    case confused
    case sleeping
    case loadingModel
    case unloadingModel
    /// Awake and idle, but the pupils/head track the cursor (companion mode).
    case lookingAtCursor

    /// Short caption shown under the face.
    var caption: String {
        switch self {
        case .idle:           return "Ready"
        case .listening:      return "Listening…"
        case .thinking:       return "Thinking…"
        case .speaking:       return "Speaking…"
        case .happy:          return "Done!"
        case .love:           return "Glad to help"
        case .warning:        return "Heads up"
        case .error:          return "Something went wrong"
        case .confused:       return "Hmm…"
        case .sleeping:       return "Sleeping"
        case .loadingModel:   return "Loading model…"
        case .unloadingModel: return "Unloading model…"
        case .lookingAtCursor: return "Watching"
        }
    }
}
