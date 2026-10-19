import SwiftUI
import KeyboardCore

/// Settings → Text expansions: shortcuts that turn into longer text while typing.
struct TextExpansionsSection: View {
    @EnvironmentObject private var model: AppSettingsModel

    var body: some View {
        Section {
            NavigationLink {
                TextExpansionsView()
            } label: {
                LabeledContent("Text expansions", value: "\(model.settings.textExpansions.count)")
            }
        } footer: {
            Text("Type a shortcut, e.g. “mvg”, and the bar above the keys shows what it becomes. Space expands it; tap ✕ to keep what you typed.")
        }
    }
}

struct TextExpansionsView: View {
    @EnvironmentObject private var model: AppSettingsModel
    @State private var shortcut = ""
    @State private var expansion = ""
    @State private var editing: TextExpansion?
    @FocusState private var focus: Field?

    private enum Field { case shortcut, expansion }

    private var cleanedShortcut: String { TextExpander.cleanShortcut(shortcut) }
    private var canAdd: Bool {
        !cleanedShortcut.isEmpty && !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var replacesExisting: Bool {
        model.settings.textExpansions.contains {
            $0.shortcut.lowercased() == cleanedShortcut.lowercased() && $0.id != editing?.id
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Shortcut, e.g. mvg", text: $shortcut)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .shortcut)
                    .submitLabel(.next)
                    .onSubmit { focus = .expansion }
                TextField("Expands to, e.g. Met vriendelijke groet,", text: $expansion, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focus, equals: .expansion)
                Button(editing == nil ? "Add" : "Save") { save() }
                    .disabled(!canAdd)
                if editing != nil {
                    Button("Cancel editing", role: .cancel) { clear() }
                }
            } header: {
                Text(editing == nil ? "New expansion" : "Edit “\(editing!.shortcut)”")
            } footer: {
                if !shortcut.isEmpty, cleanedShortcut != shortcut {
                    Text("Shortcuts are letters and digits only, so it will be “\(cleanedShortcut)”.")
                } else if replacesExisting {
                    Text("This replaces the expansion you already have for “\(cleanedShortcut)”.")
                } else {
                    Text("Typing the shortcut with a capital (Mvg) capitalises the first letter of the expansion.")
                }
            }

            Section("Your expansions") {
                if model.settings.textExpansions.isEmpty {
                    Text("None yet.").foregroundStyle(.secondary)
                }
                ForEach(model.settings.textExpansions) { item in
                    Button {
                        editing = item
                        shortcut = item.shortcut
                        expansion = item.expansion
                        focus = .expansion
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.shortcut).font(.body.monospaced())
                            Text(item.expansion)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    model.settings.textExpansions.remove(atOffsets: offsets)
                    if let editing, !model.settings.textExpansions.contains(editing) { clear() }
                }
            }
        }
        .navigationTitle("Text expansions")
        .toolbar { EditButton().disabled(model.settings.textExpansions.isEmpty) }
    }

    private func save() {
        var list = model.settings.textExpansions
        if let editing { list.removeAll { $0.id == editing.id } }
        let item = TextExpansion(id: editing?.id ?? UUID(), shortcut: cleanedShortcut,
                                 expansion: expansion.trimmingCharacters(in: .whitespacesAndNewlines))
        model.settings.textExpansions = TextExpander.adding(item, to: list)
        clear()
    }

    private func clear() {
        editing = nil
        shortcut = ""
        expansion = ""
        focus = nil
    }
}
