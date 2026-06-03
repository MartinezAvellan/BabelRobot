//
//  SystemMetricsView.swift
//  BabelRobot
//
//  Always-visible, collapsible system metrics panel. Part of the normal UI
//  (this is a local-LLM benchmark/prototype tool). Unavailable metrics show
//  "unavailable" rather than a fabricated number.
//

import SwiftUI

struct SystemMetricsView: View {
    let metrics: SystemMetrics
    @State private var expanded = true

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $expanded) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                    row("App RAM", Self.bytes(metrics.appRAMBytes))
                    row("Available RAM", Self.bytes(metrics.freeRAMBytes))
                    row("Total RAM", Self.bytes(metrics.totalRAMBytes))
                    row("CPU usage", Self.percent(metrics.cpuUsage))
                    thermalRow
                    row("GPU memory", gpuText)
                    row("macOS", metrics.osVersion)
                    row("Mac model", metrics.deviceModel)
                    row("Chip / arch", chipText)
                }
                .font(.system(.callout, design: .monospaced))
                .padding(.top, 8)
            } label: {
                Label("System metrics", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.headline)
            }
        }
    }

    // MARK: Rows

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var thermalRow: some View {
        GridRow {
            Text("Thermal state")
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(Self.thermalColor(metrics.thermalState))
                    .frame(width: 9, height: 9)
                Text(Self.thermalText(metrics.thermalState))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Derived strings

    private var gpuText: String {
        guard !metrics.gpuUnavailable, let allocated = metrics.gpuAllocatedBytes else {
            return "unavailable"
        }
        if let budget = metrics.gpuBudgetBytes, budget > 0 {
            return "\(Self.bytes(allocated)) / \(Self.bytes(budget))"
        }
        return Self.bytes(allocated)
    }

    private var chipText: String {
        switch (metrics.chip, metrics.architecture) {
        case let (chip?, arch?): return "\(chip) · \(arch)"
        case let (chip?, nil):   return chip
        case let (nil, arch?):   return arch
        default:                 return "unavailable"
        }
    }

    // MARK: Formatting

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useMB, .useGB]
        return f
    }()

    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "unavailable" }
        return byteFormatter.string(fromByteCount: Int64(value))
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "unavailable" }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }

    static func thermalText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    static func thermalColor(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal:  return .green
        case .fair:     return .yellow
        case .serious:  return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }
}

#Preview {
    SystemMetricsView(metrics: SystemMetrics())
        .padding()
        .frame(width: 420)
}
