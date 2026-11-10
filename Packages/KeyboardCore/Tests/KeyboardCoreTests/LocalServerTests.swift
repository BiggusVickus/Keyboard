import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import KeyboardCore

/// Answers by host + path; hosts not listed behave like a switched-off computer.
private final class RoutedHTTPClient: HTTPClient, @unchecked Sendable {
    var routes: [String: (Int, String)] = [:]
    private(set) var requested: [String] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = "\(request.url!.host!)\(request.url!.path)"
        requested.append(key)
        guard let (status, body) = routes[key] else { throw URLError(.timedOut) }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private let chatReply = #"{"choices": [{"message": {"content": "%@"}, "finish_reason": "stop"}]}"#

final class LocalServerTests: XCTestCase {
    private func candidates(_ http: RoutedHTTPClient) -> FallbackAIClient {
        let pc = OpenAICompatibleClient(baseURLString: "http://pc:11434/v1", model: "qwen3:14b", http: http)!
        let pi = OpenAICompatibleClient(baseURLString: "http://pi:11434/v1", model: "qwen3:1.7b", http: http)!
        return FallbackAIClient([.init(name: "pc", client: pc), .init(name: "pi", client: pi)])
    }

    func testPCIsUsedWhenOn() async throws {
        let http = RoutedHTTPClient()
        http.routes = ["pc/v1/models": (200, "{}"), "pc/v1/chat/completions": (200, String(format: chatReply, "from pc")),
                       "pi/v1/models": (200, "{}"), "pi/v1/chat/completions": (200, String(format: chatReply, "from pi"))]
        let answer = try await candidates(http).complete(AIRequest(system: "", prompt: "hi"))
        XCTAssertEqual(answer, "from pc")
        XCTAssertFalse(http.requested.contains { $0.hasPrefix("pi") })
    }

    func testPiTakesOverWhenPCIsOff() async throws {
        let http = RoutedHTTPClient()
        http.routes = ["pi/v1/models": (200, "{}"), "pi/v1/chat/completions": (200, String(format: chatReply, "from pi"))]
        let answer = try await candidates(http).complete(AIRequest(system: "", prompt: "hi"))
        XCTAssertEqual(answer, "from pi")
    }

    func testPiTakesOverWhenPCFails() async throws {
        let http = RoutedHTTPClient()
        http.routes = ["pc/v1/models": (200, "{}"), "pc/v1/chat/completions": (404, "model not found"),
                       "pi/v1/models": (200, "{}"), "pi/v1/chat/completions": (200, String(format: chatReply, "from pi"))]
        let answer = try await candidates(http).complete(AIRequest(system: "", prompt: "hi"))
        XCTAssertEqual(answer, "from pi")
    }

    func testBothOffSaysSo() async {
        do {
            _ = try await candidates(RoutedHTTPClient()).complete(AIRequest(system: "", prompt: "hi"))
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue((error as? AIError)?.errorDescription?.contains("pc or pi") == true, "\(error)")
        }
    }

    // MARK: - Translation servers

    private let health = #"{"ok": true, "pairs": ["nl-en", "en-nl"], "device": "cpu"}"#

    private func service(_ http: RoutedHTTPClient, assistantReply: String? = nil) -> TranslationService {
        let servers = ["http://pc:8020", "http://pi:8020"].compactMap { TranslationServerClient(urlString: $0, http: http) }
        var assistant: Assistant?
        if let assistantReply {
            http.routes["ai/v1/chat/completions"] = (200, String(format: chatReply, assistantReply))
            assistant = Assistant(client: OpenAICompatibleClient(baseURLString: "http://ai/v1", model: "m", http: http)!)
        }
        return TranslationService(servers: servers, assistant: assistant)
    }

