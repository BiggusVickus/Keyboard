import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Talks to your own translation server (Tools/server/translate_server.py), which runs the
/// trained Dutch ↔ English models on the PC (GPU) or the Raspberry Pi (CPU).
///
///     GET  /health     → {"ok": true, "pairs": ["nl-en", "en-nl"], "device": "cuda"}
///     POST /translate  {"text": "…", "source": "nl", "target": "en"} → {"translation": "…"}
public struct TranslationServerClient: Sendable {
    public let baseURL: URL
    private let http: HTTPClient

    public init?(urlString: String, http: HTTPClient = URLSessionHTTPClient()) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme, scheme == "http" || scheme == "https"
        else { return nil }
        self.baseURL = url
        self.http = http
    }

    private struct Health: Decodable {
        let pairs: [String]
    }

    /// The language pairs the server offers ("nl-en"), or nil when it doesn't answer quickly.
    public func pairs(timeout: TimeInterval = 2.5) async -> Set<String>? {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = timeout
        guard let (data, response) = try? await http.send(request), response.statusCode == 200,
              let health = try? JSONDecoder().decode(Health.self, from: data)
        else { return nil }
        return Set(health.pairs)
    }

    private struct Answer: Decodable {
        let translation: String
    }

    public func translate(_ text: String, from source: KeyboardLanguage, to target: KeyboardLanguage) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("translate"))
        request.httpMethod = "POST"
        // The Pi needs a few seconds for a long paragraph.
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text, "source": source.rawValue, "target": target.rawValue,
        ])
        let (data, response) = try await http.send(request)
        guard response.statusCode == 200 else {
            throw AIError.http(status: response.statusCode, message: "Translation server error \(response.statusCode).")
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { throw AIError.invalidResponse }
        let translation = answer.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        if translation.isEmpty { throw AIError.emptyResponse }
        return translation
    }
}

/// Picks who translates: your translation servers in order (for the pairs they know), then the
/// AI helper (other languages, or when the servers are off).
public struct TranslationService: Sendable {
    public let servers: [TranslationServerClient]
    /// Nil when no AI helper is set up; `assistantError` then says why.
    public let assistant: Assistant?
    public let assistantError: Error?

    public init(servers: [TranslationServerClient], assistant: Assistant?, assistantError: Error? = nil) {
        self.servers = servers
        self.assistant = assistant
        self.assistantError = assistantError
    }

    public func translate(_ text: String, from source: KeyboardLanguage, to target: KeyboardLanguage) async throws -> Translation {
        let pair = "\(source.rawValue)-\(target.rawValue)"
        for server in servers {
            try Task.checkCancellation()
            guard let pairs = await server.pairs(), pairs.contains(pair) else { continue }
            if let translation = try? await server.translate(text, from: source, to: target) {
                return Translation(translation: translation, notes: "")
            }
        }
        try Task.checkCancellation()
        if let assistant {
            return try await assistant.translate(text, from: source, to: target)
        }
        if !servers.isEmpty, source.isDutchOrEnglish, target.isDutchOrEnglish {
            throw AIError.unavailable("Can't reach your translation server. Is the PC or the Pi on, and is the phone on the same network?")
        }
        throw assistantError ?? AIError.notConfigured("Set up a translation server or an AI helper in the Taalhulp app.")
    }
}

extension KeyboardLanguage {
    var isDutchOrEnglish: Bool { self == .dutch || self == .english }
}
