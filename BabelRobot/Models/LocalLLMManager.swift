//
//  LocalLLMManager.swift
//  BabelRobot
//
//  Owns the model lifecycle: load, generate (streaming), unload, switch.
//  Enforces the LocalModelState machine, applies load/generation timeouts,
//  guarantees only one resident model, and cleans up GPU memory on unload.
//
//  MainActor-isolated (the project default). Heavy work happens inside the
//  MLX `ModelContainer` actor; this class only orchestrates and observes.
//

import Foundation
import Observation
import MLX
import MLXLMCommon

/// Tunable generation settings exposed in the UI.
struct GenerationSettings: Sendable {
    var temperature: Float = 0.2
    var topP: Float = 0.9
    var maxTokens: Int = 512

    /// Deterministic preset reserved for a future translation mode.
    static let translation = GenerationSettings(temperature: 0.0, topP: 1.0, maxTokens: 160)
}

/// Friendly, user-facing errors. Technical detail is logged in DEBUG only.
enum LocalLLMError: LocalizedError {
    case notLoaded
    case busy
    case loadFailed(underlying: String)
    case loadTimeout
    case outOfMemory
    case generationFailed(underlying: String)
    case generationTimeout

    var errorDescription: String? {
        switch self {
        case .notLoaded:           return "Please load a model first."
        case .busy:                return "The robot is busy. Please wait a moment."
        case .loadFailed:          return "Could not load the local model."
        case .loadTimeout:         return "Loading took too long. Please try again."
        case .outOfMemory:         return "Not enough memory to load this model."
        case .generationFailed:    return "Local generation failed. Please try again."
        case .generationTimeout:   return "Generation timed out. Please try again."
        }
    }
}

@MainActor
@Observable
final class LocalLLMManager {

    // MARK: Tunables

    private let loadTimeout: TimeInterval = 120
    private let generationTimeout: TimeInterval = 60

    private let systemPrompt = """
        You are Babel Robot, a friendly AI assistant running locally on this Mac. \
        You may be given live context (date, location, weather) and web search \
        results below. When such information is provided, use it to answer with \
        up-to-date facts and do NOT say you are offline or lack internet access — \
        the app has already fetched what you need. Cite sources when helpful. \
        Answer clearly and concisely.
        """

    /// Optional context (time / place / weather) injected into the system prompt
    /// so answers can be situationally aware. Supplied by the Awareness layer;
    /// `nil` keeps the assistant context-free. Never affects local-only inference.
    var contextProvider: (() -> String?)?

    /// The system prompt plus any live awareness context.
    private var effectiveSystemPrompt: String {
        guard let context = contextProvider?(), !context.isEmpty else { return systemPrompt }
        return systemPrompt + "\n" + context
    }

    // MARK: Observable state

    private(set) var state: LocalModelState = .unloaded
    /// 0...1 download progress while fetching weights from Hugging Face.
    private(set) var loadProgress: Double = 0
    /// True once the download has finished and the weights are being mapped into
    /// memory (the phase after the download bar, with no fine-grained progress).
    private(set) var isMappingIntoMemory = false
    /// Set when the user cancels an in-progress load; the completed container is
    /// then discarded rather than becoming resident.
    private var loadCancelled = false

    // Last completed generation stats (for the metrics panel).
    private(set) var lastTokensPerSecond: Double?
    private(set) var lastGenerationTime: TimeInterval?
    private(set) var lastFirstTokenLatency: TimeInterval?

    // MARK: Private

    private var container: ModelContainer?
    private var generationWorkTask: Task<GenerationOutcome, Error>?

    private struct GenerationOutcome: Sendable {
        var text: String
        var info: GenerateCompletionInfo?
        var firstTokenLatency: TimeInterval?
        var cancelled: Bool
    }

    // MARK: - Loading

