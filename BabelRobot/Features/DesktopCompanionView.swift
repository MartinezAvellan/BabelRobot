//
//  DesktopCompanionView.swift
//  BabelRobot
//
//  The SwiftUI content hosted inside the floating companion panel. Reuses the
//  shared face system (head, neon eyes, animated mouth) on a transparent
//  background, adds a subtle cursor-driven head tilt, tap-to-wake, and a
//  right-click menu for quick settings.
//

import SwiftUI

struct DesktopCompanionView: View {
    @Bindable var manager: DesktopCompanionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RobotFaceView(state: manager.faceState, animator: manager.animator,
                      thermalState: ProcessInfo.processInfo.thermalState)
            .environment(\.robotAudioLevel,
                         manager.voiceState == .speaking ? manager.audioLevel : nil)
            .scaleEffect(0.6)
            .frame(width: 240, height: 240)
            .rotation3DEffect(
                .degrees(manager.headTilt),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                perspective: 0.5)
            .contentShape(Rectangle())
            .onTapGesture { manager.activate() }
            .contextMenu { menu }
            .onAppear { manager.reduceMotion = reduceMotion }
            .onChange(of: reduceMotion) { _, value in manager.reduceMotion = value }
            .accessibilityElement()
            .accessibilityLabel("Babel Robot companion")
            .accessibilityValue(manager.faceState.caption)
    }

    @ViewBuilder
    private var menu: some View {
        Picker("Mode", selection: $manager.mode) {
            ForEach(DesktopCompanionManager.Mode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        Toggle("Follow cursor", isOn: $manager.followCursor)
        Toggle("Sleep when idle", isOn: $manager.sleepWhenIdle)
        Toggle("Always on top", isOn: $manager.alwaysOnTop)
        Divider()
        Button("Hide companion") { manager.enabled = false }
    }
}
