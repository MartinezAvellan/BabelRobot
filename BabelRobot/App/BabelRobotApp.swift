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
    @State private var screenshot = ScreenshotUnderstandingViewModel()
    @State private var awareness = RobotAwarenessService()
    @State private var search = WebSearchService()

    var body: some Scene {
        WindowGroup {
            MainRobotView(viewModel: viewModel, theme: theme,
                          companion: companion, voice: voice,
                          screenshot: screenshot, awareness: awareness,
                          search: search)
                .preferredColorScheme(theme.preferredColorScheme)
                .onAppear { wireUp() }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification)) { _ in
                    viewModel.shutdown()
                    companion.shutdown()
                    voice.shutdown()
                    screenshot.shutdown()
                }
        }
        .windowResizability(.contentSize)
    }

    /// Connect the independent managers together (closures, no hard refs).
    private func wireUp() {
        // Mirror the assistant's lifecycle onto the desktop companion. The
        // context closure lets the Personality Model read the conversation's tone
        // at end-of-turn (classification only — never used to answer).
        companion.connectAI(
            stateProvider: { viewModel.faceState },
            contextProvider: { (viewModel.promptText, viewModel.responseText) }
        )

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

        // Screenshot Understanding: OCR locally, run the loaded model on the
        // extracted text, drive the companion face, and optionally speak.
        screenshot.isModelLoaded = { [viewModel] in viewModel.isModelLoaded }
        screenshot.onFaceState = { [companion] state in companion.screenshotState = state }
        // Screenshot answers render in the SHARED response box, via the same
        // generation path as the prompt.
        screenshot.generate = { [viewModel] prompt, onText in
            await viewModel.generateShared(prompt: prompt, onText: onText)
        }
        screenshot.clearShared = { [viewModel] in viewModel.clearResponse() }
        // Ready OCR / copied text lands in the shared prompt box for review.
        screenshot.onTextReady = { [viewModel] text in viewModel.promptText = text }
        // Speak screenshot answers through the SAME streaming TTS as Talk.
        screenshot.speechBegin = { [voice] in voice.beginStreamingSpeech() }
        screenshot.speechFeed = { [voice] chunk in voice.feedStreamingSpeech(chunk) }
        screenshot.speechEnd = { [voice] in voice.endStreamingSpeech() }
        // Translate targets the Voice Conversation speech language.
        screenshot.targetLanguageProvider = { [voice] in Self.languageName(voice.speechLanguage) }
        // Surface the "Analyze it?" prompt + quick actions on the companion.
        screenshot.onPending = { [companion] prompt in companion.confirmPrompt = prompt }
        screenshot.onActions = { [companion] actions in companion.screenshotActions = actions }
        companion.onConfirmAccept = { [screenshot] in screenshot.acceptPending() }
        companion.onConfirmDecline = { [screenshot] in screenshot.dismissPending() }
        companion.onScreenshotAction = { [screenshot] action in screenshot.perform(action) }
        companion.onScreenshotDismiss = { [screenshot] in screenshot.dismissActions() }
        // Let the robot show Talk / Stop Listening / Stop / Mute.
        companion.voice = voice
        screenshot.lastGenStats = { [viewModel] in
            (viewModel.manager.lastGenerationTime,
             viewModel.manager.lastTokensPerSecond,
             viewModel.selectedModel.displayName)
        }

        // Give the local assistant a sense of time / place / weather (opt-in).
        // The Awareness layer is the only network access for the robot's own
        // knowledge; LLM inference stays fully local.
        viewModel.manager.contextProvider = { [awareness] in awareness.systemContextLine }

        // Web search (opt-in): searches the web and feeds results to the LOCAL
        // model as context. Searches are logged in the shared awareness log.
        search.log = awareness.log
        viewModel.retrieveContext = { [search] prompt in await search.contextBlock(for: prompt) }

        // Auto-download / load the default model (Llama 3.1 8B) on launch.
        viewModel.autoLoadDefaultIfNeeded()
    }

    /// Map a BCP-47 speech code (e.g. "pt-BR") to an English language name
    /// ("Portuguese") for the Translate action.
    private static func languageName(_ bcp47: String) -> String {
        let code = String(bcp47.prefix(2))
        return Locale(identifier: "en_US")
            .localizedString(forLanguageCode: code)?.capitalized ?? "English"
    }
}
