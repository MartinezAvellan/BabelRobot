//
//  PersonalityModelRegistry.swift
//  BabelRobot
//
//  The tiny models offered for *emotion classification only* (the Personality
//  Model). These are intentionally small so they can stay resident alongside
//  the main chat LLM without meaningful memory pressure. They never answer the
//  user — they only label the robot's emotion.
//
//  Default: Qwen 2.5 0.5B Instruct (4-bit).
//

import Foundation

enum PersonalityModelRegistry {

    /// The selectable Personality Models, in display order.
    static let all: [LocalModelConfig] = [
        LocalModelConfig(
            id: "personality-qwen2.5-0.5b",
            displayName: "Qwen 2.5 0.5B Instruct",
            huggingFaceId: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            parametersLabel: "0.5B",
            quantization: "4-bit",
            approximateSizeMB: 300,
            estimatedRAMMB: 450,
            note: "Default. Best multilingual (PT/EN/ES) emotion read at a tiny size."
        ),
        LocalModelConfig(
            id: "personality-smollm2-360m",
            displayName: "SmolLM2 360M Instruct",
            huggingFaceId: "mlx-community/SmolLM2-360M-Instruct-4bit",
            parametersLabel: "360M",
            quantization: "4-bit",
            approximateSizeMB: 230,
            estimatedRAMMB: 320,
            note: "Lighter. Stable, fast emotion classification."
        ),
        LocalModelConfig(
            id: "personality-smollm2-135m",
            displayName: "SmolLM2 135M Instruct",
            huggingFaceId: "mlx-community/SmolLM2-135M-Instruct-4bit",
            parametersLabel: "135M",
            quantization: "4-bit",
            approximateSizeMB: 120,
            estimatedRAMMB: 150,
            note: "Smallest footprint. Quickest, lowest RAM."
        ),
    ]

    /// The model selected by default for personality classification.
    static var `default`: LocalModelConfig {
        model(withId: "personality-qwen2.5-0.5b") ?? all[0]
    }

    /// Look up a Personality Model by slug.
    static func model(withId id: String) -> LocalModelConfig? {
        all.first { $0.id == id }
    }
}
