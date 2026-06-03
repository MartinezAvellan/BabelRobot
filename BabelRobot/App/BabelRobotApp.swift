//
//  BabelRobotApp.swift
//  BabelRobot
//
//  Offline local AI assistant with an animated robot face (macOS).
//  Inference runs entirely on-device via MLX; no cloud, no API key.
//

import SwiftUI

@main
struct BabelRobotApp: App {
    @State private var viewModel = RobotAssistantViewModel()
    @State private var theme = ThemeManager()
    @State private var companion = DesktopCompanionManager()
    @State private var voice = VoiceConversationManager()

    var body: some Scene {
        WindowGroup {
            MainRobotView(viewModel: viewModel, theme: theme,
                          companion: companion, voice: voice)
                .preferredColorScheme(theme.preferredColorScheme)
                .onAppear { wireUp() }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification)) { _ in
                    viewModel.shutdown()
                    companion.shutdown()
                    voice.shutdown()
                }
        }
        .windowResizability(.contentSize)
    }

    /// Connect the independent managers together (closures, no hard refs).
    private func wireUp() {
        // Mirror the assistant's lifecycle onto the desktop companion.
        companion.connectAI { viewModel.faceState }

        // Clicking the robot starts a voice turn (when voice is enabled).
        companion.onActivate = { [voice] in voice.toggleTalk() }

        // Voice mode talks to the local LLM and drives the companion face.
        voice.generate = { [viewModel] prompt in await viewModel.generateForVoice(prompt: prompt) }
        voice.generateStreaming = { [viewModel] prompt, onChunk in
            await viewModel.generateForVoiceStreaming(prompt: prompt, onChunk: onChunk)
        }
        voice.isModelLoaded = { [viewModel] in viewModel.isModelLoaded }
        voice.cancelGeneration = { [viewModel] in viewModel.stop() }
        voice.applyFaceOverride = { [companion] state in companion.voiceState = state }
        voice.keepAwake = { [companion] in companion.wake() }
        // Feed real-time TTS loudness to the companion's tuner mouth.
        voice.tts.onLevel = { [companion] level in companion.audioLevel = level }

        // Auto-download / load the default model (Llama 3.1 8B) on launch.
        viewModel.autoLoadDefaultIfNeeded()
    }
}
