//
//  BabelRobotTheme.swift
//  BabelRobot
//
//  Visual identity: color palettes for Light and Dark, exposed through the
//  SwiftUI environment so every view shares one consistent design language.
//

import SwiftUI

extension Color {
    /// Create a color from a 0xRRGGBB hex value.
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

/// The full set of semantic colors used across the app.
struct BabelRobotPalette: Equatable, Sendable {
    let background: Color
    let card: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let robotFace: Color
    let robotScreen: Color
    let success: Color
    let warning: Color
    let error: Color
    /// True for the dark palette (used for subtle styling decisions).
    let isDark: Bool

    static let dark = BabelRobotPalette(
        background: Color(hex: 0x05070B),
        card: Color(hex: 0x151A24),
        primaryText: Color(hex: 0xFFFFFF),
        secondaryText: Color(hex: 0xA7AAB4),
        accent: Color(hex: 0x8A3FFC),
        robotFace: Color(hex: 0xFFFFFF),   // base eye color (white); tinted per mood
        robotScreen: Color(hex: 0x000000), // black display
        success: Color(hex: 0x34C759),
        warning: Color(hex: 0xFF9F0A),
        error: Color(hex: 0xFF453A),
        isDark: true
    )

    static let light = BabelRobotPalette(
        background: Color(hex: 0xFFFFFF),
        card: Color(hex: 0xF7F7F7),
        primaryText: Color(hex: 0x111111),
        secondaryText: Color(hex: 0x5F6368),
        accent: Color(hex: 0x8A3FFC),
        robotFace: Color(hex: 0xFFFFFF),   // base eye color (white); tinted per mood
        robotScreen: Color(hex: 0x0D1220), // dark display
        success: Color(hex: 0x34C759),
        warning: Color(hex: 0xFF9F0A),
        error: Color(hex: 0xFF453A),
        isDark: false
    )
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = BabelRobotPalette.dark
}

extension EnvironmentValues {
    var palette: BabelRobotPalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Real-time TTS loudness (0…1) used to drive the speaking mouth like a tuner.
/// `nil` means "no live audio" — the mouth falls back to its looping wave.
private struct RobotAudioLevelKey: EnvironmentKey {
    static let defaultValue: Float? = nil
}

extension EnvironmentValues {
    var robotAudioLevel: Float? {
        get { self[RobotAudioLevelKey.self] }
        set { self[RobotAudioLevelKey.self] = newValue }
    }
}
