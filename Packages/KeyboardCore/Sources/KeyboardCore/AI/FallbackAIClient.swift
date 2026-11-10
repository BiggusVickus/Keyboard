import Foundation

/// Tries several AI servers in order, e.g. Ollama on the PC first and on the Raspberry Pi second.
/// A server that doesn't answer a quick check is skipped; one that fails while answering
/// hands the request to the next one.
public struct FallbackAIClient: AIClient {
    public struct Candidate: Sendable {
        public let name: String
        public let client: AIClient
        public let isReachable: @Sendable () async -> Bool

        public init(name: String, client: AIClient, isReachable: @escaping @Sendable () async -> Bool) {
            self.name = name
            self.client = client
            self.isReachable = isReachable
        }

        public init(name: String, client: OpenAICompatibleClient) {
            self.init(name: name, client: client, isReachable: { await client.isReachable() })
        }
    }

    public let candidates: [Candidate]

    public init(_ candidates: [Candidate]) {
        self.candidates = candidates
    }

    public func complete(_ request: AIRequest) async throws -> String {
        var firstError: Error?
        var skipped: [String] = []
        for candidate in candidates {
            try Task.checkCancellation()
            guard await candidate.isReachable() else {
                skipped.append(candidate.name)
                continue
            }
            do {
                return try await candidate.client.complete(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A wrong answer format won't get better elsewhere, but a broken or busy server might.
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
        let names = skipped.joined(separator: " or ")
        throw AIError.unavailable("Can't reach \(names.isEmpty ? "your AI server" : names). Are they switched on, and is the phone on the same network (or Tailscale)?")
    }
}
