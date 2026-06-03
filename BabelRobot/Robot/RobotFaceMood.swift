//
//  RobotFaceMood.swift
//  BabelRobot
//
//  Maps the robot's current state (and the Mac's thermal state) to the color
//  of the glowing facial elements. The eyes are white at rest and shift color
//  to express what's happening:
//
//    • red     → anger / error
//    • orange  → warning, or the CPU getting hot
//    • pink    → blush (love / shy)
//    • yellow  → puzzled / confused
//    • cyan    → thinking / working with a model
//    • green   → happy
//
//  Thermal heat takes priority: when the Mac runs hot, the eyes go orange/red
//  regardless of mood, so the face doubles as a temperature indicator.
//

import SwiftUI

enum RobotFaceMood {

    // Mood colors (medium saturation — readable, not harsh neon).
    static let anger   = Color(hex: 0xFF453A)   // red
    static let warning = Color(hex: 0xFF9F0A)   // orange
    static let heat    = Color(hex: 0xFF7A1A)   // hot orange
    static let blush   = Color(hex: 0xFF6FA5)   // pink
    static let puzzled = Color(hex: 0xFFD60A)   // yellow
    static let working = Color(hex: 0x5AC8FA)   // cyan
    static let happy   = Color(hex: 0x34C759)   // green

    /// The eye / mouth color for a given state, with thermal override.
    /// `base` is the resting color (white) from the palette.
    static func color(
        for state: RobotFaceState,
        base: Color,
        thermal: ProcessInfo.ThermalState = .nominal
    ) -> Color {
        // Heat wins: a hot Mac turns the eyes warm no matter the mood.
        switch thermal {
        case .critical: return anger
        case .serious:  return heat
        default:        break
        }

        switch state {
        case .error:                                   return anger
        case .warning:                                 return warning
        case .love:                                    return blush
        case .confused:                                return puzzled
        case .thinking, .loadingModel, .unloadingModel, .lookingAtScreenshot: return working
        case .happy:                                   return happy
        case .idle, .listening, .speaking, .sleeping, .lookingAtCursor, .curious, .askConfirm:
            return base   // askConfirm colors its eyes individually (red ✗ / green ✓)
        }
    }

    /// Whether to show blush cheeks (love / shy).
    static func showsBlush(for state: RobotFaceState) -> Bool {
        state == .love
    }
}
