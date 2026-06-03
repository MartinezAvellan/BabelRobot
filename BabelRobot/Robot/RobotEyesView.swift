//
//  RobotEyesView.swift
//  BabelRobot
//
//  The robot's eyes, drawn as glowing neon elements that reshape per state.
//

import SwiftUI

struct RobotEyesView: View {
    let state: RobotFaceState
    var animator: RobotFaceAnimator
    let color: Color
    /// Base eye diameter.
    var size: CGFloat = 44

    var body: some View {
        HStack(spacing: size * 0.85) {
            eye(side: .left)
            eye(side: .right)
        }
        .foregroundStyle(color)
        // Gentle glow (toned down — the neon eyes were too bright).
        .shadow(color: color.opacity(0.30), radius: 5)
    }

    private enum Side { case left, right }

    @ViewBuilder
    private func eye(side: Side) -> some View {
        switch state {
        case .happy:
            Curve(curvature: 0.9)
                .stroke(color, style: .init(lineWidth: size * 0.16, lineCap: .round))
                .frame(width: size, height: size * 0.6)

        case .love:
            HeartShape().fill(color)
                .frame(width: size * 0.9, height: size * 0.9)

        case .sleeping:
            Capsule().fill(color)
                .frame(width: size, height: size * 0.16)

        case .error:
            Image(systemName: "xmark")
                .font(.system(size: size * 0.9, weight: .bold))

        case .warning:
            Image(systemName: "exclamationmark")
                .font(.system(size: size * 1.05, weight: .heavy))

        case .confused:
            // Left: normal eye. Right: a question mark.
            if side == .left { openEye } else {
                Image(systemName: "questionmark")
                    .font(.system(size: size * 0.95, weight: .bold))
            }

        case .loadingModel:
            ArcRing()
                .stroke(color, style: .init(lineWidth: size * 0.16, lineCap: .round))
                .frame(width: size * 0.86, height: size * 0.86)
                .rotationEffect(.degrees(animator.spin))

        case .unloadingModel:
            // Pupils looking down-ish (◔).
            pupilEye(offset: CGSize(width: 0, height: 0.4))

        case .thinking:
            // Pupils follow the alternating gaze.
            pupilEye(offset: animator.gaze)

        default: // idle, listening, speaking
            openEye
        }
    }

    /// A solid eye that becomes a thin slit when blinking.
    private var openEye: some View {
        let attentive = (state == .listening)
        let h = animator.eyesClosed ? size * 0.16 : size
        return Capsule()
            .fill(color)
            .frame(width: attentive ? size : size * 0.92, height: h)
            .overlay {
                if !animator.eyesClosed {
                    Circle()
                        .fill(.black.opacity(0.18))
                        .frame(width: size * 0.30, height: size * 0.30)
                        .offset(x: animator.gaze.width * size * 0.2,
                                y: animator.gaze.height * size * 0.2)
                        .blendMode(.multiply)
                }
            }
            .clipShape(Capsule())
    }

    /// An eye with a movable pupil (no blink).
    private func pupilEye(offset: CGSize) -> some View {
        Capsule()
            .fill(color)
            .frame(width: size * 0.92, height: size)
            .overlay {
                Circle()
                    .fill(.black.opacity(0.18))
                    .frame(width: size * 0.32, height: size * 0.32)
                    .offset(x: offset.width * size * 0.22, y: offset.height * size * 0.22)
                    .blendMode(.multiply)
            }
            .clipShape(Capsule())
    }
}
