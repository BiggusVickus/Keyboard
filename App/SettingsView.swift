import SwiftUI
import KeyboardCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppSettingsModel

    var body: some View {
        NavigationStack {
            Form {
                languagesSection
                typingSection
                grammarSection
                aiSection
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
        } header: {
            Text("Typing")
        } footer: {
            Text(model.settings.autocorrect.detail)
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
            LabeledContent("LanguageTool server") {
                TextField("URL", text: $model.settings.languageToolURL)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
        } header: {
            Text("Grammar")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.settings.grammarLevel.detail)
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
                TextField("Server URL", text: $model.settings.localBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Model name", text: $model.settings.localModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

            case .none, .appleOnDevice:
                EmptyView()
            }
        } header: {
            Text("AI helper")
        } footer: {
            Text(aiFooter)
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
            "Any OpenAI-compatible server works, e.g. **Ollama** or **LM Studio** on your Mac. For Ollama, start it with `OLLAMA_HOST=0.0.0.0 ollama serve` and use your Mac's IP, e.g. `http://192.168.1.20:11434/v1`. Away from home, use Tailscale and the Mac's Tailscale address. Free, but quality depends on the model; expect more mistakes than Claude."
        case .appleOnDevice:
            "Experimental: uses Apple Intelligence on your iPhone. Free and private, but it may not work inside a keyboard, and its Dutch and German grammar is weaker."
        }
    }
}
