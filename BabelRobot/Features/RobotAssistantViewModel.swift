//
//  RobotAssistantViewModel.swift
//  BabelRobot
//
//  Bridges the LLM lifecycle (LocalLLMManager) and the robot face. Owns the
//  UI-facing state: selected model, prompt, streamed response, settings, and
//  the derived RobotFaceState that the face renders.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class RobotAssistantViewModel {

    let manager = LocalLLMManager()
    let animator = RobotFaceAnimator()
    let metricsMonitor = SystemMetricsMonitor()

    // User-facing inputs
    var selectedModel: LocalModelConfig = LocalModelRegistry.default
    var promptText: String = ""
    var settings = GenerationSettings()

    // Outputs
    private(set) var responseText: String = ""
    private(set) var errorMessage: String?

    // Transient face cues
    private(set) var isSpeaking = false
    private var promptFocused = false
    private var showHappyUntil: Date?

    private var runTask: Task<Void, Never>?
    private var didAutoLoad = false

    let models = LocalModelRegistry.all

    /// Optional retrieval hook: given the user prompt, returns a web-search
    /// context block to prepend to the model prompt (or nil). Set by the app
    /// when Web search is enabled. The model stays local; this only adds context.
    var retrieveContext: ((String) async -> String?)?

    /// Load the default model once, automatically, on first launch of the UI.
    /// (Cached after the first download; later launches load from disk.)
    func autoLoadDefaultIfNeeded() {
        guard !didAutoLoad else { return }
        didAutoLoad = true
        loadSelectedModel()
    }

    // MARK: - Derived robot face

    var faceState: RobotFaceState {
        switch manager.state {
        case .loading:
            return .loadingModel
        case .unloading:
            return .unloadingModel
        case .failed:
            return .error
        case .generating:
            return isSpeaking ? .speaking : .thinking
        case .loaded:
            if isShowingHappy { return .happy }
            return promptFocused && !promptText.isEmpty ? .listening : .idle
        case .unloaded:
            return isShowingHappy ? .happy : .idle
        }
    }

    private var isShowingHappy: Bool {
        if let until = showHappyUntil, until > Date() { return true }
        return false
    }

    var isModelLoaded: Bool { manager.state.hasResidentModel }
    var isBusy: Bool { manager.state.isBusy }
    var isGenerating: Bool { if case .generating = manager.state { return true } else { return false } }
    var isLoading: Bool { if case .loading = manager.state { return true } else { return false } }
    var loadProgress: Double { manager.loadProgress }
    /// True once weights are downloaded and being mapped into memory (the phase
    /// after the download bar, shown as an indeterminate spinner).
    var isMappingIntoMemory: Bool { manager.isMappingIntoMemory }
    var statusCaption: String { faceState.caption }

    // MARK: - Lifecycle hooks for the face animator

    /// Call when the face state may have changed so the animator can re-sync.
    func syncAnimator() {
        animator.update(for: faceState)
    }

    func setPromptFocused(_ focused: Bool) {
        promptFocused = focused
    }

    // MARK: - Actions

    func loadSelectedModel() {
        errorMessage = nil
        Task {
            await manager.load(selectedModel)
            if manager.state.hasResidentModel {
                flashHappy()
            } else if case .failed(let message) = manager.state {
                errorMessage = message
            }
            syncAnimator()
        }
    }

    /// Cancel an in-progress model download/load and unlock the UI.
    func cancelLoad() {
        manager.cancelLoad()
        errorMessage = nil
        syncAnimator()
    }

    func unloadModel() {
        errorMessage = nil
        Task {
            await manager.unload()
            syncAnimator()
        }
    }

    /// Switch to a newly picked model (unload current, load new).
    func modelSelectionChanged(to model: LocalModelConfig) {
        selectedModel = model
        guard manager.state.hasResidentModel else { return }
        // Different model picked while one is resident: reload.
        loadSelectedModel()
    }

    func run() {
        let prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard isModelLoaded, !isBusy else {
            if !isModelLoaded { errorMessage = "Please load a model first." }
            return
        }

        runTask = Task { await performGeneration(prompt: prompt) }
    }

    /// Run the loaded model on `prompt`, streaming into `responseText` and
    /// driving the face. Returns the full response, or nil on failure (after
    /// setting `errorMessage`). Shared by the text Run button and voice mode.
    @discardableResult
    private func performGeneration(
        prompt: String,
        onText: (@MainActor (String) -> Void)? = nil
    ) async -> String? {
        errorMessage = nil
        responseText = ""
        isSpeaking = false
        syncAnimator() // thinking

        // Optionally search the web first and prepend the results as context, so
        // the local model can answer about current events. No-op when disabled.
        var modelPrompt = prompt
        if let retrieveContext, let context = await retrieveContext(prompt) {
            modelPrompt = context + "\n\nUser question: " + prompt
        }

        do {
            _ = try await manager.generate(prompt: modelPrompt, settings: settings) { [weak self] chunk in
                guard let self else { return }
                if !self.isSpeaking {
                    self.isSpeaking = true
                    self.syncAnimator() // switch to speaking
                }
                self.responseText += chunk
                onText?(chunk)   // stream deltas to voice mode for incremental TTS
            }
            isSpeaking = false
            flashHappy()
            syncAnimator()
            return responseText
        } catch {
            isSpeaking = false
            errorMessage = (error as? LocalLLMError)?.errorDescription
                ?? "Local generation failed. Please try again."
            syncAnimator()
            return nil
        }
    }

    /// Entry point for Voice Conversation mode: sets the prompt (so it shows in
    /// the UI) and awaits the full response. Returns nil if no model is loaded
    /// or generation fails.
    func generateForVoice(prompt: String) async -> String? {
        guard isModelLoaded else {
            errorMessage = "Please load a model first."
            return nil
        }
        guard !isBusy else { return nil }
        promptText = prompt
        return await performGeneration(prompt: prompt)
    }

    /// Streaming variant for voice mode: forwards each token delta to `onChunk`
    /// so the response can be spoken sentence-by-sentence while it's generated.
    func generateForVoiceStreaming(
        prompt: String,
        onChunk: @escaping @MainActor (String) -> Void
    ) async -> String? {
        guard isModelLoaded else {
            errorMessage = "Please load a model first."
            return nil
        }
        guard !isBusy else { return nil }
        promptText = prompt
        return await performGeneration(prompt: prompt, onText: onChunk)
    }

    /// Generate for an auxiliary feature (e.g. Screenshot Understanding) into the
    /// SHARED response box and shared face — so there is one answer area for
    /// everything. Streams each chunk to `onText` (for incremental TTS). Returns
    /// the full text, or nil if no model is loaded / busy / failed.
    func generateShared(
        prompt: String,
        onText: @escaping @MainActor (String) -> Void
    ) async -> String? {
        guard isModelLoaded else {
            errorMessage = "Please load a local model first."
            return nil
        }
        guard !isBusy else { return nil }
        return await performGeneration(prompt: prompt, onText: onText)
    }

    /// Clear only the shared response (not the prompt).
    func clearResponse() {
        responseText = ""
        errorMessage = nil
        syncAnimator()
    }

    func stop() {
        manager.cancelGeneration()
        runTask?.cancel()
        isSpeaking = false
    }

    func clear() {
        promptText = ""
        responseText = ""
        errorMessage = nil
        syncAnimator()
    }

    func shutdown() {
        runTask?.cancel()
        manager.shutdown()
        animator.stop()
        metricsMonitor.stop()
    }

    private func flashHappy() {
        showHappyUntil = Date().addingTimeInterval(1.6)
        syncAnimator()
        Task {
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            syncAnimator()
        }
    }
}
