//
//  LocalMemoryMonitor.swift
//  BabelRobot
//
//  Thin wrapper over MLX memory stats plus host facts (RAM, device, OS).
//  Used by the benchmark logger to record memory before/after each phase.
//

import Foundation
import MLX

struct MemorySnapshot: Sendable {
    /// Bytes held by live MLXArrays.
    let activeBytes: Int
    /// Bytes held by the MLX buffer cache.
    let cacheBytes: Int
    /// Peak MLX memory observed.
    let peakBytes: Int

    static let zero = MemorySnapshot(activeBytes: 0, cacheBytes: 0, peakBytes: 0)

    var totalBytes: Int { activeBytes + cacheBytes }

    var description: String {
        "active \(Self.mb(activeBytes)) MB, cache \(Self.mb(cacheBytes)) MB, peak \(Self.mb(peakBytes)) MB"
    }

    static func mb(_ bytes: Int) -> Int { bytes / (1024 * 1024) }
}

enum LocalMemoryMonitor {

    /// Current MLX GPU/unified memory snapshot.
    static func snapshot() -> MemorySnapshot {
        let s = MLX.Memory.snapshot()
        return MemorySnapshot(
            activeBytes: s.activeMemory,
            cacheBytes: s.cacheMemory,
            peakBytes: s.peakMemory
        )
    }

    /// Physical RAM installed on this Mac, in bytes.
    static var physicalRAMBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    static var physicalRAMGB: Double {
        Double(physicalRAMBytes) / (1024 * 1024 * 1024)
    }

    static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    /// Hardware model identifier, e.g. "Mac15,3".
    static var deviceModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown Mac" }
        var chars = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &chars, &size, nil, 0)
        return String(cString: chars)
    }
}
