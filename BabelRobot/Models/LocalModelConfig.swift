//
//  LocalModelConfig.swift
//  BabelRobot
//
//  Describes a single local model that can be loaded by the assistant.
//  This is our own lightweight registry entry, independent of the
//  MLX `LLMRegistry`, so we control exactly which models the POC offers.
//

import Foundation

/// A description of a local model the app knows how to load.
///
/// `id` is a short, stable slug (e.g. `llama3.2-3b`) used by the state
/// machine and selection; `huggingFaceId` is the repository that holds the
/// MLX-quantized weights. Weights are downloaded once for setup/cache and
/// then run fully offline.
struct LocalModelConfig: Identifiable, Hashable, Sendable {
    /// Short, stable identifier, e.g. `llama3.2-3b`.
    let id: String

    /// User-facing name shown in the picker.
    let displayName: String

    /// Hugging Face repository id, e.g. `mlx-community/Llama-3.2-3B-Instruct-4bit`.
    let huggingFaceId: String

    /// Parameter-count label, e.g. `3B`, `7B`, `E4B`.
    let parametersLabel: String

    /// Quantization label, e.g. `4-bit`.
    let quantization: String

    /// Approximate on-disk / download footprint, in MB.
    let approximateSizeMB: Int

    /// Estimated RAM needed to load + run the model, in MB
    /// (weights plus KV cache / working set headroom).
    let estimatedRAMMB: Int

    /// Short note about the model.
    let note: String

    /// Compact "size · quantization" label for the selector, e.g. "3B · 4-bit".
    var sizeLabel: String { "\(parametersLabel) · \(quantization)" }

    /// Human-readable estimated RAM requirement, e.g. "~3.0 GB".
    var estimatedRAMText: String { Self.gb(estimatedRAMMB) }

    /// Human-readable download size, e.g. "~1.8 GB".
    var downloadSizeText: String { Self.gb(approximateSizeMB) }

    /// True when the estimated RAM is a large fraction of this Mac's physical
    /// memory, i.e. loading may be risky. Threshold: 70% of installed RAM.
    func exceedsComfortableMemory(physicalRAMBytes: UInt64) -> Bool {
        guard physicalRAMBytes > 0 else { return false }
        let physicalMB = Double(physicalRAMBytes) / (1024 * 1024)
        return Double(estimatedRAMMB) > physicalMB * 0.70
    }

    private static func gb(_ mb: Int) -> String {
        String(format: "~%.1f GB", Double(mb) / 1024)
    }
}
