//
//  SystemMetricsMonitor.swift
//  BabelRobot
//
//  Always-on system metrics for this local-LLM benchmark/prototype tool.
//  Samples real values from Mach / Metal / ProcessInfo once per second with
//  low overhead. Anything that cannot be read reliably is reported as
//  unavailable — never faked.
//
//  Not DEBUG-gated. Monitoring stops when `stop()` is called (app close).
//

import Foundation
import Observation
import Metal
import Darwin

/// A single snapshot of host metrics. Optional fields are `nil` when the
/// underlying API did not return a reliable value.
struct SystemMetrics: Sendable {
    var appRAMBytes: UInt64?
    var freeRAMBytes: UInt64?
    var totalRAMBytes: UInt64
    /// System-wide CPU usage, 0...1. `nil` until the first delta is available.
    var cpuUsage: Double?
    var thermalState: ProcessInfo.ThermalState
    /// Memory currently allocated to the default Metal device by this process.
    var gpuAllocatedBytes: UInt64?
    /// Recommended max working set for the Metal device (its memory budget).
    var gpuBudgetBytes: UInt64?
    var gpuUnavailable: Bool
    var osVersion: String
    var deviceModel: String
    /// e.g. "Apple M2 Pro" — the CPU brand string.
    var chip: String?
    /// e.g. "arm64".
    var architecture: String?

    init() {
        self.totalRAMBytes = ProcessInfo.processInfo.physicalMemory
        self.thermalState = ProcessInfo.processInfo.thermalState
        self.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        self.deviceModel = "—"
        self.gpuUnavailable = true
    }
}

@MainActor
@Observable
final class SystemMetricsMonitor {

    private(set) var metrics = SystemMetrics()

    private var task: Task<Void, Never>?
    private var previousCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    /// Cached so we don't recreate the Metal device every second.
    private let metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()

    // Static host facts, read once.
    private let staticDeviceModel = SystemMetricsMonitor.sysctlString("hw.model") ?? "Unknown Mac"
    private let staticChip = SystemMetricsMonitor.sysctlString("machdep.cpu.brand_string")
    private let staticArch = SystemMetricsMonitor.sysctlString("hw.machine")

    func start() {
        guard task == nil else { return }
        sample()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self?.sample()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - Sampling

    private func sample() {
        var m = SystemMetrics()
        m.appRAMBytes = Self.appMemoryFootprint()
        m.freeRAMBytes = Self.freeMemory()
        m.cpuUsage = systemCPUUsage()
        m.thermalState = ProcessInfo.processInfo.thermalState

        if let device = metalDevice {
            m.gpuAllocatedBytes = UInt64(device.currentAllocatedSize)
            m.gpuBudgetBytes = device.recommendedMaxWorkingSetSize
            m.gpuUnavailable = false
        } else {
            m.gpuUnavailable = true
        }

        m.deviceModel = staticDeviceModel
        m.chip = staticChip
        m.architecture = staticArch

        metrics = m
    }

    // MARK: - CPU (needs delta between samples)

    private func systemCPUUsage() -> Double? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let ticks = info.cpu_ticks
        let current = (user: ticks.0, system: ticks.1, idle: ticks.2, nice: ticks.3)
        defer { previousCPUTicks = current }

        // First sample: no delta yet — report unavailable rather than a fake value.
        guard let prev = previousCPUTicks else { return nil }

        let dUser = Double(current.user &- prev.user)
        let dSystem = Double(current.system &- prev.system)
        let dIdle = Double(current.idle &- prev.idle)
        let dNice = Double(current.nice &- prev.nice)
        let busy = dUser + dSystem + dNice
        let total = busy + dIdle
        guard total > 0 else { return nil }
        return busy / total
    }

    // MARK: - Memory

    private static func appMemoryFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }

    /// Memory the system can hand out right now, matching Activity Monitor's
    /// sense of "available" — not the tiny `free_count`.
    ///
    /// macOS keeps `free_count` near zero on purpose: it fills otherwise-idle
    /// RAM with the file cache plus inactive / purgeable / speculative pages,
    /// all of which it reclaims instantly under pressure. Reporting only
    /// `free_count` made a 64 GB Mac with 20+ GB available look like it had
    /// ~700 MB. Available ≈ free + inactive + purgeable + speculative.
    private static func freeMemory() -> UInt64? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }

        let reclaimablePages = UInt64(stats.free_count)
            + UInt64(stats.inactive_count)
            + UInt64(stats.purgeable_count)
            + UInt64(stats.speculative_count)
        return reclaimablePages * UInt64(pageSize)
    }

    // MARK: - sysctl helper

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
