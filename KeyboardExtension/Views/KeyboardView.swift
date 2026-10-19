import SwiftUI
import KeyboardCore

/// The whole keyboard: the bar on top (suggestions, grammar chips, or the translator)
/// and below it the key rows, or a panel with grammar details or AI results.
struct KeyboardView: View {
    @ObservedObject var model: KeyboardViewModel

    static let topBarHeight: CGFloat = 40
    static let translatorBarHeight: CGFloat = 136
    static let bottomPadding: CGFloat = 4
    /// Four rows of keys. Panels get exactly this much room, so the keyboard never jumps.
    static let keyAreaHeight = CGFloat(KeyboardMetrics.keyAreaHeight)

    /// Total height for the controller's constraint.
    static func height(for panel: Panel) -> CGFloat {
        (panel == .translator ? translatorBarHeight : topBarHeight) + keyAreaHeight + bottomPadding
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isTranslating {
                TranslatorBar(model: model)
                    .frame(height: Self.translatorBarHeight)
            } else {
                TopBar(model: model)
                    .frame(height: Self.topBarHeight)
            }
            keyArea
                .frame(height: Self.keyAreaHeight)
                .padding(.bottom, Self.bottomPadding)
        }
    }

    @ViewBuilder
    private var keyArea: some View {
        switch model.panel {
        case .none, .translator:
            KeyArea(model: model, touches: model.touches)
        case .issue(let issue):
            IssuePanel(model: model, issue: issue)
                .padding(.horizontal, CGFloat(KeyboardMetrics.horizontalPadding))
        case .tools:
            ToolsPanel(model: model)
                .padding(.horizontal, CGFloat(KeyboardMetrics.horizontalPadding))
        case .review(let request):
            ReviewPanel(model: model, request: request)
                .padding(.horizontal, CGFloat(KeyboardMetrics.horizontalPadding))
        }
    }
}

/// The keys, drawn at the frames from `KeyboardGeometry`, with one touch surface on top.
/// The same frames are used for drawing and for deciding which key a touch hits.
struct KeyArea: View {
    @ObservedObject var model: KeyboardViewModel
    @ObservedObject var touches: KeyTouchHandler

    var body: some View {
        GeometryReader { geo in
            let frames = KeyboardGeometry.frames(for: model.layout, width: geo.size.width)
            let style = model.keyCapStyle(trackpad: touches.isTrackpadActive)
            ZStack(alignment: .topLeading) {
                ForEach(frames, id: \.key.id) { frame in
                    KeyCap(key: frame.key, size: frame.rect.size,
                           isPressed: touches.pressedKeyIDs.contains(frame.key.id), style: style)
                        .equatable()
                        .position(x: frame.rect.midX, y: frame.rect.midY)
                }
                // Reaches over the bottom padding too, so a tap below the space bar still counts.
                KeyTouchSurface(handler: touches, frames: frames, width: geo.size.width)
                    .padding(.bottom, -KeyboardView.bottomPadding)
                previews(frames: frames, style: style)
                if let popup = touches.popup {
                    AlternatesPopupView(popup: popup)
                }
            }
        }
    }

    @ViewBuilder
    private func previews(frames: [KeyFrame], style: KeyCapStyle) -> some View {
        if KeyCap.showsPreviews, !touches.isTrackpadActive {
            ForEach(frames.filter { touches.pressedKeyIDs.contains($0.key.id) && touches.popup?.keyID != $0.key.id },
                    id: \.key.id) { frame in
                if let character = frame.key.character {
                    KeyPreview(text: KeyCap.display(character, shift: style.shift), keyRect: frame.rect)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// Hosts the UIKit view that receives the touches.
struct KeyTouchSurface: UIViewRepresentable {
    let handler: KeyTouchHandler
    let frames: [KeyFrame]
    let width: CGFloat

    func makeUIView(context: Context) -> KeyboardTouchView {
        let view = KeyboardTouchView()
        view.handler = handler
        return view
    }

    func updateUIView(_ view: KeyboardTouchView, context: Context) {
        view.handler = handler
        if handler.frames != frames { handler.frames = frames }
        handler.areaWidth = width
    }
}

/// Colours that match the system keyboard in light and dark mode.
enum KeyColors {
    static let letter = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    })
    static let special = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.27, alpha: 1)
            : UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1)
    })
    /// Cards and panels that sit where the keys normally are.
    static let panel = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.20, alpha: 1) : UIColor(white: 0.98, alpha: 1)
    })
    static let error = Color(UIColor.systemRed)
    static let tip = Color(UIColor.systemBlue)

    static func color(for kind: GrammarIssue.Kind) -> Color {
        kind == .error ? error : tip
    }
}