    /// Load the given model. If another model is resident it is unloaded first
    /// (so memory never accumulates). Rejected while generating.
    func load(_ model: LocalModelConfig) async {
        guard !state.isBusy else { return }

        // Switching models: unload the current one first.
        if state.hasResidentModel {
            await unload()
        }

        guard transition(to: .loading(modelId: model.id)) else { return }
        loadProgress = 0
        isMappingIntoMemory = false
        loadCancelled = false

        var record = BenchmarkRecord(modelId: model.id)
        record.ramBeforeLoad = LocalMemoryMonitor.snapshot()
        let start = Date()

        do {
            let loaded = try await withTimeout(seconds: loadTimeout, onTimeout: LocalLLMError.loadTimeout) {
                try await LocalModelProvider.loadContainer(huggingFaceId: model.huggingFaceId) { frac in
                    Task { @MainActor in
                        guard !self.loadCancelled else { return }
                        self.loadProgress = frac
                        // Download finished → now mapping weights into memory.
                        if frac >= 1.0 { self.isMappingIntoMemory = true }
                    }
                }
            }

            // The user cancelled while we were loading: discard the result.
            if loadCancelled {
                MLX.Memory.cacheLimit = 0
                return
            }

            container = loaded
            loadProgress = 1
            isMappingIntoMemory = false
            record.loadTime = Date().timeIntervalSince(start)
            record.ramAfterLoad = LocalMemoryMonitor.snapshot()
            record.success = true
            LocalLLMBenchmark.log(record)

            _ = transition(to: .loaded(modelId: model.id))
        } catch {
            isMappingIntoMemory = false
            // A user cancel already moved us to `.unloaded`; don't mark failed.
            if loadCancelled { MLX.Memory.cacheLimit = 0; return }
            container = nil
            MLX.Memory.cacheLimit = 0  // clears the GPU/unified-memory cache (was GPU.set(cacheLimit:))
            record.success = false
            record.failureMessage = String(describing: error)
            record.ramAfterLoad = LocalMemoryMonitor.snapshot()
            LocalLLMBenchmark.log(record)

            let friendly = (error as? LocalLLMError) ?? .loadFailed(underlying: String(describing: error))
            _ = transition(to: .failed(message: friendly.errorDescription ?? "Could not load the local model."))
        }
    }

    /// Cancel an in-progress load. The UI unlocks immediately; the underlying
    /// download keeps filling the Hugging Face cache (so a later load is fast),
    /// but its result is discarded rather than becoming resident.
    func cancelLoad() {
        guard case .loading = state else { return }
        loadCancelled = true
        loadProgress = 0
        isMappingIntoMemory = false
        container = nil
        MLX.Memory.cacheLimit = 0
        _ = transition(to: .unloaded)
    }

    // MARK: - Generation

