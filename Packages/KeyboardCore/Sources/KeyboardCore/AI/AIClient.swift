import Foundation

/// How hard the model should think. Low is faster and cheaper; medium is more careful.
public enum AIEffort: String, Sendable {
    case low
    case medium
}

/// One question for the AI.
public struct AIRequest: Sendable {
    public var system: String
    public var prompt: String
    /// A JSON Schema (as JSON text) the answer must follow, or nil for a plain-text answer.
    public var schema: String?
    public var maxTokens: Int
    public var effort: AIEffort

    public init(system: String, prompt: String, schema: String? = nil, maxTokens: Int = 2000, effort: AIEffort = .low) {
        self.system = system
        self.prompt = prompt
        self.schema = schema
        self.maxTokens = maxTokens
        self.effort = effort
    }
}

/// Anything that can answer an `AIRequest`: Claude, a local server, Apple's on-device model.
public protocol AIClient: Sendable {
    /// Returns the answer text (JSON text when the request has a schema).
    func complete(_ request: AIRequest) async throws -> String
}

public enum AIError: Error, Equatable, LocalizedError {
    /// Something is missing in Settings; the text says what.
    case notConfigured(String)
    case http(status: Int, message: String)
    /// The model declined to answer.
    case refused
    /// The answer was cut off before it was complete.
    case truncated
    case emptyResponse
    case invalidResponse
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let what): what
        case .http(401, _): "The API key was not accepted. Check it in the Taalhulp app."
        case .http(429, _): "Too many requests right now. Try again in a minute."
        case .http(let status, let message): message.isEmpty ? "The AI returned error \(status)." : message
        case .refused: "The AI declined to answer this one."
        case .truncated: "The answer was cut off. Try a shorter text."
        case .emptyResponse: "The AI gave an empty answer."
        case .invalidResponse: "The AI's answer couldn't be read."
        case .unavailable(let reason): reason
        }
    }
}

/// Helpers for reading JSON out of model answers.
public enum AIJSON {
    /// Finds the JSON object in a model's answer, ignoring ```json fences and chatter around it.
    public static func extractObject(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return Data(text[start...end].utf8)
    }

    /// Removes the <think>…</think> block that reasoning models (Qwen, DeepSeek) put before their answer.
    public static func stripThinking(_ text: String) -> String {
        var result = text
        while let open = result.range(of: "<think>"),
              let close = result.range(of: "</think>", range: open.upperBound..<result.endIndex) {
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let data = extractObject(from: stripThinking(text)) else { throw AIError.invalidResponse }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIError.invalidResponse
        }
    }
}
