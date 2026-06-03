//
//  ClipboardMonitor.swift
//  BabelRobot
//
//  Watches the general pasteboard and signals when NEW content (an image or
//  text) appears — e.g. after a screenshot or a copy. It only reads the cheap
//  `changeCount` on a low-frequency timer and inspects the content once when it
//  changes; it never auto-analyzes. The feature surfaces a Yes/No prompt, so
//  the user always consents before anything is read into the model.
//
//  This is clipboard change detection with explicit consent — not screen
//  monitoring. It can be turned off entirely.
//

import AppKit
import Observation

@MainActor
@Observable
final class ClipboardMonitor {

    enum Content: Equatable { case image, text }

    /// Fired when new clipboard content is detected.
    var onChange: ((Content) -> Void)?

    private var task: Task<Void, Never>?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let interval: TimeInterval = 0.7

    func start() {
        guard task == nil else { return }
        // Ignore whatever was already on the clipboard at startup.
        lastChangeCount = NSPasteboard.general.changeCount
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.interval ?? 0.7) * 1_000_000_000))
                if Task.isCancelled { return }
                self?.poll()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Re-sync the baseline so we don't re-prompt for content we just consumed
    /// or produced ourselves.
    func acknowledge() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// Image UTIs a screenshot / copied picture typically lands on the clipboard as.
    private let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .pdf]

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        // Detect images robustly: screenshots arrive as PNG/TIFF, which
        // `canReadObject(NSImage)` sometimes misses depending on the source.
        if pb.availableType(from: imageTypes) != nil
            || pb.canReadObject(forClasses: [NSImage.self], options: nil) {
            onChange?(.image)
        } else if let s = pb.string(forType: .string),
                  !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onChange?(.text)
        }
    }
}
