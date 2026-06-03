//
//  RobotMouthView.swift
//  BabelRobot
//
//  The robot's mouth, a glowing neon element that reshapes per state.
//

import SwiftUI
import Combine

struct RobotMouthView: View {
    let state: RobotFaceState
    let color: Color
    /// True while the speaking oscillation is active (animatable).
    let speaking: Bool
    var width: CGFloat = 76

    var body: some View {
        content
            .foregroundStyle(color)
            .frame(height: width * 0.5)
            // Gentle glow (toned down — was too neon).
            .shadow(color: color.opacity(0.3), radius: 4)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .happy, .love:
            Curve(curvature: 0.8)
                .stroke(color, style: .init(lineWidth: 7, lineCap: .round))
                .frame(width: width, height: width * 0.34)

        case .sleeping:
            Curve(curvature: 0.35)
                .stroke(color.opacity(0.8), style: .init(lineWidth: 6, lineCap: .round))
                .frame(width: width * 0.55, height: width * 0.18)

        case .confused:
            WaveShape()
                .stroke(color, style: .init(lineWidth: 6, lineCap: .round))
                .frame(width: width * 0.7, height: width * 0.2)

        case .error:
            // Low flat line "_".
            Capsule().fill(color)
                .frame(width: width * 0.6, height: 6)
                .offset(y: width * 0.12)

        case .warning, .idle, .lookingAtCursor, .askConfirm:
            Capsule().fill(color)
                .frame(width: width * 0.7, height: 8)

        case .listening, .curious:
            Circle()
                .stroke(color, lineWidth: 6)
                .frame(width: width * 0.3, height: width * 0.3)

        case .thinking, .loadingModel, .unloadingModel, .lookingAtScreenshot:
            EllipsisMouth(color: color)

        case .speaking:
            // Animated sound-wave / equalizer bars while talking.
            SoundWaveMouth(color: color, width: width)
        }
    }
}

/// Animated sound-wave (equalizer) mouth shown while speaking. A row of bars
/// pulses out of phase to read as sound waves. Respects Reduce Motion (then it
/// shows a static waveform). Stops when the view leaves the speaking state.
struct SoundWaveMouth: View {
    let color: Color
    var width: CGFloat = 76

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.robotAudioLevel) private var audioLevel
    @State private var animating = false

    /// Relative bar heights — taller in the middle, like a voice envelope.
    private let pattern: [CGFloat] = [0.4, 0.7, 1.0, 0.55, 1.0, 0.7, 0.4]

    var body: some View {
        HStack(spacing: width * 0.045) {
            ForEach(pattern.indices, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: width * 0.055, height: barHeight(i))
                    .animation(barAnimation(i), value: scaleDriver)
            }
        }
        .frame(width: width * 0.74, height: width * 0.5)
        .onAppear { animating = true }
    }

    // When real audio is present we run as a tuner (bars track loudness);
    // otherwise we fall back to the looping decorative wave.
    private var isTuner: Bool { audioLevel != nil }

    /// A single value the bars animate against (loudness, or the loop toggle).
    private var scaleDriver: Float { isTuner ? (audioLevel ?? 0) : (animating ? 1 : 0) }

    private func barHeight(_ i: Int) -> CGFloat {
        let maxH = width * 0.44 * pattern[i]
        if isTuner {
            // Bars rise/fall with the voice; a small floor keeps them visible.
            let level = CGFloat(max(0, min(1, audioLevel ?? 0)))
            return maxH * (0.18 + 0.82 * level)
        } else {
            return maxH * (animating ? 1.0 : 0.3)
        }
    }

    private func barAnimation(_ i: Int) -> Animation? {
        if isTuner {
            return .easeOut(duration: 0.06)          // snappy, follows the audio
        }
        return reduceMotion ? nil :
            .easeInOut(duration: 0.42)
            .repeatForever(autoreverses: true)
            .delay(Double(i) * 0.07)
    }
}

/// Animated "…" used for thinking / loading states.
struct EllipsisMouth: View {
    let color: Color
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 11, height: 11)
                    .opacity(phase == i ? 1.0 : 0.3)
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.25)) { phase = (phase + 1) % 3 }
        }
    }
}
