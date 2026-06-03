//
//  ScreenshotUnderstandingViewModel.swift
//  BabelRobot
//
//  Orchestrates the screenshot-understanding flow end to end:
//
//    provide image → OCR (Vision) → review text → action → local LLM → answer
//
//  The robot face is driven through an override closure (wired to the desktop
//  companion). The LLM runs on the currently loaded local model via a closure,
//  so this module stays decoupled from the model code.
//
//  Privacy: the image and OCR text live only in memory and are wiped on Clear.
//  Nothing is written to disk, and only the OCR text (never the image) is sent
//  to the model.
//

import SwiftUI
import Observation
import AppKit

@MainActor
@Observable
final class ScreenshotUnderstandingViewModel {

    enum Phase: Equatable {
        case empty          // no image
        case hasImage       // image provided, OCR not started/finished
        case runningOCR
        case ready          // OCR text available, awaiting an action
        case generating     // LLM running
        case error
    }

    /// New clipboard content awaiting the user's yes/no decision.
    enum Pending {
        case image(NSImage)
        case text(String)

        var prompt: String {
            switch self {
            case .image: return "New image in the clipboard — analyze it?"
            case .text:  return "New copied text — analyze it?"
            }
        }
    }

    // MARK: - Observed state
    private(set) var phase: Phase = .empty
    private(set) var image: NSImage?
    private(set) var context: ScreenshotContext?
    private(set) var errorMessage: String?
    private(set) var ocrDurationSeconds: Double?
    private(set) var lastAction: ScreenshotAction?
    /// New clipboard content waiting for the user's yes/no, or nil. Mirrored to
    /// the desktop companion's "Analyze it?" bubble.
    private(set) var pending: Pending? { didSet { onPending?(pending?.prompt) } }

    // MARK: - User inputs
    var question = ""
    var targetLanguage = "English"
    /// Whether to watch the clipboard and offer to analyze new content.
    var watchClipboard: Bool { didSet { persistWatch(); applyWatch() } }

    // MARK: - Limits
    private let maxOCRCharacters = 12_000

    // MARK: - Services
    private let input = ScreenshotInputService()
    private let ocrService = ScreenshotOCRService()
    private let clipboard = ClipboardMonitor()

    // MARK: - Wiring (set once in BabelRobotApp)

    /// Whether a local model is currently loaded.
    var isModelLoaded: (() -> Bool)?
    /// Run a prompt on the loaded model, streaming chunks. Returns full text.
    var generate: ((String, @escaping @MainActor (String) -> Void) async -> String?)?
    /// Push a face override to the desktop companion (nil clears it).
    var onFaceState: ((RobotFaceState?) -> Void)?
    /// Streamed speech, sharing the voice mode's TTS pipeline (same configs).
    /// `speechBegin` returns true when it will actually speak.
    var speechBegin: (() -> Bool)?
    var speechFeed: ((String) -> Void)?
    var speechEnd: (() -> Void)?
    /// Mirror the "analyze?" prompt onto the desktop companion's speech bubble.
    var onPending: ((String?) -> Void)?
    /// Show / hide the quick-action buttons (Explain / Summarize / Tasks /
    /// Translate) on the desktop companion. Empty array hides them.
    var onActions: (([ScreenshotAction]) -> Void)?
    /// Clear the shared response box (answers now render there, not here).
    var clearShared: (() -> Void)?
    /// Put the ready OCR / copied text into the shared prompt box for review.
    var onTextReady: ((String) -> Void)?
    /// Target language for Translate — taken from Voice Conversation's setting.
    var targetLanguageProvider: (() -> String)?
    /// Last LLM generation stats for the metrics row: (seconds, tokens/sec, model).
    var lastGenStats: (() -> (Double?, Double?, String)?)?

