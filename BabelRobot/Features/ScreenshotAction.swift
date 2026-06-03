//
//  ScreenshotAction.swift
//  BabelRobot
//
//  The actions the user can run against a screenshot's OCR text, and the
//  prompt template each one feeds to the local model. Only the extracted text
//  (never the image) is ever sent to the LLM.
//

import Foundation

enum ScreenshotAction: String, CaseIterable, Identifiable, Sendable {
    case explain
    case summarize
    case translate
    case extractTasks
    case ask

    var id: String { rawValue }

    /// The quick actions surfaced as buttons on the desktop companion (Ask is
    /// excluded — it needs typing, which doesn't suit the floating robot).
    static let quickActions: [ScreenshotAction] = [.explain, .summarize, .extractTasks, .translate]

    var title: String {
        switch self {
        case .explain:      return "Explain"
        case .summarize:    return "Summarize"
        case .translate:    return "Translate"
        case .extractTasks: return "Extract Tasks"
        case .ask:          return "Ask"
        }
    }

    var symbol: String {
        switch self {
        case .explain:      return "text.magnifyingglass"
        case .summarize:    return "doc.text"
        case .translate:    return "character.book.closed"
        case .extractTasks: return "checklist"
        case .ask:          return "questionmark.bubble"
        }
    }

    /// Ask needs a user question; Translate needs a target language.
    var needsQuestion: Bool { self == .ask }
    var needsLanguage: Bool { self == .translate }

    /// Build the LLM prompt from the OCR text (plus the extra input that
    /// Ask / Translate require).
    func prompt(
        ocrText: String,
        question: String = "",
        targetLanguage: String = "English"
    ) -> String {
        switch self {
        case .explain:
            return """
            Use the following OCR text extracted from a screenshot and explain what it means clearly:

            \(ocrText)
            """
        case .summarize:
            return """
            Summarize the following screenshot content:

            \(ocrText)
            """
        case .translate:
            return """
            Translate the following screenshot text to \(targetLanguage). Return only the translation:

            \(ocrText)
            """
        case .extractTasks:
            return """
            Extract actionable tasks from the following screenshot text:

            \(ocrText)
            """
        case .ask:
            return """
            Use the screenshot OCR text as context to answer the question.

            Screenshot OCR text:
            \(ocrText)

            Question:
            \(question)
            """
        }
    }
}