    func testTranslationServerFallsBackToPi() async throws {
        let http = RoutedHTTPClient()
        http.routes = ["pi/health": (200, health), "pi/translate": (200, #"{"translation": "I am hungry."}"#)]
        let result = try await service(http).translate("Ik heb honger.", from: .dutch, to: .english)
        XCTAssertEqual(result, Translation(translation: "I am hungry.", notes: ""))
    }

    func testGermanGoesToTheAI() async throws {
        let http = RoutedHTTPClient()
        http.routes = ["pc/health": (200, health), "pc/translate": (200, #"{"translation": "wrong"}"#)]
        let result = try await service(http, assistantReply: #"{\"translation\": \"Ich habe Hunger.\", \"notes\": \"\"}"#)
            .translate("Ik heb honger.", from: .dutch, to: .german)
        XCTAssertEqual(result.translation, "Ich habe Hunger.")
        XCTAssertFalse(http.requested.contains("pc/translate"))
    }

    func testServersOffWithoutAI() async {
        do {
            _ = try await service(RoutedHTTPClient()).translate("Hoi", from: .dutch, to: .english)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue((error as? AIError)?.errorDescription?.contains("translation server") == true, "\(error)")
        }
    }

    func testTranslationRequestShape() async throws {
        let http = FakeHTTPClient(json: #"{"translation": "Hallo"}"#)
        let client = try XCTUnwrap(TranslationServerClient(urlString: "http://pi:8020", http: http))
        _ = try await client.translate("Hello", from: .english, to: .dutch)
        XCTAssertEqual(http.lastRequest?.url?.absoluteString, "http://pi:8020/translate")
        XCTAssertEqual(http.lastBodyJSON?["source"] as? String, "en")
        XCTAssertEqual(http.lastBodyJSON?["target"] as? String, "nl")
    }

    // MARK: - Settings

    func testOldSettingsGetEmptyBackupServers() throws {
        let old = #"{"localBaseURL": "http://pc:11434/v1", "localModel": "gemma3:12b"}"#
        let settings = try JSONDecoder().decode(TaalhulpSettings.self, from: Data(old.utf8))
        XCTAssertEqual(settings.localModel, "gemma3:12b")
        XCTAssertEqual(settings.localBackupBaseURL, "")
        XCTAssertEqual(settings.translatorURLs, [])
    }

    func testTranslatorURLsSkipEmpty() {
        var settings = TaalhulpSettings()
        settings.translatorBackupURL = " http://pi:8020 "
        XCTAssertEqual(settings.translatorURLs, ["http://pi:8020"])
    }

    // MARK: - Backup across reinstalls

    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "Backup-\(UUID())")! }

    func testBackupComesBackInAFreshContainer() throws {
        let old = freshDefaults()
        var settings = TaalhulpSettings()
        settings.textExpansions = [TextExpansion(shortcut: "mvg", expansion: "Met vriendelijke groet,")]
        settings.touchModel = .custom
        SettingsStore(defaults: old).save(settings)
        var profile = TouchProfile()
        profile.add(TouchSample(character: "e", x: 2, y: 3))
        TouchProfileStore(defaults: old).save(profile)
        LearnedWordsStore(defaults: old).learn("Taalhulp", language: .dutch)
        let backup = try XCTUnwrap(SettingsBackup.snapshot(of: old))

        // Reinstall: an empty container, where the keyboard already saved default settings.
        let new = freshDefaults()
        SettingsStore(defaults: new).save(TaalhulpSettings())
        let restored = SettingsBackup.restoreIfFresh(from: backup, into: new)

        XCTAssertEqual(Set(restored), [SettingsStore.key, TouchProfileStore.key, LearnedWordsStore.key])
        XCTAssertEqual(SettingsStore(defaults: new).load(), settings)
        XCTAssertEqual(TouchProfileStore(defaults: new).load(), profile)
        XCTAssertEqual(LearnedWordsStore(defaults: new).load()[.dutch], ["taalhulp"])
    }

    func testBackupDoesNotOverwriteLaterChanges() throws {
        let defaults = freshDefaults()
        XCTAssertEqual(SettingsBackup.restoreIfFresh(from: nil, into: defaults), [])
        var settings = TaalhulpSettings()
        settings.keySounds = false
        SettingsStore(defaults: defaults).save(settings)
        let olderBackup = try XCTUnwrap(SettingsBackup.snapshot(of: freshDefaultsWith(TaalhulpSettings())))

        // Next launch: the container is ours already, so the (older) backup is not put back.
        XCTAssertEqual(SettingsBackup.restoreIfFresh(from: olderBackup, into: defaults), [])
        XCTAssertFalse(SettingsStore(defaults: defaults).load().keySounds)
    }

    private func freshDefaultsWith(_ settings: TaalhulpSettings) -> UserDefaults {
        let defaults = freshDefaults()
        SettingsStore(defaults: defaults).save(settings)
        return defaults
    }
}
