import SwiftUI
import KeyboardCore

/// The learning log: mistakes fixed in the keyboard, grouped by what they were about.
struct LearnView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var entries: [LearningEntry] = []
    @State private var confirmsClear = false
    private let store = LearningLogStore()

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Nothing to review yet",
                        systemImage: "graduationcap",
                        description: Text("When you accept a grammar fix in the keyboard, it appears here, so you can see what to practise.")
                    )
                } else {
                    Section("What you get wrong most") {
                        ForEach(LearningLogStore.summary(of: entries).prefix(8)) { item in
                            NavigationLink {
                                TopicView(language: item.language, topic: item.topic,
                                          entries: entries.filter { $0.language == item.language && $0.topic == item.topic })
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.topic.title(for: item.language))
                                        Text(item.language.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(item.count)×")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section("Recent") {
                        ForEach(entries.prefix(50)) { entry in
                            EntryRow(entry: entry)
                        }
                        .onDelete { offsets in
                            let ids = Set(offsets.map { entries[$0].id })
                            store.remove(ids: ids)
                            reload()
                        }
                    }
                }
            }
            .navigationTitle("Learn")
            .toolbar {
                if !entries.isEmpty {
                    Button("Clear", role: .destructive) { confirmsClear = true }
                }
            }
            .confirmationDialog("Clear the whole learning log?", isPresented: $confirmsClear, titleVisibility: .visible) {
                Button("Clear log", role: .destructive) {
                    store.clear()
                    reload()
                }
            }
            .onAppear(perform: reload)
            .onChange(of: scenePhase) { _, phase in
                // The keyboard may have added entries while the app was in the background.
                if phase == .active { reload() }
            }
        }
    }

    private func reload() {
        entries = store.load()
    }
}

/// All mistakes about one topic, with the general rule on top.
private struct TopicView: View {
    let language: KeyboardLanguage
    let topic: GrammarTopic
    let entries: [LearningEntry]

    var body: some View {
        List {
            Section("The rule") {
                Text(topic.explanation(for: language))
            }
            Section("Your mistakes") {
                ForEach(entries) { EntryRow(entry: $0) }
            }
        }
        .navigationTitle(topic.title(for: language))
    }
}

private struct EntryRow: View {
    let entry: LearningEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.original)
                    .strikethrough()
                    .foregroundStyle(.red)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.corrected)
                    .foregroundStyle(.green)
            }
            if !entry.explanation.isEmpty {
                Text(entry.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(entry.date, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
