//
//  RobotFaceView.swift
//  BabelRobot
//
//  Composes the robot head, eyes, and mouth into a single expressive face.
//  Pure SwiftUI; no video, no external animation libraries.
//

import SwiftUI

struct RobotFaceView: View {
    let state: RobotFaceState
    var animator: RobotFaceAnimator
    /// Mac thermal state — drives the "hot CPU → orange eyes" mood.
    var thermalState: ProcessInfo.ThermalState = .nominal

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mouthSpeaking = false

    /// Eye / mouth color, tinted by mood and thermal state.
    private var faceColor: Color {
        RobotFaceMood.color(for: state, base: palette.robotFace, thermal: thermalState)
    }

    var body: some View {
        RobotHeadView(accent: palette.accent) {
            VStack(spacing: 22) {
                RobotEyesView(state: state, animator: animator, color: faceColor)
                RobotMouthView(state: state, color: faceColor, speaking: mouthSpeaking)
            }
            .padding(.horizontal, 12)
            .overlay { blushCheeks }
        }
        .animation(.easeInOut(duration: 0.4), value: faceColor)
        .scaleEffect(animator.breathScale)
        .opacity(animator.faceOpacity)
        .animation(.easeInOut(duration: 0.3), value: state)
        .onAppear { syncSpeaking() }
        .onChange(of: state) { _, _ in syncSpeaking() }
        .accessibilityElement()
        .accessibilityLabel("Robot face")
        .accessibilityValue(state.caption)
    }

    /// Soft pink cheeks for the blush (love / shy) moods.
    @ViewBuilder
    private var blushCheeks: some View {
        if RobotFaceMood.showsBlush(for: state) {
            HStack(spacing: 96) {
                cheek
                cheek
            }
            .offset(y: 26)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    private var cheek: some View {
        Ellipse()
            .fill(RobotFaceMood.blush.opacity(0.55))
            .frame(width: 34, height: 22)
            .blur(radius: 6)
    }

    private func syncSpeaking() {
        let shouldSpeak = (state == .speaking) && !reduceMotion
        guard shouldSpeak != mouthSpeaking else { return }
        if shouldSpeak {
            withAnimation(.easeInOut(duration: 0.22).repeatForever(autoreverses: true)) {
                mouthSpeaking = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { mouthSpeaking = false }
        }
    }
}

#Preview("States – Dark") {
    FacePreviewGrid()
        .environment(\.palette, .dark)
        .background(BabelRobotPalette.dark.background)
}

#Preview("States – Light") {
    FacePreviewGrid()
        .environment(\.palette, .light)
        .background(BabelRobotPalette.light.background)
}

private struct FacePreviewGrid: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                ForEach(RobotFaceState.allCases, id: \.self) { state in
                    VStack {
                        RobotFaceView(state: state, animator: RobotFaceAnimator())
                            .scaleEffect(0.6)
                            .frame(height: 180)
                        Text(String(describing: state))
                            .font(.caption)
                    }
                }
            }
            .padding()
        }
    }
}
