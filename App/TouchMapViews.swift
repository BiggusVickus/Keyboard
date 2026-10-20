import SwiftUI
import UIKit
import KeyboardCore

/// Settings → Touch map: pick normal / larger / custom, see the map, and train it.
struct TouchMapSection: View {
    @EnvironmentObject private var model: AppSettingsModel
    @State private var profile = TouchProfileStore().load()
    @State private var showsTrainer = false
    @State private var confirmsReset = false
    @State private var report = SettingsStore().loadKeyboardReport()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            Picker("Touch map", selection: $model.settings.touchModel) {
                ForEach(TouchModelKind.allCases) { Text($0.title).tag($0) }
            }

            PressMapView(kind: model.settings.touchModel, profile: profile,
                         language: model.settings.currentLanguage)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            KeyboardStatusRow(report: report, chosen: model.settings.touchModel)

            Button(profile.isEmpty ? "Train my touch map…" : "Train more…") { showsTrainer = true }
            if !profile.isEmpty {
                LabeledContent("Taps learned", value: "\(profile.samples.count)")
                Button("Reset training", role: .destructive) { confirmsReset = true }
            }
        } header: {
            Text("Touch map")
        } footer: {
            Text(footer)
        }
        .fullScreenCover(isPresented: $showsTrainer, onDismiss: { profile = TouchProfileStore().load() }) {
            TouchTrainingView()
                .environmentObject(model)
        }
        .confirmationDialog("Delete all recorded taps?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset training", role: .destructive) {
                TouchProfileStore().save(TouchProfile())
                profile = TouchProfile()
                if model.settings.touchModel == .custom { model.settings.touchModel = .normal }
            }
        }
        .onAppear {
            profile = TouchProfileStore().load()
            report = SettingsStore().loadKeyboardReport()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { report = SettingsStore().loadKeyboardReport() }
        }
    }

    private var footer: String {
        var text = model.settings.touchModel.detail
        if model.settings.touchModel == .custom, profile.isEmpty {
            text += " Not trained yet, so it works like Normal for now."
        }
        return text + " Each colour is the area that types that key."
    }
}

/// What the keyboard itself last reported: which touch map it really uses, and whether iOS is
/// still running an older keyboard than this app.
struct KeyboardStatusRow: View {
    let report: KeyboardReport?
    let chosen: TouchModelKind

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .foregroundStyle(color)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var outdated: Bool { report?.isOutdated(comparedTo: BuildInfo.executableDate) ?? false }

    private var title: String {
        guard let report else { return "Keyboard hasn't checked in yet" }
        if outdated { return "Keyboard is an older version" }
        let taps = report.touchModel == .custom ? " (\(report.trainedTaps) taps)" : ""
        return "Keyboard uses \(report.touchModel.title)\(taps)"
    }

    private var detail: String {
        guard let report else {
            return "Open the Taalhulp keyboard once in any app. It needs Full Access to report here."
        }
        if outdated {
            return "iOS is still running a keyboard from before this app was installed, so new features (and the touch map) aren't active. Switch to another keyboard and back with 🌐, or restart the iPhone."
        }
        var text = "Checked \(report.date.formatted(.relative(presentation: .named)))."
        if report.touchModel != chosen {
            text += " It switches to \(chosen.title) the next time the keyboard opens."
        }
        if let build = report.build {
            text += " Build \(build.formatted(date: .abbreviated, time: .shortened))."
        }
        return text
    }

    private var symbol: String {
        guard report != nil else { return "questionmark.circle" }
        return outdated ? "exclamationmark.triangle.fill" : "checkmark.circle"
    }

    private var color: Color {
        guard report != nil else { return .secondary }
        return outdated ? .orange : .primary
    }
}

// MARK: - Press map

/// A picture of which key each spot on the keyboard types, for the chosen touch map.
/// For a trained map, your recorded taps are drawn on top as a heat map.
struct PressMapView: View {
    let kind: TouchModelKind
    let profile: TouchProfile
    let language: KeyboardLanguage

    private var layout: KeyboardLayout {
        KeyboardLayout.make(language: language, page: .letters, showsGlobe: false)
    }

    var body: some View {
        Canvas { context, size in
            let frames = KeyboardGeometry.frames(for: layout, width: size.width)
            let tester = KeyHitTester(kind: kind, profile: kind == .custom ? profile : nil)
            drawRegions(&context, size: size, frames: frames, tester: tester)
            drawKeys(&context, frames: frames)
            if kind == .custom { drawSamples(&context, frames: frames) }
        }
        .frame(height: CGFloat(KeyboardMetrics.keyAreaHeight))
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Map of which key each part of the keyboard types")
    }