    private var ocrTask: Task<Void, Never>?
    private var genTask: Task<Void, Never>?
    private var faceResetTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        watchClipboard = UserDefaults.standard.object(forKey: Self.watchKey) as? Bool ?? true
        clipboard.onChange = { [weak self] kind in self?.clipboardChanged(kind) }
        // Watch from launch so a screenshot/copy is offered even before the
        // Screenshot section scrolls into view.
        if watchClipboard { clipboard.start() }
    }

    // MARK: - Derived

    var ocrText: String { context?.ocrText ?? "" }
    var hasText: Bool { !(context?.ocrText.isEmpty ?? true) }
    var characterCount: Int { context?.characterCount ?? 0 }
    var truncated: Bool { context?.truncated ?? false }
    var confidence: Double? { context?.averageConfidence }
    var isBusy: Bool { phase == .runningOCR || phase == .generating }
    /// Resolved Translate target (the Voice Conversation language).
    var translateTargetName: String { targetLanguageProvider?() ?? targetLanguage }

    var statusMessage: String {
        switch phase {
        case .empty:      return "Provide a screenshot to read."
        case .hasImage:   return "Screenshot loaded."
        case .runningOCR: return "Reading screenshot…"
        case .ready:      return "Text ready — choose an action."
        case .generating: return "Thinking…"
        case .error:      return errorMessage ?? "Something went wrong."
        }
    }

    // MARK: - Input entry points

    func pasteScreenshot() {
        do { setImage(try input.imageFromPasteboard()) }
        catch { fail(error.localizedDescription) }
    }

    func chooseImage() {
        Task {
            guard let image = await input.chooseImageFile() else { return }
            do { try input.validate(image); setImage(image) }
            catch { fail(error.localizedDescription) }
        }
    }

    // MARK: - Clipboard watching (with consent)

    /// Start watching the clipboard (called when the section appears).
    func startMonitoringClipboard() { applyWatch() }

    private func applyWatch() {
        watchClipboard ? clipboard.start() : clipboard.stop()
        if !watchClipboard { pending = nil }
    }

    /// New clipboard content was detected — stage a yes/no prompt (don't read
    /// it into the model until the user says yes). Ignored while busy.
    private func clipboardChanged(_ kind: ClipboardMonitor.Content) {
        guard !isBusy else { return }
        let pb = NSPasteboard.general
        switch kind {
        case .image:
            if let image = NSImage(pasteboard: pb) { pending = .image(image) }
        case .text:
            if let text = pb.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                pending = .text(text)
            }
        }
    }

    /// User chose "Yes": analyze the staged clipboard content.
    func acceptPending() {
        guard let pending else { return }
        self.pending = nil
        clipboard.acknowledge()
        switch pending {
        case .image(let image):
            do { try input.validate(image); setImage(image) }
            catch { fail(error.localizedDescription) }
        case .text(let text):
            ingestText(text)
        }
    }

    /// User chose "No": discard the prompt and don't re-ask for this content.
    func dismissPending() {
        pending = nil
        clipboard.acknowledge()
    }

    // MARK: - OCR

    private func setImage(_ image: NSImage) {
        cancelAll()
        pending = nil
        onActions?([])
        clearShared?()
        self.image = image
        context = nil
        errorMessage = nil
        lastAction = nil
        ocrDurationSeconds = nil
        phase = .hasImage
        setFace(.curious)
        runOCR()
    }

    /// Ingest copied text directly (no OCR / image) so the actions can run on it.
    private func ingestText(_ text: String) {
        cancelAll()
        pending = nil
        clearShared?()
        image = nil
        errorMessage = nil
        lastAction = nil
        ocrDurationSeconds = nil
        context = ScreenshotContext(text: text, maxCharacters: maxOCRCharacters)
        phase = .ready
        onTextReady?(context?.ocrText ?? text)       // text lands in the prompt
        setFace(.curious, clearAfter: 1.4)
        onActions?(ScreenshotAction.quickActions)   // offer the actions on the robot
    }

    private func runOCR() {
        guard let image else { return }
        phase = .runningOCR
        setFace(.lookingAtScreenshot)
        let start = Date()
        ocrTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.ocrService.extractText(from: image)
                if Task.isCancelled { return }
                self.context = ScreenshotContext(ocr: result, maxCharacters: self.maxOCRCharacters)
                self.ocrDurationSeconds = Date().timeIntervalSince(start)
                self.phase = .ready
                self.onTextReady?(self.context?.ocrText ?? "")   // text lands in the prompt
                self.setFace(.happy, clearAfter: 1.6)
                self.onActions?(ScreenshotAction.quickActions)   // show buttons on the robot
            } catch {
                if Task.isCancelled { return }
                self.fail(error.localizedDescription, face: .confused)
            }
        }
    }

    // MARK: - Actions

    func perform(_ action: ScreenshotAction) {
        guard let context, hasText else {
            fail("Could not extract text from this image.", face: .confused)
            return
        }
        guard isModelLoaded?() == true else {
            fail("Please load a local model first.", face: .error)
            return
        }
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if action.needsQuestion && trimmedQuestion.isEmpty { return }

        lastAction = action
        // Translate targets the Voice Conversation speech language.
        let targetLang = targetLanguageProvider?() ?? targetLanguage
        let prompt = action.prompt(
            ocrText: context.ocrText,
            question: trimmedQuestion,
            targetLanguage: targetLang)

        errorMessage = nil
        phase = .generating
        onActions?([])      // hide the quick actions while generating
        setFace(nil)        // the answer renders in the shared response + shared face

        // Speak the answer the SAME way Talk does: stream sentences to TTS as
        // they're generated (identical voice/rate/pacing), not one block at the end.
        let willSpeak = speechBegin?() ?? false

        genTask = Task { [weak self] in
            guard let self, let generate = self.generate else { return }
            // `generate` writes the shared response box and drives the shared face.
            _ = await generate(prompt) { [weak self] chunk in
                guard let self, willSpeak else { return }
                self.speechFeed?(chunk)
            }
            if willSpeak { self.speechEnd?() }   // flush + close the TTS queue
            if Task.isCancelled { return }
            self.phase = .ready
            self.onActions?(ScreenshotAction.quickActions)   // offer the actions again
        }
    }

    // MARK: - Clear / shutdown

    func clear() {
        cancelAll()
        pending = nil
        clipboard.acknowledge()
        onActions?([])
        clearShared?()
        image = nil
        context = nil
        errorMessage = nil
        question = ""
        lastAction = nil
        ocrDurationSeconds = nil
        phase = .empty
        setFace(nil)
    }

    /// Dismiss the on-robot action buttons and return the robot to its default
    /// (voice) controls, WITHOUT wiping the prompt/response the user may still
    /// want. Re-copying or re-pasting will offer the actions again.
    func dismissActions() {
        onActions?([])
        context = nil
        image = nil
        lastAction = nil
        ocrDurationSeconds = nil
        phase = .empty
        setFace(nil)
    }

    func shutdown() {
        cancelAll()
        clipboard.stop()
        setFace(nil)
    }

    // MARK: - Persistence

    private static let watchKey = "screenshot.watchClipboard"
    private func persistWatch() {
        UserDefaults.standard.set(watchClipboard, forKey: Self.watchKey)
    }

    // MARK: - Internals

    private func cancelAll() {
        ocrTask?.cancel(); ocrTask = nil
        genTask?.cancel(); genTask = nil
        faceResetTask?.cancel(); faceResetTask = nil
    }

    private func fail(_ message: String, face: RobotFaceState = .error) {
        errorMessage = message
        phase = .error
        setFace(face, clearAfter: 3.0)
    }

    /// Push a face override, optionally clearing it back to nil after a delay so
    /// the companion resumes its normal behavior between operations.
    private func setFace(_ state: RobotFaceState?, clearAfter: TimeInterval? = nil) {
        faceResetTask?.cancel()
        faceResetTask = nil
        onFaceState?(state)
        if let clearAfter, state != nil {
            faceResetTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(clearAfter * 1_000_000_000))
                if Task.isCancelled { return }
                self?.onFaceState?(nil)
            }
        }
    }
}
