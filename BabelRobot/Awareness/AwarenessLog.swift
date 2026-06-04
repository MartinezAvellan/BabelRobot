//
//  AwarenessLog.swift
//  BabelRobot
//
//  A transparent, append-only record of every external lookup the robot makes
//  to build its sense of context (location, geocoding, weather, connectivity).
//  Kept both in memory (for the live UI) and on disk (so it can be audited after
//  the fact). Nothing here is sent anywhere — it only documents what was read.
//

import Foundation
import Observation

/// One logged lookup.
struct AwarenessLogEntry: Identifiable, Sendable, Equatable {
    let id = UUID()
    let date: Date
    let category: Category
    /// One-line human summary, e.g. "Lisbon, Portugal" or "GET api.open-meteo.com".
    let summary: String
    /// Optional extra detail (a URL, a coordinate, an error message).
    let detail: String?

    enum Category: String, Sendable {
        case location   // a device location fix
        case geocode    // reverse-geocoding a fix into a place name
        case weather    // a weather request
        case network    // connectivity change
        case permission // an authorization change
        case time       // a time/locale read (local, no network)

        var symbol: String {
            switch self {
            case .location:   return "location.fill"
            case .geocode:    return "map.fill"
            case .weather:    return "cloud.sun.fill"
            case .network:    return "wifi"
            case .permission: return "lock.shield"
            case .time:       return "clock.fill"
            }
        }

        /// Whether this category involved leaving the Mac (a network request).
        var isNetwork: Bool {
            switch self {
            case .geocode, .weather: return true
            case .location, .network, .permission, .time: return false
            }
        }
    }

    var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

@MainActor
@Observable
final class AwarenessLog {

    /// Most-recent-first, capped for the UI.
    private(set) var entries: [AwarenessLogEntry] = []

    private let cap = 200
    private let fileURL: URL?
    private let isoFormatter = ISO8601DateFormatter()

    init() {
        fileURL = Self.makeFileURL()
    }

    /// The on-disk log location, for the "Reveal in Finder" affordance.
    var logFileURL: URL? { fileURL }

    func record(_ category: AwarenessLogEntry.Category, _ summary: String, detail: String? = nil) {
        let entry = AwarenessLogEntry(date: Date(), category: category, summary: summary, detail: detail)
        entries.insert(entry, at: 0)
        if entries.count > cap { entries.removeLast(entries.count - cap) }
        appendToFile(entry)
        #if DEBUG
        print("[Awareness] \(entry.category.rawValue): \(summary)\(detail.map { " — \($0)" } ?? "")")
        #endif
    }

    func clear() {
        entries.removeAll()
        if let fileURL { try? "".write(to: fileURL, atomically: true, encoding: .utf8) }
    }

    // MARK: - File backing

    private func appendToFile(_ entry: AwarenessLogEntry) {
        guard let fileURL else { return }
        var line = "\(isoFormatter.string(from: entry.date))\t[\(entry.category.rawValue)]\t\(entry.summary)"
        if let detail = entry.detail { line += "\t\(detail)" }
        line += "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    private static func makeFileURL() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("BabelRobot", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("awareness.log")
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        return url
    }
}
