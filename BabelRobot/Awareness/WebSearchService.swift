//
//  WebSearchService.swift
//  BabelRobot
//
//  Lets the robot search the web to answer questions about current events and
//  facts it can't know offline. This does NOT make the LLM remote — it fetches
//  a few results, hands them to the local model as context (retrieval), and the
//  model answers from them. Keyless sources only, and every query is written to
//  the shared awareness log so searches can be followed.
//
//  Sources (no API key, no signup):
//   • DuckDuckGo Instant Answer — quick facts / definitions (JSON).
//   • Google News RSS           — current headlines for news-like queries (XML).
//

import Foundation
import Observation

/// One retrieved result.
struct WebResult: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let snippet: String?
    let url: String?
    let source: String
}

@MainActor
@Observable
final class WebSearchService {

    /// Opt-in. Off by default — the assistant is otherwise fully offline.
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.key) }
    }

    /// Max results handed to the model.
    var maxResults = 5

    /// Shared activity log (set to the awareness log so searches show there too).
    var log: AwarenessLog?

    private static let key = "websearch.enabled"

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.key)
    }

    // MARK: - Public entry point

    /// If enabled and the prompt looks like it benefits from fresh/external
    /// info, search the web and return a context block to prepend to the model
    /// prompt. Returns `nil` when search is off, not warranted, or found nothing.
    func contextBlock(for prompt: String) async -> String? {
        guard enabled else { return nil }
        let query = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldSearch(query) else { return nil }

        let results = await search(query)
        guard !results.isEmpty else { return nil }

        var lines = ["Web search results for \"\(query)\" (use these to answer; cite sources when useful):"]
        for (i, r) in results.enumerated() {
            var line = "\(i + 1). \(r.title)"
            if let s = r.snippet, !s.isEmpty { line += " — \(s)" }
            if let u = r.url { line += " (\(u))" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Search

    /// Run the appropriate keyless source(s) for `query` and merge results.
    func search(_ query: String) async -> [WebResult] {
        log?.record(.search, "Search: \"\(query)\"")
        async let instant = duckDuckGo(query)
        async let news = looksLikeNews(query) ? googleNews(query) : []
        var merged = (await news) + (await instant)
        if merged.count > maxResults { merged = Array(merged.prefix(maxResults)) }
        log?.record(.search, "Found \(merged.count) result(s) for \"\(query)\"")
        return merged
    }

    // MARK: - DuckDuckGo Instant Answer (JSON)

    private func duckDuckGo(_ query: String) async -> [WebResult] {
        var comps = URLComponents(string: "https://api.duckduckgo.com/")
        comps?.queryItems = [
            .init(name: "q", value: query),
            .init(name: "format", value: "json"),
            .init(name: "no_html", value: "1"),
            .init(name: "no_redirect", value: "1"),
        ]
        guard let url = comps?.url else { return [] }
        log?.record(.search, "GET api.duckduckgo.com", detail: url.absoluteString)
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let r = try JSONDecoder().decode(DDGResponse.self, from: data)
            var out: [WebResult] = []
            if let abstract = r.AbstractText, !abstract.isEmpty {
                out.append(WebResult(title: r.Heading ?? query, snippet: abstract,
                                     url: r.AbstractURL, source: "DuckDuckGo"))
            }
            for topic in r.RelatedTopics ?? [] {
                guard let text = topic.Text, !text.isEmpty else { continue }
                out.append(WebResult(title: text, snippet: nil,
                                     url: topic.FirstURL, source: "DuckDuckGo"))
                if out.count >= maxResults { break }
            }
            return out
        } catch {
            log?.record(.search, "DuckDuckGo failed", detail: error.localizedDescription)
            return []
        }
    }

    private struct DDGResponse: Decodable {
        let Heading: String?
        let AbstractText: String?
        let AbstractURL: String?
        let RelatedTopics: [Topic]?
        struct Topic: Decodable {
            let Text: String?
            let FirstURL: String?
        }
    }

    // MARK: - Google News RSS (XML)

    private func googleNews(_ query: String) async -> [WebResult] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://news.google.com/rss/search?q=\(q)") else { return [] }
        log?.record(.search, "GET news.google.com/rss", detail: url.absoluteString)
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let items = RSSParser.parse(data, limit: maxResults)
            return items.map { WebResult(title: $0.title, snippet: $0.date,
                                         url: $0.link, source: "Google News") }
        } catch {
            log?.record(.search, "News failed", detail: error.localizedDescription)
            return []
        }
    }

    // MARK: - Heuristics

    /// Only search when the prompt plausibly needs external/fresh info, so plain
    /// chat and self-contained requests stay fully local.
    private func shouldSearch(_ query: String) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 2 else { return false }
        let t = query.lowercased()
        if t.contains("?") { return true }
        let triggers = [
            // recency / news
            "news", "latest", "today", "now", "current", "recent", "this week", "this year",
            "notícia", "noticia", "hoje", "agora", "atual", "última", "ultima", "recente",
            "noticias", "notícias",
            // lookup-ish
            "who is", "what is", "when", "where", "price", "weather", "score", "stock",
            "quem é", "quem e", "o que é", "o que e", "quando", "onde", "preço", "preco",
            "cotação", "cotacao", "resultado", "search", "pesquis", "procura", "busca",
        ]
        return triggers.contains { t.contains($0) }
    }

    private func looksLikeNews(_ query: String) -> Bool {
        let t = query.lowercased()
        let cues = ["news", "headline", "today", "latest", "breaking",
                    "notícia", "noticia", "notícias", "noticias", "hoje", "manchete", "última"]
        return cues.contains { t.contains($0) }
    }
}

// MARK: - Minimal RSS parser

private enum RSSParser {
    struct Item { let title: String; let link: String?; let date: String? }

    static func parse(_ data: Data, limit: Int) -> [Item] {
        let delegate = Delegate(limit: limit)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [Item] = []
        private let limit: Int
        private var inItem = false
        private var current = ""
        private var title = ""
        private var link = ""
        private var date = ""

        init(limit: Int) { self.limit = limit }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            if name == "item" { inItem = true; title = ""; link = ""; date = "" }
            current = name
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard inItem else { return }
            switch current {
            case "title": title += string
            case "link": link += string
            case "pubDate": date += string
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            if name == "item" {
                inItem = false
                let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, items.count < limit {
                    items.append(Item(
                        title: t,
                        link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                        date: date.isEmpty ? nil : String(date.prefix(16))
                    ))
                }
                if items.count >= limit { parser.abortParsing() }
            }
            current = ""
        }
    }
}
