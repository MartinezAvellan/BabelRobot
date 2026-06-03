//
//  LocalLLMBenchmark.swift
//  BabelRobot
//
//  DEBUG-only benchmark logging for model load + generation. Captures
//  device facts, timings, tokens/sec and memory snapshots around each phase.
//  In release builds these helpers compile to no-ops.
//

import Foundation
import OSLog

/// One captured run (a load and/or a generation).
struct BenchmarkRecord: Sendable {
    var modelId: String
    var deviceModel: String
    var osVersion: String
    var physicalRAMGB: Double

    var loadTime: TimeInterval?
    var firstTokenLatency: TimeInterval?
    var generationTime: TimeInterval?
    var tokensPerSecond: Double?
    var inputCharacters: Int?
    var outputTokens: Int?

    var ramBeforeLoad: MemorySnapshot?
    var ramAfterLoad: MemorySnapshot?
    var ramAfterGeneration: MemorySnapshot?
    var ramAfterUnload: MemorySnapshot?

    var gpuCacheCleanupExecuted: Bool = false
    var success: Bool = true
    var failureMessage: String?

    init(modelId: String) {
        self.modelId = modelId
        self.deviceModel = LocalMemoryMonitor.deviceModel
        self.osVersion = LocalMemoryMonitor.osVersion
        self.physicalRAMGB = LocalMemoryMonitor.physicalRAMGB
    }
}

enum LocalLLMBenchmark {

    private static let logger = Logger(subsystem: "com.quarkteck.BabelRobot", category: "Benchmark")

    /// Emit a full record to the unified log. No-op outside DEBUG.
    static func log(_ record: BenchmarkRecord) {
        #if DEBUG
        logger.debug("\(format(record), privacy: .public)")
        #endif
    }

    /// Lightweight phase marker. No-op outside DEBUG.
    static func mark(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    static func format(_ r: BenchmarkRecord) -> String {
        func ms(_ t: TimeInterval?) -> String { t.map { String(format: "%.0f ms", $0 * 1000) } ?? "—" }
        func mem(_ m: MemorySnapshot?) -> String { m?.description ?? "—" }

        return """

        ───────── Babel Robot benchmark ─────────
        model:               \(r.modelId)
        device:              \(r.deviceModel)
        macOS:               \(r.osVersion)
        physical RAM:        \(String(format: "%.1f", r.physicalRAMGB)) GB
        load time:           \(ms(r.loadTime))
        first token latency: \(ms(r.firstTokenLatency))
        generation time:     \(ms(r.generationTime))
        tokens/sec:          \(r.tokensPerSecond.map { String(format: "%.1f", $0) } ?? "—")
        input characters:    \(r.inputCharacters.map(String.init) ?? "—")
        output tokens:       \(r.outputTokens.map(String.init) ?? "—")
        RAM before load:     \(mem(r.ramBeforeLoad))
        RAM after load:      \(mem(r.ramAfterLoad))
        RAM after gen:       \(mem(r.ramAfterGeneration))
        RAM after unload:    \(mem(r.ramAfterUnload))
        GPU cache cleanup:   \(r.gpuCacheCleanupExecuted ? "yes" : "no")
        result:              \(r.success ? "success" : "FAILURE: \(r.failureMessage ?? "unknown")")
        ─────────────────────────────────────────
        """
    }
}
