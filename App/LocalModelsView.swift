import SwiftUI
import KeyboardCore

/// Settings → AI helper → Models: the models offered in the Model dropdowns.
/// Type a name (as `ollama list` shows it), or fetch what is installed on your servers.
struct LocalModelsView: View {
    @EnvironmentObject private var model: AppSettingsModel
    @State private var newName = ""
    @State private var fetching = false
    @State private var fetchMessage: String?

    var body: some View {
        Form {
            Section {
                ForEach(model.settings.localModels, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        if name == model.settings.localModel {
                            Text("Main").font(.caption).foregroundStyle(.secondary)
                        } else if name == model.settings.localBackupModel {
                            Text("Backup").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: remove)
                .onMove { model.settings.localModels.move(fromOffsets: $0, toOffset: $1) }

                HStack {
                    TextField("Add a model, e.g. qwen3.5:9b", text: $newName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addTyped)
                    Button("Add", action: addTyped)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Swipe left to remove. The name must match `ollama list` on the server exactly.")
            }

            Section {
                Button {
                    Task { await fetchFromServers() }
                } label: {
                    HStack {
                        Text("Add the models on my servers")
                        if fetching { Spacer(); ProgressView() }
                    }
                }
                .disabled(fetching)
            } footer: {
                if let fetchMessage { Text(fetchMessage) }
            }
        }
        .navigationTitle("Models")
        .toolbar { EditButton() }
    }

    private func addTyped() {
        add([newName])
        newName = ""
    }

    private func add(_ names: [String]) {
        var list = model.settings.localModels
        for name in names.map({ $0.trimmingCharacters(in: .whitespaces) }) where !name.isEmpty && !list.contains(name) {
            list.append(name)
        }
        model.settings.localModels = list
        if model.settings.localModel.isEmpty, let first = list.first {
            model.settings.localModel = first
        }
    }

    private func remove(at offsets: IndexSet) {
        let removed = offsets.map { model.settings.localModels[$0] }
        model.settings.localModels.remove(atOffsets: offsets)
        // Don't leave a removed model selected (it would still show in the dropdown).
        if removed.contains(model.settings.localModel) {
            model.settings.localModel = model.settings.localModels.first ?? ""
        }
        if removed.contains(model.settings.localBackupModel) {
            model.settings.localBackupModel = ""
        }
    }

    /// Asks the main and backup server which models they have (GET /v1/models) and adds them.
    private func fetchFromServers() async {
        fetching = true
        defer { fetching = false }
        let urls = [model.settings.localBaseURL, model.settings.localBackupBaseURL]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var found: [String] = []
        var problems: [String] = []
        for url in urls {
            guard let client = OpenAICompatibleClient(baseURLString: url, model: "") else {
                problems.append("\(url) isn't a valid URL.")
                continue
            }
            do {
                found += try await client.listModels()
            } catch {
                problems.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
        let before = Set(model.settings.localModels)
        add(found)
        let added = model.settings.localModels.filter { !before.contains($0) }.count
        fetchMessage = ([urls.isEmpty ? "Enter a server URL first." : "Found \(Set(found).count), added \(added) new."] + problems)
            .joined(separator: "\n")
    }
}