    private func drawRegions(_ context: inout GraphicsContext, size: CGSize, frames: [KeyFrame], tester: KeyHitTester) {
        let step: CGFloat = 3
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
                let point = CGPoint(x: x + step / 2, y: y + step / 2)
                if let frame = tester.frame(at: point, in: frames) {
                    context.fill(Path(CGRect(x: x, y: y, width: step, height: step)),
                                 with: .color(Self.color(for: frame).opacity(0.45)))
                }
                x += step
            }
            y += step
        }
    }

    private func drawKeys(_ context: inout GraphicsContext, frames: [KeyFrame]) {
        for frame in frames {
            context.stroke(Path(roundedRect: frame.rect, cornerRadius: 5), with: .color(.primary.opacity(0.35)),
                           lineWidth: 0.75)
            let label: String
            switch frame.key.kind {
            case .character(let c): label = c
            case .shift: label = "⇧"
            case .delete: label = "⌫"
            case .space: label = "space"
            case .returnKey: label = "⏎"
            case .languageSwitch: label = language.shortLabel
            case .page: label = "123"
            case .globe: label = "🌐"
            }
            context.draw(Text(label).font(.system(size: 13)).foregroundStyle(.secondary),
                         at: frame.center)
        }
    }

    /// Recorded taps as soft dots: where they pile up, the colour gets stronger.
    private func drawSamples(_ context: inout GraphicsContext, frames: [KeyFrame]) {
        var framesByCharacter: [String: KeyFrame] = [:]
        for frame in frames { if let c = frame.key.character { framesByCharacter[c] = frame } }
        for sample in profile.samples {
            guard let frame = framesByCharacter[sample.character] else { continue }
            let point = CGPoint(x: frame.rect.midX + sample.x * frame.rect.width,
                                y: frame.rect.midY + sample.y * frame.rect.height)
            context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                         with: .color(.red.opacity(0.18)))
        }
        // The learned centre of each key.
        for (character, stats) in profile.statistics() {
            guard let frame = framesByCharacter[character], stats.count >= 3 else { continue }
            let point = CGPoint(x: frame.rect.midX + stats.meanX * frame.rect.width,
                                y: frame.rect.midY + stats.meanY * frame.rect.height)
            var cross = Path()
            cross.move(to: CGPoint(x: point.x - 4, y: point.y))
            cross.addLine(to: CGPoint(x: point.x + 4, y: point.y))
            cross.move(to: CGPoint(x: point.x, y: point.y - 4))
            cross.addLine(to: CGPoint(x: point.x, y: point.y + 4))
            context.stroke(cross, with: .color(.primary), lineWidth: 1.5)
        }
    }

    /// Neighbouring keys get different colours; special keys are grey.
    static func color(for frame: KeyFrame) -> Color {
        guard frame.key.character != nil else { return .gray }
        let palette: [Color] = frame.row % 2 == 0 ? [.blue, .teal] : [.orange, .pink]
        return palette[frame.index % 2]
    }
}

// MARK: - Trainer

/// Shows sentences to type on a copy of the keyboard and records where each letter is tapped.
struct TouchTrainingView: View {
    @EnvironmentObject private var model: AppSettingsModel
    @Environment(\.dismiss) private var dismiss

    static let sentencesPerRound = 5
    private static let nextSentenceKey = "touchTraining.nextSentence"

    @State private var sentences: [String] = []
    @State private var sentenceIndex = 0
    @State private var trainer: TouchTrainer?
    @State private var recorded: [TouchSample] = []
    @State private var misses = 0
    @State private var flashMiss = false
    @State private var finished = false

