//
//  PersonalityModelEngine.swift
//  BabelRobot
//
//  Loads and runs the tiny *Personality Model* that classifies the robot's
//  emotion. It is a SEPARATE, lightweight MLX container from the main chat LLM
//  (`LocalLLMManager`): the two coexist in memory, so the personality model adds
//  only its own small footprint (~0.15–0.45 GB) and never unloads or shares the
//  main model.
//
//  It conforms to `EmotionModelRunner`, so the `ModelEmotionClassifier` can call
//  `complete(...)` to get the raw JSON emotion. The model classifies emotion
//  ONLY — it is never used to answer the user.
//

import Foundation
import Observation
import MLX
import MLXLMCommon

@MainActor
@Observable
final class PersonalityModelEngine: EmotionModelRunner {

    // MARK: - Observable state

    /// Reuses the app's strict lifecycle vocabulary for a consistent UI.
    private(set) var state: LocalModelState = .unloaded
    /// 0...1 progress during loading.
    private(set) var loadProgress: Double = 0

    /// The currently-selected Personality Model.
    var selectedModel: LocalModelConfig = PersonalityModelRegistry.default

    var isLoaded: Bool { state.hasResidentModel }
    var isBusy: Bool { state.isBusy }

    // MARK: - Private

    private let loadTimeout: TimeInterval = 120
    private var container: ModelContainer?

    // MARK: - Loading

    /// Download (if needed) and load `model` into its own container. A previous
    /// personality model is released first. No-op while busy.
    func load(_ model: LocalModelConfig) async {
        guard !state.isBusy else { return }
        selectedModel = model

        if state.hasResidentModel { await unload() }

        state = .loading(modelId: model.id)
        loadProgress = 0
        do {
            let loaded = try await withTimeout(seconds: loadTimeout) {
                try await LocalModelProvider.loadContainer(huggingFaceId: model.huggingFaceId) { frac in
                    Task { @MainActor in self.loadProgress = frac }
                }
            }
            container = loaded
            loadProgress = 1
            state = .loaded(modelId: model.id)
        } catch {
            container = nil
            MLX.Memory.cacheLimit = 0
            state = .failed(message: "Could not load the personality model.")
        }
    }

    /// Convenience: load the currently-selected model.
    func loadSelected() async { await load(selectedModel) }

    func unload() async {
        let isFailed = { if case .failed = state { return true } else { return false } }()
        guard state.hasResidentModel || isFailed else { return }
        autoreleasepool { container = nil }
        MLX.Memory.cacheLimit = 0
        loadProgress = 0
        state = .unloaded
    }

    func shutdown() {
        autoreleasepool { container = nil }
        state = .unloaded
    }

    // MARK: - EmotionModelRunner

    /// Run the classifier prompt and return the raw completion (expected to be a
    /// small JSON object). Throws if no model is resident, so the classifier can
    /// fall back to the deterministic rules.
    func complete(prompt: String, maxTokens: Int, temperature: Double) async throws -> String {
        guard state.hasResidentModel, let container else {
            throw LocalLLMError.notLoaded
        }

        // Run off the main actor (the container is a Sendable actor) to avoid a
        // priority inversion, mirroring LocalLLMManager.
        let work = Task.detached(priority: .userInitiated) { () -> String in
            let input = UserInput(chat: [.user(prompt)])
            let lmInput = try await container.prepare(input: input)
            let params = GenerateParameters(
                maxTokens: maxTokens,
                temperature: Float(temperature),
                topP: 1.0
            )
            let stream = try await container.generate(input: lmInput, parameters: params)
            var output = ""
            for await item in stream {
                if Task.isCancelled { break }
                if case .chunk(let text) = item {
                    output += text
                    // The emotion JSON closes with "}" — stop as soon as we have
                    // a complete object to keep latency minimal.
                    if output.contains("}") { break }
                }
            }
            return output
        }
        return try await work.value
    }

    // MARK: - Timeout helper

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw LocalLLMError.loadTimeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw LocalLLMError.loadTimeout }
            return result
        }
    }
}
