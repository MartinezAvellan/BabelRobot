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
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            face
            if let prompt = manager.confirmPrompt {
                confirmBubble(prompt)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            bottomBar
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: 240, height: 240)
        .contextMenu { menu }
        .onAppear { manager.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, value in manager.reduceMotion = value }
        .accessibilityElement()
        .accessibilityLabel("Babel Robot companion")
        .accessibilityValue(manager.confirmPrompt ?? manager.faceState.caption)
    }

    private var face: some View {
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
            // While confirming, a tap shouldn't start a voice turn — the ✓/✗
            // buttons handle the choice.
            .onTapGesture { if manager.confirmPrompt == nil { manager.activate() } }
    }

    /// Speech bubble shown above the robot with the "Analyze it?" prompt and
    /// the green ✓ (accept) / red ✗ (decline) buttons.
    private func confirmBubble(_ text: String) -> some View {
        VStack(spacing: 7) {
            Text(text)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.82), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
            controlPanel {
                roundButton("xmark", "No", tint: .red) { manager.confirmDecline() }
                roundButton("checkmark", "Analyze", tint: .green) { manager.confirmAccept() }
            }
        }
        .padding(.top, 2)
        .transition(.scale.combined(with: .opacity))
    }

    /// The bottom strip: screenshot actions when text is ready, otherwise the
    /// voice controls. Hidden while the confirm bubble is up.
    @ViewBuilder
    private var bottomBar: some View {
        if manager.confirmPrompt == nil {
            if !manager.screenshotActions.isEmpty {
                actionBar
            } else {
                voiceControls
            }
        }
    }

    /// Talk / Stop Listening / Stop / Mute on the robot (icons; label on hover).
    @ViewBuilder
    private var voiceControls: some View {
        if let voice = manager.voice, voice.enabled {
            controlPanel {
                roundButton("mic.fill", "Talk", tint: .green) { voice.toggleTalk() }
                roundButton("mic.slash.fill", "Stop Listening",
                            enabled: voice.isListeningState) { voice.stopListening() }
                roundButton("stop.fill", "Stop",
                            enabled: voice.tts.isSpeaking) { voice.stopSpeaking() }
                roundButton(voice.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            voice.muted ? "Unmute" : "Mute",
                            tint: voice.muted ? .orange : nil) { voice.toggleMute() }
            }
            .transition(.opacity)
        }
    }

    /// Quick-action buttons (icons; label on hover) shown on the robot once OCR
    /// text is ready: Explain · Summarize · Tasks · Translate. The ✗ dismisses
    /// them and returns the robot to the voice controls.
    private var actionBar: some View {
        controlPanel {
            ForEach(manager.screenshotActions) { action in
                roundButton(action.symbol, action.title) { manager.onScreenshotAction?(action) }
            }
            divider
            roundButton("xmark", "Dismiss", tint: .red) { manager.onScreenshotDismiss?() }
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Shared control styling

    /// Wraps a row of buttons in a rounded, softly-glowing panel (as if the
    /// glass were catching the light).
    private func controlPanel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.black.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .white.opacity(0.06)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            // Outer glow — light reflecting off the panel.
            .shadow(color: palette.accent.opacity(0.5), radius: 10)
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            .padding(.bottom, 8)
    }

    /// A thin separator between the action buttons and the dismiss ✗.
    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.18))
            .frame(width: 1, height: 20)
    }

    /// A small circular icon button with a hover label.
    private func roundButton(_ symbol: String, _ label: String,
                             enabled: Bool = true, tint: Color? = nil,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background((tint ?? .white).opacity(tint == nil ? 0.16 : 0.9), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .help(label)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
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
