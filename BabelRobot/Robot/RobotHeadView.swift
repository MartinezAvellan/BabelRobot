//
//  RobotHeadView.swift
//  BabelRobot
//
//  The rounded robot head: a soft housing with an antenna and an inset
//  rounded "screen/visor" that hosts the neon facial elements.
//

import SwiftUI

struct RobotHeadView<Screen: View>: View {
    @Environment(\.palette) private var palette
    /// Accent tint for the housing edge / antenna.
    var accent: Color
    @ViewBuilder var screen: Screen

    var body: some View {
        VStack(spacing: 0) {
            antenna
            housing
        }
    }

    private var antenna: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(accent)
                .frame(width: 14, height: 14)
                .shadow(color: accent.opacity(0.6), radius: 6)
            Rectangle()
                .fill(palette.secondaryText.opacity(0.5))
                .frame(width: 4, height: 18)
        }
    }

    private var housing: some View {
        ZStack {
            // Outer head housing with a soft vertical gradient + edge stroke.
            RoundedRectangle(cornerRadius: 52, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: headColors,
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 52, style: .continuous)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 2)
                )
                .shadow(color: .black.opacity(palette.isDark ? 0.5 : 0.18), radius: 24, y: 10)

            // Inset screen / visor.
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(palette.robotScreen)
                .overlay(
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .strokeBorder(.white.opacity(palette.isDark ? 0.06 : 0.0), lineWidth: 1)
                )
                .padding(22)
                .overlay { screen }
        }
        .frame(width: 300, height: 250)
    }

    private var headColors: [Color] {
        if palette.isDark {
            return [Color(hex: 0x222A38), Color(hex: 0x161C28)]
        } else {
            return [Color(hex: 0xFFFFFF), Color(hex: 0xE7EAF1)]
        }
    }
}
