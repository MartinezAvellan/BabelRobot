//
//  ScreenshotOCRService.swift
//  BabelRobot
//
//  On-device OCR with Apple's Vision framework (VNRecognizeTextRequest).
//  Recognizes English, Portuguese, and Spanish, preserves reading order as
//  much as possible (top-to-bottom, left-to-right), and reports an average
//  confidence. Everything runs locally — nothing leaves this Mac.
//

import Foundation
import Vision
import AppKit

/// Text recognized from a screenshot.
struct OCRResult: Sendable {
    var rawText: String
    var lines: [String]
    var confidenceAverage: Double?
    var imageSize: CGSize
    var createdAt: Date
}

enum ScreenshotOCRError: LocalizedError {
    case invalidImage
    case noText

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not read the screenshot."
        case .noText:       return "Could not extract text from this image."
        }
    }
}

struct ScreenshotOCRService {

    /// Languages Vision will try, in priority order.
    var recognitionLanguages = ["en-US", "pt-BR", "es-ES"]

    func extractText(from image: NSImage) async throws -> OCRResult {
        guard let cg = image.cgImageForOCR() else {
            throw ScreenshotOCRError.invalidImage
        }
        let size = CGSize(width: cg.width, height: cg.height)
        let languages = recognitionLanguages

        // Vision is CPU/GPU bound and synchronous — run it off the main actor
        // and return only the Sendable OCRResult.
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            guard !observations.isEmpty else { throw ScreenshotOCRError.noText }

            // Reading order: top-to-bottom, then left-to-right. Vision's
            // boundingBox is normalized with origin at the bottom-left, so a
            // larger midY is higher on the page.
            let ordered = observations.sorted { a, b in
                let ay = a.boundingBox.midY, by = b.boundingBox.midY
                if abs(ay - by) > 0.02 { return ay > by }      // different rows
                return a.boundingBox.minX < b.boundingBox.minX // same row
            }

            var lines: [String] = []
            var confidences: [Float] = []
            for obs in ordered {
                guard let candidate = obs.topCandidates(1).first else { continue }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }
                lines.append(text)
                confidences.append(candidate.confidence)
            }

            guard !lines.isEmpty else { throw ScreenshotOCRError.noText }

            let avg = confidences.isEmpty
                ? nil
                : Double(confidences.reduce(0, +) / Float(confidences.count))

            return OCRResult(
                rawText: lines.joined(separator: "\n"),
                lines: lines,
                confidenceAverage: avg,
                imageSize: size,
                createdAt: Date()
            )
        }.value
    }
}

private extension NSImage {
    /// A CGImage suitable for Vision OCR.
    func cgImageForOCR() -> CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
