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
    @Environment(\.palette) private var palette

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("Device", systemImage: "cpu")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 0) {
                    metric("thermometer.medium",
                           Self.thermalText(metrics.thermalState), "Thermal",
                           tint: Self.thermalColor(metrics.thermalState))
                    metric("cpu", Self.percent(metrics.cpuUsage), "CPU")
                    metric("memorychip", Self.bytes(metrics.appRAMBytes), "App RAM")
                    metric("square.stack.3d.up.fill", Self.bytes(metrics.freeRAMBytes), "Free RAM")
                }
            }
        }
    }

    /// One metric column: icon, big value, caption.
    private func metric(_ icon: String, _ value: String, _ label: String,
                        tint: Color? = nil) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint ?? palette.accent)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .textSelection(.enabled)
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
