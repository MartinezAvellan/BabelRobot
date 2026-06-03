//
//  LocalModelRegistry.swift
//  BabelRobot
//
//  The set of models this macOS app offers. These are Mac-capable, heavier
//  4-bit models (no iPhone-baseline restrictions). Only one is ever loaded at
//  a time (see LocalLLMManager); switching unloads the previous model first.
//
//  The default is Llama 3.2 3B Instruct (4-bit).
//

import Foundation

enum LocalModelRegistry {

    /// A coarse size tier, shown as a section header in the selector.
    enum Tier: String, CaseIterable, Sendable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"
    }

    /// Models shown in the selector, grouped by tier. The default is the first
    /// Medium model (Llama 3.1 8B), which is auto-loaded on launch.
    static let all: [LocalModelConfig] = small + medium + large

    /// Models for a given tier, in display order.
    static func models(in tier: Tier) -> [LocalModelConfig] {
        switch tier {
        case .small:  return small
        case .medium: return medium
        case .large:  return large
        }
    }

    // ── SMALL ──────────────────────────────────────────────────────────────
    static let small: [LocalModelConfig] = [
        LocalModelConfig(
            id: "llama3.2-3b",
            displayName: "Llama 3.2 3B Instruct",
            huggingFaceId: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            parametersLabel: "3B",
            quantization: "4-bit",
            approximateSizeMB: 1800,
            estimatedRAMMB: 3000,
            note: "Fast, light. Great on 8 GB Macs."
        ),
        LocalModelConfig(
            id: "qwen3-4b",
            displayName: "Qwen 3 4B",
            huggingFaceId: "mlx-community/Qwen3-4B-4bit",
            parametersLabel: "4B",
            quantization: "4-bit",
            approximateSizeMB: 2300,
            estimatedRAMMB: 3600,
            note: "Newer 4B with strong reasoning."
        ),
        LocalModelConfig(
            id: "deepseek-r1-qwen-7b",
            displayName: "DeepSeek R1 Distill Qwen 7B",
            huggingFaceId: "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit",
            parametersLabel: "7B",
            quantization: "4-bit",
            approximateSizeMB: 4300,
            estimatedRAMMB: 6000,
            note: "Reasoning distill. Emits <think> traces. ~8 GB+ RAM."
        ),
        LocalModelConfig(
            id: "gemma3-4b",
            displayName: "Gemma 3 4B Instruct",
            huggingFaceId: "mlx-community/gemma-3-4b-it-4bit",
            parametersLabel: "4B",
            quantization: "4-bit",
            approximateSizeMB: 2600,
            estimatedRAMMB: 4200,
            note: "Google Gemma 3, 4B instruct."
        ),
    ]

    // ── MEDIUM ─────────────────────────────────────────────────────────────
    static let medium: [LocalModelConfig] = [
        LocalModelConfig(
            id: "llama3.1-8b",
            displayName: "Llama 3.1 8B Instruct",
            huggingFaceId: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            parametersLabel: "8B",
            quantization: "4-bit",
            approximateSizeMB: 4600,
            estimatedRAMMB: 7000,
            note: "Default. Auto-downloads on first launch. ~10 GB+ RAM."
        ),
        LocalModelConfig(
            id: "qwen3-8b",
            displayName: "Qwen 3 8B",
            huggingFaceId: "mlx-community/Qwen3-8B-4bit",
            parametersLabel: "8B",
            quantization: "4-bit",
            approximateSizeMB: 4700,
            estimatedRAMMB: 7000,
            note: "8B reasoning model. ~10 GB+ RAM recommended."
        ),
        LocalModelConfig(
            id: "deepseek-r1-qwen-14b",
            displayName: "DeepSeek R1 Distill Qwen 14B",
            huggingFaceId: "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit",
            parametersLabel: "14B",
            quantization: "4-bit",
            approximateSizeMB: 8000,
            estimatedRAMMB: 10500,
            note: "Reasoning distill. Emits <think> traces. 16 GB+ RAM."
        ),
        LocalModelConfig(
            id: "gemma3-12b",
            displayName: "Gemma 3 12B Instruct",
            huggingFaceId: "mlx-community/gemma-3-12b-it-4bit",
            parametersLabel: "12B",
            quantization: "4-bit",
            approximateSizeMB: 7000,
            estimatedRAMMB: 9500,
            note: "Gemma 3, 12B instruct. 16 GB+ RAM recommended."
        ),
    ]

    // ── LARGE ──────────────────────────────────────────────────────────────
    static let large: [LocalModelConfig] = [
        LocalModelConfig(
            id: "llama3.3-70b",
            displayName: "Llama 3.3 70B Instruct",
            huggingFaceId: "mlx-community/Llama-3.3-70B-Instruct-4bit",
            parametersLabel: "70B",
            quantization: "4-bit",
            approximateSizeMB: 40000,
            estimatedRAMMB: 46000,
            note: "Flagship 70B. 64 GB+ unified memory required."
        ),
        LocalModelConfig(
            id: "qwen3-14b",
            displayName: "Qwen 3 14B",
            huggingFaceId: "mlx-community/Qwen3-14B-4bit",
            parametersLabel: "14B",
            quantization: "4-bit",
            approximateSizeMB: 8000,
            estimatedRAMMB: 10500,
            note: "14B reasoning model. 16 GB+ RAM recommended."
        ),
        LocalModelConfig(
            id: "deepseek-r1-qwen-32b",
            displayName: "DeepSeek R1 Distill Qwen 32B",
            huggingFaceId: "mlx-community/DeepSeek-R1-Distill-Qwen-32B-4bit",
            parametersLabel: "32B",
            quantization: "4-bit",
            approximateSizeMB: 18000,
            estimatedRAMMB: 21000,
            note: "Strong reasoning distill. 32 GB+ unified memory."
        ),
        LocalModelConfig(
            id: "qwen3-32b",
            displayName: "Qwen 3 32B",
            huggingFaceId: "mlx-community/Qwen3-32B-4bit",
            parametersLabel: "32B",
            quantization: "4-bit",
            approximateSizeMB: 18000,
            estimatedRAMMB: 21000,
            note: "32B reasoning model. 32 GB+ unified memory recommended."
        ),
    ]

    /// Optional lightweight models, hidden from the main selector. Kept only as
    /// fallbacks for very low-memory situations or quick smoke tests.
    static let lightweightFallbacks: [LocalModelConfig] = [
        LocalModelConfig(
            id: "qwen2.5-0.5b",
            displayName: "Qwen 2.5 0.5B Instruct (fallback)",
            huggingFaceId: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            parametersLabel: "0.5B",
            quantization: "4-bit",
            approximateSizeMB: 300,
            estimatedRAMMB: 700,
            note: "Tiny fallback."
        ),
        LocalModelConfig(
            id: "qwen3-0.6b",
            displayName: "Qwen 3 0.6B (fallback)",
            huggingFaceId: "mlx-community/Qwen3-0.6B-4bit",
            parametersLabel: "0.6B",
            quantization: "4-bit",
            approximateSizeMB: 400,
            estimatedRAMMB: 800,
            note: "Tiny fallback."
        ),
        LocalModelConfig(
            id: "smollm-135m",
            displayName: "SmolLM 135M Instruct (fallback)",
            huggingFaceId: "mlx-community/SmolLM-135M-Instruct-4bit",
            parametersLabel: "135M",
            quantization: "4-bit",
            approximateSizeMB: 120,
            estimatedRAMMB: 400,
            note: "Smallest fallback."
        ),
    ]

    /// The model selected (and auto-loaded) by default when the app launches.
    static var `default`: LocalModelConfig {
        model(withId: "llama3.1-8b") ?? all[0]
    }

    /// Look up any known model (main list or hidden fallback) by slug.
    static func model(withId id: String) -> LocalModelConfig? {
        (all + lightweightFallbacks).first { $0.id == id }
    }
}
