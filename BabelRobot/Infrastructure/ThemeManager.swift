//
//  ThemeManager.swift
//  BabelRobot
//
//  Tracks the user's theme preference (System / Light / Dark), persists it,
//  and drives live theme switching via `preferredColorScheme`.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class ThemeManager {

    enum Preference: String, CaseIterable, Identifiable, Sendable {
        case system, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "System"
            case .light:  return "Light"
            case .dark:   return "Dark"
            }
        }
        var symbol: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
            case .light:  return "sun.max"
            case .dark:   return "moon"
            }
        }
    }

    private static let storageKey = "BabelRobotThemePreference"

    var preference: Preference {
        didSet { UserDefaults.standard.set(preference.rawValue, forKey: Self.storageKey) }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey)
        self.preference = raw.flatMap(Preference.init(rawValue:)) ?? .system
    }

    /// Value for `.preferredColorScheme`. `nil` follows the system setting.
    var preferredColorScheme: ColorScheme? {
        switch preference {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Resolve the palette for a concrete (already-forced) color scheme.
    func palette(for scheme: ColorScheme) -> BabelRobotPalette {
        scheme == .dark ? .dark : .light
    }
}
