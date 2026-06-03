//
//  ScreenshotContext.swift
//  BabelRobot
//
//  The post-OCR context handed to the local model. Only the extracted text
//  leaves this struct — the raw image is never sent to the LLM. The text is
//  capped so a huge screenshot can't blow past the model's context window.
//

import Foundation
import CoreGraphics

struct ScreenshotContext: Sendable {
    /// The (possibly truncated) OCR text sent to the model.
    let ocrText: String
    /// Pixel size of the source image.
    let imageSize: CGSize
    /// True when `ocrText` was truncated to fit the limit.
    let truncated: Bool
    /// Character count of `ocrText`.
    let characterCount: Int
    /// Average OCR confidence (0…1), if Vision reported one.
    let averageConfidence: Double?

    init(ocr: OCRResult, maxCharacters: Int) {
        let raw = ocr.rawText
        if raw.count > maxCharacters {
            ocrText = String(raw.prefix(maxCharacters))
            truncated = true
        } else {
            ocrText = raw
            truncated = false
        }
        imageSize = ocr.imageSize
        characterCount = ocrText.count
        averageConfidence = ocr.confidenceAverage
    }

    /// Build a context directly from copied text (no OCR / image).
    init(text: String, maxCharacters: Int) {
        if text.count > maxCharacters {
            ocrText = String(text.prefix(maxCharacters))
            truncated = true
        } else {
            ocrText = text
            truncated = false
        }
        imageSize = .zero
        characterCount = ocrText.count
        averageConfidence = nil
    }
}
