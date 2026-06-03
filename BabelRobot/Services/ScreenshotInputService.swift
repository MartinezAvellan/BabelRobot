//
//  ScreenshotInputService.swift
//  BabelRobot
//
//  Explicit, user-initiated screenshot input. This service NEVER reads the
//  screen or the clipboard on its own — only when the user pastes, drops, or
//  picks a file. There is no automatic screen monitoring.
//

import AppKit
import UniformTypeIdentifiers

enum ScreenshotInputError: LocalizedError {
    case noImageInClipboard
    case tooLarge
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noImageInClipboard: return "Clipboard does not contain an image."
        case .tooLarge:           return "Screenshot is too large."
        case .unreadable:         return "Could not read the screenshot."
        }
    }
}

@MainActor
struct ScreenshotInputService {

    /// Largest accepted image edge, in pixels.
    static let maxDimension: CGFloat = 4096

    /// Read an image from the general pasteboard (user clicked "Paste Screenshot").
    func imageFromPasteboard() throws -> NSImage {
        guard let image = NSImage(pasteboard: .general) else {
            throw ScreenshotInputError.noImageInClipboard
        }
        try validate(image)
        return image
    }

    /// Open an NSOpenPanel to pick a PNG / JPEG image file.
    func chooseImageFile() async -> NSImage? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image
    }

    /// Validate a pasted / dropped / chosen image against the size limit.
    func validate(_ image: NSImage) throws {
        let size = image.pixelSize ?? image.size
        guard size.width > 0, size.height > 0 else {
            throw ScreenshotInputError.unreadable
        }
        guard size.width <= Self.maxDimension, size.height <= Self.maxDimension else {
            throw ScreenshotInputError.tooLarge
        }
    }
}

extension NSImage {
    /// True pixel dimensions (NSImage.size is measured in points).
    var pixelSize: CGSize? {
        guard let rep = representations.first else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }
}
