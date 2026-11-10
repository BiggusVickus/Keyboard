import Foundation
import KeyboardCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Builds the AI client picked in Settings.
enum AIClientFactory {
    static func make(_ settings: TaalhulpSettings, hasFullAccess: Bool) throws -> AIClient {
        if settings.aiProvider != .appleOnDevice, settings.aiProvider != .none, !hasFullAccess {
            throw AIError.notConfigured("Turn on Allow Full Access for Taalhulp (Settings → General → Keyboard → Keyboards) to use the AI helper.")
        }
        switch settings.aiProvider {
        case .none:
            throw AIError.notConfigured("Choose an AI helper in the Taalhulp app (Settings → AI helper).")
        case .claude:
            return ClaudeClient(apiKey: settings.claudeAPIKey, model: settings.claudeModel)
        case .local:
            guard let main = OpenAICompatibleClient(baseURLString: settings.localBaseURL, model: settings.localModel,
                                                    thinking: settings.localThinking) else {
                throw AIError.notConfigured("Check the local server URL in the Taalhulp app (Settings → AI helper).")
            }
            var candidates = [FallbackAIClient.Candidate(name: main.baseURL.host ?? "your main server", client: main)]
            // The backup (e.g. the Raspberry Pi) answers when the main server (the PC) is off.
            if !settings.localBackupBaseURL.trimmingCharacters(in: .whitespaces).isEmpty,
               let backup = OpenAICompatibleClient(baseURLString: settings.localBackupBaseURL,
                                                   model: settings.localBackupModel.isEmpty ? settings.localModel : settings.localBackupModel,
                                                   thinking: settings.localThinking) {
                candidates.append(.init(name: backup.baseURL.host ?? "your backup server", client: backup))
            }
            return FallbackAIClient(candidates)
        case .appleOnDevice:
            #if canImport(FoundationModels)
            return AppleIntelligenceClient()
            #else
            throw AIError.unavailable("Apple Intelligence needs a newer iOS.")
            #endif
        }
    }
}

#if canImport(FoundationModels)
/// Apple's on-device model (Apple Intelligence). Free and private, but it may refuse to run
/// inside a keyboard, and its Dutch and German are weaker than Claude's.
struct AppleIntelligenceClient: AIClient {
    func complete(_ request: AIRequest) async throws -> String {
        guard SystemLanguageModel.default.isAvailable else {
            throw AIError.unavailable("Apple Intelligence isn't available here (it may be off, still downloading, or not allowed in keyboards). Pick another AI helper in the Taalhulp app.")
        }
        var instructions = request.system
        if let schema = request.schema {
            instructions += "\n\nAnswer with only a JSON object (no Markdown, no other text) that follows this JSON Schema:\n\(schema)"
        }
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: request.prompt)
        return response.content
    }
}
#endif
