import SwiftUI
import KeyboardCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppSettingsModel

    var body: some View {
        NavigationStack {
            Form {
                languagesSection
                typingSection
                TextExpansionsSection()
                TouchMapSection()
                grammarSection
                aiSection
                translatorSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Languages

    private var languagesSection: some View {
        Section {
            ForEach(KeyboardLanguage.allCases) { language in
                Toggle(language.displayName, isOn: enabled(language))
            }
        } header: {
            Text("Languages")
        } footer: {
            Text("The language key on the keyboard switches between the languages that are on.")
        }
    }

    private func enabled(_ language: KeyboardLanguage) -> Binding<Bool> {
        Binding(
            get: { model.settings.enabledLanguages.contains(language) },
            set: { isOn in
                var languages = model.settings.enabledLanguages
                if isOn {
                    if !languages.contains(language) { languages.append(language) }
                } else {
                    // Always keep at least one language.
                    guard languages.count > 1 else { return }
                    languages.removeAll { $0 == language }
                }
                model.settings.enabledLanguages = languages
                if !languages.contains(model.settings.currentLanguage) {
                    model.settings.currentLanguage = languages[0]
                }
            }
        )
    }

    // MARK: - Typing

    private var typingSection: some View {
        Section {
            Picker("Autocorrect", selection: $model.settings.autocorrect) {
                ForEach(AutocorrectMode.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Auto-capitalisation", isOn: $model.settings.autoCapitalize)
            Toggle("Haptic feedback", isOn: $model.settings.hapticFeedback)
            Toggle("Key sounds", isOn: $model.settings.keySounds)
            Toggle("Show text when moving the cursor", isOn: $model.settings.trackpadShowsText)
        } header: {
            Text("Typing")
        } footer: {
            Text(model.settings.autocorrect.detail + " Key sounds and haptics need Full Access; sounds follow the silent switch, like Apple's keyboard. Hold the space bar to move the cursor: with “Show text” on, the keyboard shows the text with a floating cursor; off, the keyboard goes blank like Apple's and you follow the cursor in the text box.")
        }
    }

    // MARK: - Grammar

    private var grammarSection: some View {
        Section {
            Toggle("Check grammar", isOn: $model.settings.grammarCheckEnabled)
            Picker("Level", selection: $model.settings.grammarLevel) {
                ForEach(GrammarLevel.allCases) { Text($0.title).tag($0) }
            }
            .disabled(!model.settings.grammarCheckEnabled)
            Toggle("Keep a learning log", isOn: $model.settings.keepLearningLog)
            LabeledContent("Your LanguageTool server") {
                TextField("Optional", text: $model.settings.languageToolURL)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            LabeledContent("Backup server", value: "api.languagetool.org")
        } header: {
            Text("Grammar")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.settings.grammarLevel.detail)
                Text(model.settings.ownLanguageToolURL == nil
                     ? "Checks use the free public LanguageTool server. Add your own server (e.g. http://192.168.1.20:8010/v2/check) to use it first."
                     : "Checks go to your server first. If it doesn't answer within 3 seconds, the free public server is used instead.")
                Text("🔴 Error: this is wrong.   🔵 Tip: optional, what you wrote is also correct.")
            }
        }
    }

    // MARK: - AI

    private var aiSection: some View {
        Section {
            Picker("AI helper", selection: $model.settings.aiProvider) {
                ForEach(AIProviderKind.allCases) { Text($0.title).tag($0) }
            }

            switch model.settings.aiProvider {
            case .claude:
                Picker("Model", selection: claudeModelSelection) {
                    ForEach(ClaudeModelOption.all) { option in
                        VStack(alignment: .leading) {
                            Text(option.name)
                            Text(option.note).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(option.id)
                    }
                    Text("Custom…").tag(Self.customModelTag)
                }
                .pickerStyle(.navigationLink)

                if claudeModelSelection.wrappedValue == Self.customModelTag {
                    TextField("Model ID, e.g. claude-sonnet-5-5", text: $model.settings.claudeModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                SecureField("API key (sk-ant-…)", text: $model.settings.claudeAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

            case .local:
                urlField("Main server (PC)", text: $model.settings.localBaseURL, prompt: "http://192.168.1.20:11434/v1")
                Picker("Model", selection: $model.settings.localModel) {
                    if model.settings.localModelChoices.isEmpty { Text("None yet").tag("") }
                    ForEach(model.settings.localModelChoices, id: \.self) { Text($0).tag($0) }
                }
                urlField("Backup server (Pi)", text: $model.settings.localBackupBaseURL, prompt: "Optional")
                if !model.settings.localBackupBaseURL.trimmingCharacters(in: .whitespaces).isEmpty {
                    Picker("Backup model", selection: $model.settings.localBackupModel) {
                        Text("Same as main").tag("")
                        ForEach(model.settings.localModelChoices, id: \.self) { Text($0).tag($0) }
                    }
                }
                NavigationLink {
                    LocalModelsView()
                } label: {
                    LabeledContent("Models", value: "\(model.settings.localModels.count)")
                }
                Toggle("Let the model think", isOn: $model.settings.localThinking)

            case .none, .appleOnDevice:
                EmptyView()
            }
        } header: {
            Text("AI helper")
        } footer: {
            Text(aiFooter)
        }
    }

    // MARK: - Translator

    private var translatorSection: some View {
        Section {
            urlField("Main server (PC)", text: $model.settings.translatorURL, prompt: "http://192.168.1.20:8020")
            urlField("Backup server (Pi)", text: $model.settings.translatorBackupURL, prompt: "http://192.168.1.30:8020")
        } header: {
            Text("Translator")
        } footer: {
            Text(model.settings.translatorURLs.isEmpty
                 ? "Optional: your own Dutch ↔ English translation models (Tools/server/translate_server.py). Without them, the AI helper translates."
                 : "Dutch ↔ English goes to the main server first; if it doesn't answer within 3 seconds, the backup. German, or both servers off: the AI helper translates.")
        }
    }

    private func urlField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        LabeledContent(title) {
            TextField(prompt, text: text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
    }

    private static let customModelTag = "__custom__"

    /// Shows "Custom…" in the picker whenever the stored model ID isn't one of the presets.
    private var claudeModelSelection: Binding<String> {
        Binding(
            get: {
                let id = model.settings.claudeModel
                let isPreset = ClaudeModelOption.all.contains(where: { $0.id == id })
                return isPreset ? id : Self.customModelTag
            },
            set: { newValue in
                if newValue == Self.customModelTag {
                    if ClaudeModelOption.all.contains(where: { $0.id == model.settings.claudeModel }) {
                        model.settings.claudeModel = ""
                    }
                } else {
                    model.settings.claudeModel = newValue
                }
            }
        )
    }

    private var aiFooter: LocalizedStringKey {
        switch model.settings.aiProvider {
        case .none:
            "Only LanguageTool and the built-in dictionaries are used. Free, but no explanations for every mistake and no \"Is this correct?\" check."
        case .claude:
            "Used only when you tap Explain, Is this correct? or Improve. Create an API key at **platform.claude.com** and set a monthly spend limit there. A Claude.ai subscription does not include API use."
        case .local:
            "Any OpenAI-compatible server works, e.g. **Ollama** or **LM Studio**. Start Ollama with `OLLAMA_HOST=0.0.0.0` and use the computer's IP, e.g. `http://192.168.1.20:11434/v1`. The main server is asked first; if it doesn't answer within 3 seconds (PC off), the backup is used. Away from home, use Tailscale addresses. Free, but quality depends on the model; expect more mistakes than Claude, and slow answers from a Raspberry Pi. \"Let the model think\" makes reasoning models (Qwen) think first: on a big model that takes minutes instead of seconds, so leave it off unless answers are often wrong."
        case .appleOnDevice:
            "Experimental: uses Apple Intelligence on your iPhone. Free and private, but it may not work inside a keyboard, and its Dutch and German grammar is weaker."
        }
    }
}
