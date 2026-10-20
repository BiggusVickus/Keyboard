import Foundation

/// Decides whether a finger leaving a key should still type it. Kept apart from UIKit so it can be tested.
///
/// Two things can swallow a tap that the user clearly made:
/// - iOS cancels the touch (a system gesture took it over) instead of reporting the lift.
/// - The main thread was busy, so the long-press timer ran before the waiting lift was handled,
///   and a quick tap turned into an accent popup or the space-bar trackpad.
/// In both cases the touch's own timestamps show it was a short tap, so the key is typed anyway.
public enum KeyRelease {
    public enum How: Sendable {
        /// The finger was lifted normally.
        case lifted
        /// iOS cancelled the touch (touchesCancelled).
        case cancelledBySystem
        /// iOS never reported the lift; noticed when the next finger landed.
        case lost
        /// The keyboard itself threw the touch away (keyboard hidden, panel opened).
        case discarded
    }

    /// Holding a key this long opens its popup (or turns the space bar into a trackpad).
    public static let longPressDelay: TimeInterval = 0.38
    /// A tap may wander this far (in points) and still count as a tap.
    public static let tapSlop: Double = 12

    /// Short and barely moved, judged by the touch's own timestamps, not by when we got to see it.
    public static func isQuickTap(duration: TimeInterval?, travel: Double) -> Bool {
        guard let duration else { return false }
        return duration < longPressDelay && travel < tapSlop
    }

    /// For a touch that was still an ordinary key press when it ended.
    public static func typesKey(_ how: How, duration: TimeInterval?, travel: Double) -> Bool {
        switch how {
        case .lifted, .lost: true
        case .cancelledBySystem: isQuickTap(duration: duration, travel: travel)
        case .discarded: false
        }
    }

    /// For a touch that had become a long press (popup or trackpad): was it really a tap?
    public static func longPressWasReallyATap(_ how: How, duration: TimeInterval?, travel: Double) -> Bool {
        switch how {
        case .lifted, .cancelledBySystem: isQuickTap(duration: duration, travel: travel)
        case .lost, .discarded: false
        }
    }
}