    private var language: KeyboardLanguage { model.settings.currentLanguage }
    private var layout: KeyboardLayout { KeyboardLayout.make(language: language, page: .letters, showsGlobe: false) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if finished {
                    summary
                } else {
                    prompt
                }
                Spacer(minLength: 0)
                if !finished {
                    TrainingKeyboard(layout: layout, onTap: handleTap)
                        .padding(.bottom, 8)
                        .background(Color(.systemGray5))
                        // Don't hold back taps near the bottom edge for the home-indicator swipe.
                        .defersSystemGestures(on: .bottom)
                }
            }
            .navigationTitle("Touch training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(finished ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
        .onAppear(perform: startRound)
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sentence \(sentenceIndex + 1) of \(sentences.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let trainer {
                let typed = Text(trainer.typedText).foregroundStyle(.primary)
                let upcoming = trainer.remainingText.prefix(1)
                let next = Text(upcoming == " " ? "␣" : upcoming).foregroundStyle(.blue).underline()
                let rest = Text(trainer.remainingText.dropFirst()).foregroundStyle(.secondary)
                Text("\(typed)\(next)\(rest)")
                    .font(.system(size: 26, design: .rounded))
                    // Wrap over as many lines as needed instead of cutting off with "…".
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: flashMiss ? 6 : 0)
            }
            Text("Type the sentence as you normally would. Don't aim extra carefully: the map learns from your normal taps. A tap far from the right letter is skipped; just tap again.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var summary: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Learned \(recorded.count) taps")
                .font(.title2.bold())
            Text("Skipped \(misses) taps that were too far from the letter.")
                .foregroundStyle(.secondary)
            PressMapView(kind: .custom, profile: TouchProfileStore().load(), language: language)
                .padding(.horizontal)
            Button("Train another round") { startRound() }
                .buttonStyle(.bordered)
            if model.settings.touchModel != .custom {
                Button("Use my touch map") {
                    model.settings.touchModel = .custom
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func startRound() {
        let start = UserDefaults.standard.integer(forKey: Self.nextSentenceKey)
        sentences = TrainingSentences.round(for: language, count: Self.sentencesPerRound, startingAt: start)
        UserDefaults.standard.set(start + Self.sentencesPerRound, forKey: Self.nextSentenceKey)
        sentenceIndex = 0
        recorded = []
        misses = 0
        finished = false
        trainer = TouchTrainer(sentence: sentences[0], layout: layout)
    }

    private func handleTap(at point: CGPoint, frames: [KeyFrame]) {
        guard var current = trainer else { return }
        let result = current.tap(at: point, frames: frames)
        switch result {
        case .accepted:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            trainer = current
        case .missed:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            trainer = current
            withAnimation(.default.repeatCount(2, autoreverses: true).speed(4)) { flashMiss = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { flashMiss = false }
        case .finished:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            recorded += current.samples
            misses += current.misses
            if sentenceIndex + 1 < sentences.count {
                sentenceIndex += 1
                trainer = TouchTrainer(sentence: sentences[sentenceIndex], layout: layout)
            } else {
                saveRound()
            }
        }
    }

    /// Adds this round to what was learned before, so every round makes the map better.
    private func saveRound() {
        let store = TouchProfileStore()
        var profile = store.load()
        profile.add(contentsOf: recorded)
        store.save(profile)
        trainer = nil
        finished = true
    }
}

/// A copy of the keyboard's letter page, with exactly the same key frames, for the trainer.
struct TrainingKeyboard: View {
    let layout: KeyboardLayout
    let onTap: (CGPoint, [KeyFrame]) -> Void
    @State private var pressed: String?

    var body: some View {
        GeometryReader { geo in
            let frames = KeyboardGeometry.frames(for: layout, width: geo.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(frames, id: \.key.id) { frame in
                    keyLabel(frame.key)
                        .frame(width: frame.rect.width, height: frame.rect.height)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(fill(for: frame))
                                .shadow(color: .black.opacity(0.3), radius: 0, y: 1)
                        )
                        .position(x: frame.rect.midX, y: frame.rect.midY)
                }
                TouchCaptureView { point in
                    let hit = KeyHitTester(kind: .normal).frame(at: point, in: frames)
                    pressed = hit?.key.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        if pressed == hit?.key.id { pressed = nil }
                    }
                    onTap(point, frames)
                }
            }
        }
        .frame(height: CGFloat(KeyboardMetrics.keyAreaHeight))
        .padding(.top, 8)
    }

    @ViewBuilder
    private func keyLabel(_ key: Key) -> some View {
        switch key.kind {
        case .character(let c): Text(c).font(.system(size: 23))
        case .space: Text("space").font(.system(size: 15))
        case .shift: Image(systemName: "shift")
        case .delete: Image(systemName: "delete.left")
        case .returnKey: Image(systemName: "return")
        default: Text("")
        }
    }

    private func fill(for frame: KeyFrame) -> Color {
        let special = frame.key.character == nil && frame.key.kind != .space
        if pressed == frame.key.id { return Color(.systemGray3) }
        return special ? Color(.systemGray3) : Color(.systemBackground)
    }
}

/// Reports where each finger lands, with several fingers at once, straight from UIKit.
struct TouchCaptureView: UIViewRepresentable {
    let onTouchDown: (CGPoint) -> Void

    func makeUIView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onTouchDown = onTouchDown
        return view
    }

    func updateUIView(_ view: CaptureView, context: Context) {
        view.onTouchDown = onTouchDown
    }

    final class CaptureView: UIView {
        var onTouchDown: ((CGPoint) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches { onTouchDown?(touch.location(in: self)) }
        }
    }
}
