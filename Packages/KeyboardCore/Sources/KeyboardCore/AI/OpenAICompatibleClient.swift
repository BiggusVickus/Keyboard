import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Talks to a local server with an OpenAI-style `/chat/completions` endpoint,
/// such as Ollama or LM Studio on your Mac.
public struct OpenAICompatibleClient: AIClient {
    public let baseURL: URL
    public let model: String
    /// Let reasoning models (Qwen, DeepSeek) think before answering. Off: they answer straight
    /// away, many times faster; on a 27B model, thinking can take minutes and use up the whole
    /// answer length before the answer starts.
    public let thinking: Bool
    private let http: HTTPClient

    /// Answer length allowed while thinking: the thinking counts too.
    static let thinkingMaxTokens = 16_000

    /// Returns nil when `baseURLString` isn't a usable URL.
    public init?(baseURLString: String, model: String, thinking: Bool = false, http: HTTPClient = URLSessionHTTPClient()) {
        // "http:/host" (one slash) parses as a URL without a host: reject it so Settings says so.
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme, scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        self.baseURL = url
        self.model = model.trimmingCharacters(in: .whitespaces)
        self.thinking = thinking
        self.http = http
    }

    public func complete(_ request: AIRequest) async throws -> String {
        guard !model.isEmpty else {
            throw AIError.notConfigured("Enter the local model name in the Taalhulp app (Settings → AI helper).")
        }
        var (data, response) = try await send(try makeRequest(request))
        // "reasoning_effort: none" turns thinking off in Ollama; a server that doesn't know the
        // field may reject it. Then ask again without it.
        if response.statusCode == 400, !thinking,
           String(data: data, encoding: .utf8)?.localizedCaseInsensitiveContains("reasoning") == true {
            (data, response) = try await send(try makeRequest(request, turnOffThinking: false))
        }
        guard response.statusCode == 200 else {
            throw AIError.http(status: response.statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.parse(data)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await http.send(request)
        } catch let error as URLError {
            throw AIError.unavailable("Can't reach your local AI server at \(baseURL.host ?? baseURL.absoluteString): \(Self.describe(error))")
        }
    }

    /// What went wrong, in words that point to the fix (shown in the keyboard).
    static func describe(_ error: URLError) -> String {
        switch error.code {
        case .timedOut: "no answer (timed out). Is the computer on, and Tailscale on on the phone?"
        case .cannotConnectToHost: "the computer refused the connection. Is the server running, and listening on 0.0.0.0?"
        case .cannotFindHost, .dnsLookupFailed: "the address wasn't found. Check the server URL in Settings."
        case .notConnectedToInternet: "the phone has no network connection."
        case .appTransportSecurityRequiresSecureConnection: "iOS blocked plain http to this address (App Transport Security)."
        case .secureConnectionFailed, .serverCertificateUntrusted: "the https connection failed. Use http:// for your own server."
        default: "network error \(error.code.rawValue). Is the computer on and the server running?"
        }
    }

    private struct ModelList: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }

    /// The models installed on the server (`GET /models`), sorted by name.
    public func listModels() async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 5
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await http.send(request)
        } catch let error as URLError {
            throw AIError.unavailable("Can't reach \(baseURL.host ?? baseURL.absoluteString): \(Self.describe(error))")
        }
        guard response.statusCode == 200 else {
            throw AIError.http(status: response.statusCode, message: "The server answered with error \(response.statusCode). Does the URL end in /v1?")
        }
        guard let list = try? JSONDecoder().decode(ModelList.self, from: data) else { throw AIError.invalidResponse }
        return list.data.map(\.id).sorted()
    }

    /// Quick check that the server is up (`GET /models`), so a switched-off PC is skipped in
    /// seconds instead of waiting out the long answer timeout.
    public func isReachable(timeout: TimeInterval = 2.5) async -> Bool {
        await reachabilityProblem(timeout: timeout) == nil
    }

    /// Nil when the server answers the quick check, else why not (for the error message).
    public func reachabilityProblem(timeout: TimeInterval = 2.5) async -> String? {
        var probe = URLRequest(url: baseURL.appendingPathComponent("models"))
        probe.timeoutInterval = timeout
        do {
            let (_, response) = try await http.send(probe)
            return response.statusCode == 200 ? nil : "it answered with error \(response.statusCode). Is the URL right (ending in /v1)?"
        } catch let error as URLError {
            return Self.describe(error)
        } catch {
            return "\(error.localizedDescription)"
        }
    }

    func makeRequest(_ request: AIRequest, turnOffThinking: Bool = true) throws -> URLRequest {
        var system = request.system
        if let schema = request.schema {
            // Local servers don't all support structured output, so ask for the JSON in words.
            system += "\n\nAnswer with only a JSON object (no Markdown, no other text) that follows this JSON Schema:\n\(schema)"
        }
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": request.prompt],
            ],
            "temperature": 0.2,
            "max_tokens": thinking ? max(request.maxTokens, Self.thinkingMaxTokens) : request.maxTokens,
            "stream": false,
        ]
        if !thinking, turnOffThinking {
            body["reasoning_effort"] = "none"
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        // Local models can be slow, especially the first request after loading (up to a minute
        // for a 27B model), and much slower while thinking.
        urlRequest.timeoutInterval = thinking ? 600 : 180
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                /// Ollama puts the thinking here, apart from the answer.
                let reasoning: String?
            }
            let message: Message
            let finish_reason: String?
        }
        let choices: [Choice]
    }

    static func parse(_ data: Data) throws -> String {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let choice = response.choices.first
        else { throw AIError.invalidResponse }
        let raw = choice.message.content ?? ""
        let text = AIJSON.stripThinking(raw)
        if text.isEmpty {
            let thought = !(choice.message.reasoning ?? "").isEmpty || raw.contains("<think>")
            if choice.finish_reason == "length", thought {
                throw AIError.unavailable("The model used up the whole answer length thinking. Turn off \"Let the model think\" in the Taalhulp app (Settings → AI helper).")
            }
            throw choice.finish_reason == "length" ? AIError.truncated : AIError.emptyResponse
        }
        return text
    }
}