    /// Stream a response for `prompt`. `onChunk` is called on the main actor as
    /// text arrives. Returns the full text, or throws a friendly error.
    @discardableResult
    func generate(
        prompt: String,
        settings: GenerationSettings,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard case .loaded(let modelId) = state, let container else {
            throw LocalLLMError.notLoaded
        }
        guard transition(to: .generating(modelId: modelId)) else {
            throw LocalLLMError.busy
        }

        var record = BenchmarkRecord(modelId: modelId)
        record.inputCharacters = prompt.count
        let start = Date()

        // Run the streaming consumption OFF the main actor at userInitiated
        // priority. Keeping it on the MainActor (user-interactive QoS) while it
        // awaits the lower-QoS MLX `ModelContainer` actor is a priority
        // inversion (flagged as "Hang Risk"). The container is Sendable and we
        // hop back to the main actor only to deliver each chunk.
        let systemPrompt = self.effectiveSystemPrompt
        let work = Task.detached(priority: .userInitiated) { () -> GenerationOutcome in
            var output = ""
            var info: GenerateCompletionInfo?
            var firstToken: TimeInterval?
            do {
                let input = UserInput(chat: [
                    .system(systemPrompt),
                    .user(prompt),
                ])
                let lmInput = try await container.prepare(input: input)
                let params = GenerateParameters(
                    maxTokens: settings.maxTokens,
                    temperature: settings.temperature,
                    topP: settings.topP
                )
                let stream = try await container.generate(input: lmInput, parameters: params)
                for await item in stream {
                    if Task.isCancelled {
                        return GenerationOutcome(text: output, info: info, firstTokenLatency: firstToken, cancelled: true)
                    }
                    switch item {
                    case .chunk(let text):
                        if firstToken == nil { firstToken = Date().timeIntervalSince(start) }
                        output += text
                        await onChunk(text)
                    case .info(let i):
                        info = i
                    case .toolCall:
                        break
                    }
                }
                return GenerationOutcome(text: output, info: info, firstTokenLatency: firstToken, cancelled: false)
            } catch {
                // Surface as a thrown failure via empty/cancelled marker; the
                // caller distinguishes by inspecting state below.
                throw error
            }
        }
        generationWorkTask = work

        // Watchdog enforces the generation timeout by cancelling the work task.
        let watchdog = Task { [generationTimeout] in
            try? await Task.sleep(nanoseconds: UInt64(generationTimeout * 1_000_000_000))
            work.cancel()
        }
        defer { watchdog.cancel(); generationWorkTask = nil }

        let result = await work.result

        switch result {
        case .success(let outcome):
            record.firstTokenLatency = outcome.firstTokenLatency
            record.generationTime = outcome.info?.generateTime ?? Date().timeIntervalSince(start)
            record.tokensPerSecond = outcome.info?.tokensPerSecond
            record.outputTokens = outcome.info?.generationTokenCount
            record.ramAfterGeneration = LocalMemoryMonitor.snapshot()
            record.success = !outcome.cancelled
            if outcome.cancelled { record.failureMessage = "cancelled or timed out" }
            LocalLLMBenchmark.log(record)

            lastTokensPerSecond = record.tokensPerSecond
            lastGenerationTime = record.generationTime
            lastFirstTokenLatency = record.firstTokenLatency

            _ = transition(to: .loaded(modelId: modelId))

            if outcome.cancelled && outcome.text.isEmpty {
                throw LocalLLMError.generationTimeout
            }
            return outcome.text

        case .failure(let error):
            record.success = false
            record.failureMessage = String(describing: error)
            record.ramAfterGeneration = LocalMemoryMonitor.snapshot()
            LocalLLMBenchmark.log(record)
            _ = transition(to: .loaded(modelId: modelId))
            throw LocalLLMError.generationFailed(underlying: String(describing: error))
        }
    }

    /// Cancel an in-flight generation, if any.
    func cancelGeneration() {
        generationWorkTask?.cancel()
    }

    // MARK: - Unloading

    /// Cancel generation, release the model, and clear the GPU cache.
    func unload() async {
        cancelGeneration()
        guard state.hasResidentModel else {
            // Nothing resident — still make sure we are in a clean state.
            if case .failed = state { _ = transition(to: .unloaded) }
            return
        }
        let id = state.modelId ?? "?"
        guard transition(to: .unloading(modelId: id)) else { return }

        var record = BenchmarkRecord(modelId: id)
        record.ramBeforeLoad = LocalMemoryMonitor.snapshot()

        // Drop all strong references so the container/model can deallocate.
        autoreleasepool {
            container = nil
        }

        // Acceptance criterion: GPU.set(cacheLimit: 0) is called during unload.
        MLX.Memory.cacheLimit = 0  // clears the GPU/unified-memory cache (was GPU.set(cacheLimit:))
        record.gpuCacheCleanupExecuted = true

        record.ramAfterUnload = LocalMemoryMonitor.snapshot()
        record.success = true
        LocalLLMBenchmark.log(record)

        loadProgress = 0
        _ = transition(to: .unloaded)
    }

    /// Called on app shutdown. Best-effort synchronous cleanup.
    func shutdown() {
        generationWorkTask?.cancel()
        autoreleasepool {
            container = nil
        }
        MLX.Memory.cacheLimit = 0  // clears the GPU/unified-memory cache (was GPU.set(cacheLimit:))
        state = .unloaded
    }

    // MARK: - State machine

    @discardableResult
    private func transition(to next: LocalModelState) -> Bool {
        guard state.canTransition(to: next) else {
            LocalLLMBenchmark.mark("Rejected transition \(state) -> \(next)")
            return false
        }
        state = next
        return true
    }

    // MARK: - Timeout helper

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        onTimeout: LocalLLMError,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw onTimeout
            }
            guard let result = try await group.next() else {
                throw onTimeout
            }
            group.cancelAll()
            return result
        }
    }
}
