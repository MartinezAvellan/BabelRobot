//
//  LocalModelState.swift
//  BabelRobot
//
//  The strict model lifecycle state machine. Every transition the app
//  performs is validated against `canTransition(to:)` so we never end up
//  generating with no model, loading two models at once, etc.
//

import Foundation

enum LocalModelState: Equatable, Sendable {
    case unloaded
    case loading(modelId: String)
    case loaded(modelId: String)
    case generating(modelId: String)
    case unloading(modelId: String)
    case failed(message: String)

    /// The model id associated with the state, if any.
    var modelId: String? {
        switch self {
        case .unloaded, .failed:
            return nil
        case .loading(let id), .loaded(let id), .generating(let id), .unloading(let id):
            return id
        }
    }

    /// A model is resident in memory (loaded or actively generating).
    var hasResidentModel: Bool {
        switch self {
        case .loaded, .generating:
            return true
        default:
            return false
        }
    }

    /// Short human-readable label for the metrics panel.
    var label: String {
        switch self {
        case .unloaded:    return "Unloaded"
        case .loading:     return "Loading"
        case .loaded:      return "Loaded"
        case .generating:  return "Generating"
        case .unloading:   return "Unloading"
        case .failed:      return "Failed"
        }
    }

    var isBusy: Bool {
        switch self {
        case .loading, .generating, .unloading:
            return true
        default:
            return false
        }
    }

    /// Validates allowed transitions. Invalid transitions are rejected by
    /// the manager rather than silently applied.
    func canTransition(to next: LocalModelState) -> Bool {
        switch (self, next) {
        // Loading can begin only from a non-busy state with nothing resident.
        case (.unloaded, .loading), (.failed, .loading):
            return true

        case (.loading, .loaded), (.loading, .failed):
            return true

        // The user can cancel an in-progress load.
        case (.loading, .unloaded):
            return true

        // Generation requires a loaded model.
        case (.loaded, .generating):
            return true
        case (.generating, .loaded), (.generating, .failed):
            return true

        // Unloading must start from a resident (but not loading) state.
        case (.loaded, .unloading), (.failed, .unloading):
            return true
        case (.unloading, .unloaded), (.unloading, .failed):
            return true

        // Always allowed to reset to unloaded after a failure.
        case (.failed, .unloaded):
            return true

        // Idempotent no-ops.
        case (.unloaded, .unloaded):
            return true

        default:
            return false
        }
    }
}
