//
//  LocalModelProvider.swift
//  BabelRobot
//
//  The single place that touches the Hugging Face download + tokenizer
//  integration. It uses the MLXHuggingFace macros, which expand to code
//  referencing the `HuggingFace` (swift-huggingface) and `Tokenizers`
//  (swift-transformers) modules — hence the imports below.
//
//  Models are downloaded from Hugging Face once (setup/cache); inference
//  afterwards is fully offline.
//

import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

enum LocalModelProvider {

    /// Download (if needed) and load a model into a thread-safe `ModelContainer`.
    ///
    /// - Parameters:
    ///   - huggingFaceId: repo id, e.g. `mlx-community/Qwen2.5-0.5B-Instruct-4bit`
    ///   - progress: fraction complete (0...1) reported during download/load
    static func loadContainer(
        huggingFaceId: String,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> ModelContainer {
        let configuration = ModelConfiguration(id: huggingFaceId)
        return try await #huggingFaceLoadModelContainer(
            configuration: configuration,
            progressHandler: { (p: Progress) in
                progress(p.fractionCompleted)
            }
        )
    }
}
