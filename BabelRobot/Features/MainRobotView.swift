//
//  MainRobotView.swift
//  BabelRobot
//
//  The single window: robot face, controls, prompt + streamed response,
//  generation settings, and (DEBUG only) a small diagnostics panel.
//

import SwiftUI
import AVFoundation

struct MainRobotView: View {
    @Bindable var viewModel: RobotAssistantViewModel
    @Bindable var theme: ThemeManager
    @Bindable var companion: DesktopCompanionManager
    @Bindable var voice: VoiceConversationManager
    @Bindable var screenshot: ScreenshotUnderstandingViewModel
    @FocusState private var promptFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Resolve the design-language palette for whichever scheme is currently
    /// effective (the system one, or one forced by the theme preference).
    private var palette: BabelRobotPalette { theme.palette(for: colorScheme) }

    /// The window's tabs.
    private enum Tab: Hashable { case assistant, voice, companion }
    @State private var selectedTab: Tab = .assistant

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView(selection: $selectedTab) {
                assistantTab
                    .tabItem { Label("Assistant", systemImage: "text.bubble") }
                    .tag(Tab.assistant)
                voiceTab
                    .tabItem { Label("Voice", systemImage: "waveform") }
                    .tag(Tab.voice)
                companionTab
                    .tabItem { Label("Companion", systemImage: "macwindow.on.rectangle") }
                    .tag(Tab.companion)
            }
        }
        .background(palette.background.ignoresSafeArea())
        .foregroundStyle(palette.primaryText)
        .tint(palette.accent)
        .environment(\.palette, palette)
        .frame(minWidth: 600, minHeight: 720)
        .onAppear {
            viewModel.animator.reduceMotion = reduceMotion
            viewModel.syncAnimator()
            viewModel.metricsMonitor.start()
        }
        .onChange(of: reduceMotion) { _, newValue in
            viewModel.animator.reduceMotion = newValue
        }
        .onChange(of: promptFocused) { _, focused in
            viewModel.setPromptFocused(focused)
            viewModel.syncAnimator()
        }
        .onChange(of: viewModel.promptText) { _, _ in
            viewModel.syncAnimator()
        }
    }

    // MARK: Header (always visible above the tabs)

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text(viewModel.statusCaption)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                Spacer()
                Picker("Theme", selection: $theme.preference) {
                    ForEach(ThemeManager.Preference.allCases) { pref in
                        Label(pref.label, systemImage: pref.symbol).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Appearance theme")
            }
            if viewModel.faceState == .loadingModel {
                VStack(spacing: 4) {
                    ProgressView(value: viewModel.loadProgress)
                        .progressViewStyle(.linear)
                    Text("Downloading model… \(Int((viewModel.loadProgress * 100).rounded()))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            // Compact device metrics, right under the status / theme row.
            SystemMetricsView(metrics: viewModel.metricsMonitor.metrics)
            // Local model controls, just below Device.
            modelControls
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: Tabs

    /// Standard scrollable container for a tab's sections.
    private func tabScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 20) { content() }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }
    }

    private var assistantTab: some View {
        tabScroll {
            offlineBadge
            clipboardControls
            promptSection
            responseSection
            settingsSection
        }
    }

    private var voiceTab: some View { tabScroll { voiceSection } }

    private var companionTab: some View { tabScroll { companionSection } }

    // MARK: Screenshot & clipboard (below Local Model)

    private var clipboardControls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $screenshot.watchClipboard) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Watch clipboard")
                        Text("Copies & screenshots are offered for analysis; the text lands in the prompt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if screenshot.pending != nil { clipboardPrompt }

                HStack {
                    Button { screenshot.pasteScreenshot() } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    Button { screenshot.chooseImage() } label: {
                        Label("Choose Image", systemImage: "folder")
                    }
                    Button { screenshot.clear() } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .disabled(screenshot.image == nil && !screenshot.hasText)
                    Spacer()
                    if screenshot.isBusy { ProgressView().controlSize(.small) }
                }

                if let error = screenshot.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Tip: a normal screenshot saves to a file. Use ⌃⇧⌘4 (or set the screenshot tool to “Clipboard”) so it’s offered.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } label: {
            Label("Screenshot & clipboard", systemImage: "text.viewfinder")
        }
    }

    /// In-window "Analyze it?" banner (mirrors the robot's bubble; works even
    /// when the companion is hidden).
    private var clipboardPrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundStyle(palette.accent)
            Text(screenshot.pending?.prompt ?? "")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Analyze") { screenshot.acceptPending() }
                .buttonStyle(.borderedProminent)
            Button("No") { screenshot.dismissPending() }
        }
        .padding(10)
        .background(palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.accent.opacity(0.4)))
    }

    private var offlineBadge: some View {
        Label("Offline mode: prompts stay on this Mac.", systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(.quaternary, in: Capsule())
    }

    // MARK: Model controls

    private var modelControls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Model", selection: Binding(
                    get: { viewModel.selectedModel },
                    set: { viewModel.modelSelectionChanged(to: $0) }
                )) {
                    ForEach(LocalModelRegistry.Tier.allCases, id: \.self) { tier in
                        Section(tier.rawValue) {
                            ForEach(LocalModelRegistry.models(in: tier)) { model in
                                Text("\(model.displayName)  —  \(model.sizeLabel)").tag(model)
                            }
                        }
                    }
                }
                .disabled(viewModel.isBusy)

                modelDetails

                HStack {
                    Button {
                        promptFocused = false
                        viewModel.loadSelectedModel()
                    } label: {
                        Label("Load Model", systemImage: "arrow.down.circle")
                    }
                    .disabled(viewModel.isBusy)

                    Button(role: .destructive) {
                        viewModel.unloadModel()
                    } label: {
                        Label("Unload", systemImage: "trash")
                    }
                    .disabled(!viewModel.isModelLoaded || viewModel.isBusy)

                    Spacer()

                    if viewModel.isModelLoaded {
                        Label("Loaded", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    }
                }
            }
        } label: {
            Label("Local model", systemImage: "cpu")
        }
    }

    /// Size / quantization / estimated RAM for the selected model, plus a
    /// warning when the estimate is high for this Mac.
    private var modelDetails: some View {
        let model = viewModel.selectedModel
        let highMemory = model.exceedsComfortableMemory(
            physicalRAMBytes: LocalMemoryMonitor.physicalRAMBytes)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Label(model.sizeLabel, systemImage: "square.stack.3d.up.fill")
                Label("RAM \(model.estimatedRAMText)", systemImage: "memorychip")
                Label("Download \(model.downloadSizeText)", systemImage: "arrow.down.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(model.note)
                .font(.caption)
                .foregroundStyle(.secondary)

            if highMemory {
                Label(
                    "Estimated memory (\(model.estimatedRAMText)) is high for this Mac "
                    + "(\(LocalMemoryMonitor.physicalRAMGB.formatted(.number.precision(.fractionLength(0)))) GB RAM). "
                    + "Loading may be slow or fail.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Prompt

    private var promptSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $viewModel.promptText)
                    .frame(minHeight: 90)
                    .focused($promptFocused)
                    .font(.body)
                    .overlay(alignment: .topLeading) {
                        if viewModel.promptText.isEmpty {
                            Text("Ask the robot something…")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }

                HStack {
                    Button {
                        promptFocused = false
                        viewModel.run()
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!viewModel.isModelLoaded || viewModel.isBusy
                              || viewModel.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if viewModel.isGenerating {
                        Button {
                            viewModel.stop()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    }

                    Button {
                        viewModel.clear()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .disabled(viewModel.isBusy)

                    Spacer()
                }
            }
        } label: {
            Label("Prompt", systemImage: "text.bubble")
        }
    }

    // MARK: Response

    private var responseSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                if viewModel.responseText.isEmpty && viewModel.errorMessage == nil {
                    Text("The response will appear here.")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(viewModel.responseText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minHeight: 120, alignment: .topLeading)
        } label: {
            Label("Response", systemImage: "quote.bubble")
        }
    }

    // MARK: Voice conversation

    private var voiceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $voice.enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Voice Conversation")
                        Text("Talk to the robot; it transcribes, runs the local model, and speaks the reply.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if voice.enabled {
                    Divider()
                    voiceStatusRow
                    if !voice.transcript.isEmpty {
                        Text("“\(voice.transcript)”")
                            .font(.callout)
                            .italic()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    voiceControls
                    Divider()
                    voiceSettings
                    voicePrivacyNote
                }
            }
        } label: {
            Label("Voice conversation", systemImage: "waveform")
        }
    }

    private var voiceStatusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: voiceStatusSymbol)
                .foregroundStyle(voiceStatusColor)
            Text(voice.state.message)
                .font(.callout)
                .foregroundStyle(voice.isError ? .orange : .secondary)
            Spacer()
        }
    }

    private var voiceControls: some View {
        HStack {
            Button {
                promptFocused = false
                voice.toggleTalk()
            } label: {
                Label("Talk", systemImage: "mic.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isModelLoaded && voice.isModelLoaded?() != true)

            Button {
                voice.stopListening()
            } label: {
                Label("Stop Listening", systemImage: "mic.slash")
            }
            .disabled(!voice.isListeningState)

            Button {
                voice.stopSpeaking()
            } label: {
                Label("Stop Speaking", systemImage: "speaker.slash.fill")
            }
            .disabled(!voice.tts.isSpeaking)

            Button {
                voice.toggleMute()
            } label: {
                Label(voice.muted ? "Unmute Voice" : "Mute Voice",
                      systemImage: voice.muted ? "speaker.slash" : "speaker.wave.2.fill")
            }

            Spacer()
        }
    }

    private var voiceSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Push to Talk", isOn: $voice.pushToTalk)
            Toggle("Auto Speak Responses", isOn: $voice.autoSpeak)
            HStack {
                Text("Voice Output Volume")
                Slider(value: $voice.volume, in: 0...1, step: 0.05)
                Text(voice.volume, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(width: 46, alignment: .trailing)
            }
            HStack {
                Text("Speech Speed")
                Slider(value: $voice.speechRate, in: 0.3...0.7, step: 0.02)
                Text(speedLabel)
                    .monospacedDigit()
                    .frame(width: 46, alignment: .trailing)
            }
            Picker("Speech Language", selection: $voice.speechLanguage) {
                ForEach(Self.speechLanguages, id: \.0) { code, name in
                    Text(name).tag(code)
                }
            }
            Picker("Voice", selection: $voice.voiceIdentifier) {
                Text("System default").tag(String?.none)
                ForEach(voicesForLanguage, id: \.identifier) { v in
                    Text(voiceLabel(v)).tag(Optional(v.identifier))
                }
            }
            if TextToSpeechService.hasNaturalVoice(forLanguage: voice.speechLanguage) {
                Text("Tip: pick an Enhanced or Premium voice above for the most natural sound.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Only robotic Compact voices are installed for this language. Open System Settings ▸ Accessibility ▸ Spoken Content ▸ System Voice ▸ Manage Voices… and download an Enhanced or Premium voice for smoother speech.",
                      systemImage: "exclamationmark.bubble")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Speed shown relative to the system default (0.5 = 1.0×).
    private var speedLabel: String {
        String(format: "%.2g×", voice.speechRate / 0.5)
    }

    /// Installed voices for the selected language, softer (Premium/Enhanced)
    /// first; falls back to all voices if none match.
    private var voicesForLanguage: [AVSpeechSynthesisVoice] {
        let prefix = String(voice.speechLanguage.prefix(2)).lowercased()
        let all = AVSpeechSynthesisVoice.speechVoices()
        let matching = all.filter { $0.language.lowercased().hasPrefix(prefix) }
        let pool = matching.isEmpty ? all : matching
        return pool.sorted { lhs, rhs in
            if lhs.quality.rawValue != rhs.quality.rawValue {
                return lhs.quality.rawValue > rhs.quality.rawValue   // premium/enhanced first
            }
            return lhs.name < rhs.name
        }
    }

    private func voiceLabel(_ v: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch v.quality {
        case .premium:  quality = "Premium"
        case .enhanced: quality = "Enhanced"
        default:        quality = "Compact"
        }
        return "\(v.name) · \(quality) · \(v.language)"
    }

    private var voicePrivacyNote: some View {
        Label(
            voice.usesOnDeviceRecognition
            ? "Speech is recognized on-device. Local LLM responses stay on this Mac."
            : "Speech recognition uses Apple's speech system. Local LLM responses stay on this Mac.",
            systemImage: "lock.shield")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var voiceStatusSymbol: String {
        switch voice.state {
        case .listening:    return "mic.fill"
        case .transcribing: return "text.viewfinder"
        case .thinking:     return "brain"
        case .speaking:     return "speaker.wave.2.fill"
        case .error:        return "exclamationmark.triangle.fill"
        case .requestingMicrophonePermission: return "hand.raised.fill"
        case .idle:         return "waveform"
        }
    }

    private var voiceStatusColor: Color {
        switch voice.state {
        case .error:     return .orange
        case .listening: return .green
        default:         return .secondary
        }
    }

    /// A short list of common languages for the POC picker.
    private static let speechLanguages: [(String, String)] = [
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("es-ES", "Spanish (Spain)"),
        ("es-MX", "Spanish (Mexico)"),
        ("pt-BR", "Portuguese (Brazil)"),
        ("fr-FR", "French"),
        ("de-DE", "German"),
        ("it-IT", "Italian"),
        ("ja-JP", "Japanese"),
        ("zh-CN", "Chinese (Simplified)")
    ]

    // MARK: Desktop companion

    private var companionSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $companion.enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Desktop Companion")
                        Text("A floating robot that lives on your desktop and reacts to the assistant.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if companion.enabled {
                    Divider()
                    Picker("Companion mode", selection: $companion.mode) {
                        ForEach(DesktopCompanionManager.Mode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Follow cursor", isOn: $companion.followCursor)
                    Toggle("Sleep when idle", isOn: $companion.sleepWhenIdle)
                    Toggle("Always on top", isOn: $companion.alwaysOnTop)

                    Toggle(isOn: $companion.livelyPersonality) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lively personality")
                            Text("Richer emotions and animations — the robot reacts with curiosity, focus, excitement, and more.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if companion.livelyPersonality {
                        personalityModelControls
                            .padding(.leading, 8)
                    }
                }
            }
        } label: {
            Label("Desktop companion", systemImage: "macwindow.on.rectangle")
        }
    }

    /// Picker + load controls for the tiny Personality Model that classifies
    /// emotions. Runs as its own MLX model, alongside the main chat LLM.
    private var personalityModelControls: some View {
        let model = companion.personalityModelSelection
        let pm = companion.personalityModel
        return VStack(alignment: .leading, spacing: 8) {
            Picker("Personality model", selection: Binding(
                get: { companion.personalityModelSelection },
                set: { companion.personalityModelSelection = $0 }
            )) {
                ForEach(PersonalityModelRegistry.all) { m in
                    Text("\(m.displayName)  —  \(m.sizeLabel)").tag(m)
                }
            }
            .disabled(pm.isBusy)

            HStack(spacing: 12) {
                Label("RAM \(model.estimatedRAMText)", systemImage: "memorychip")
                Label(model.downloadSizeText, systemImage: "arrow.down.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                switch pm.state {
                case .loading:
                    ProgressView(value: pm.loadProgress)
                        .frame(width: 90)
                    Text("Loading… \(Int(pm.loadProgress * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                case .loaded, .generating:
                    Label("Loaded — emotions via the model", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green).font(.caption)
                    Button("Unload") { companion.unloadPersonalityModel() }
                        .buttonStyle(.link).font(.caption)
                case .failed:
                    Label("Load failed — using rules", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.caption)
                    Button("Retry") { companion.loadPersonalityModel() }
                        .buttonStyle(.link).font(.caption)
                default:
                    Text("Not loaded — using deterministic rules until it loads.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Load") { companion.loadPersonalityModel() }
                        .buttonStyle(.link).font(.caption)
                }
            }

            if let raw = pm.lastRawOutput {
                Text("Model said (#\(pm.classificationCount)): \(raw)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Text("A tiny model that classifies the robot's emotion only — it never answers for you. Falls back to rules instantly if it's slow.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Settings

    private var settingsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Temperature")
                    Slider(value: $viewModel.settings.temperature, in: 0...1, step: 0.05)
                    Text(viewModel.settings.temperature, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                HStack {
                    Text("Max tokens")
                    Spacer()
                    TextField("Max tokens", value: $viewModel.settings.maxTokens, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Top-p")
                    Slider(value: $viewModel.settings.topP, in: 0...1, step: 0.05)
                    Text(viewModel.settings.topP, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }
        } label: {
            Label("Generation settings", systemImage: "slider.horizontal.3")
        }
    }

}

#Preview {
    MainRobotView(
        viewModel: RobotAssistantViewModel(),
        theme: ThemeManager(),
        companion: DesktopCompanionManager(),
        voice: VoiceConversationManager(),
        screenshot: ScreenshotUnderstandingViewModel())
}
