import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// How a touch is turned into a key (Settings → Typing → Touch map).
public enum TouchModelKind: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Each key owns its own rectangle, and taps in the gaps go to the nearest key.
    case normal
    /// Like normal, but letters reach a few points into shift, delete and the space bar,
    /// so near misses still type the letter.
    case larger
    /// Learned from your own typing in the app's touch trainer.
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .normal: "Normal"
        case .larger: "Larger letters"
        case .custom: "Custom (trained)"
        }
    }

    public var detail: String {
        switch self {
        case .normal: "Every key gets its own area, and taps between two keys go to the closest one."
        case .larger: "Letters grow a little into shift, delete and the space bar, so near misses still type the letter."
        case .custom: "Learned from where you actually tap each letter. Train it with a few sentences; train more to improve it."
        }
    }
}

/// One recorded tap: the letter that was meant, and where the finger landed relative to that key's
/// centre, in key sizes (x: 0.5 = half a key to the right, y: 0.5 = half a key lower).
public struct TouchSample: Codable, Equatable, Sendable {
    public let character: String
    public let x: Double
    public let y: Double

    public init(character: String, x: Double, y: Double) {
        self.character = character
        self.x = x
        self.y = y
    }
}

/// Everything the touch trainer recorded. The keyboard turns it into one small Gaussian per letter:
/// where you tend to hit that key (the mean) and how spread out your taps are (the deviation).
/// A tap goes to the letter for which it is most likely. Letters with few taps lean on a default
/// that behaves like the normal layout, so a short training session can't make typing worse.
public struct TouchProfile: Codable, Equatable, Sendable {
    public private(set) var samples: [TouchSample]

    /// Oldest taps are dropped beyond this, so the profile follows how you type now.
    public static let maxSamples = 4000

    public init(samples: [TouchSample] = []) {
        self.samples = Array(samples.suffix(Self.maxSamples))
    }

    public var isEmpty: Bool { samples.isEmpty }

    public mutating func add(_ sample: TouchSample) {
        samples.append(sample)
        if samples.count > Self.maxSamples { samples.removeFirst(samples.count - Self.maxSamples) }
    }

    public mutating func add(contentsOf newSamples: [TouchSample]) {
        for sample in newSamples { add(sample) }
    }

    public func count(for character: String) -> Int {
        samples.reduce(0) { $1.character == character ? $0 + 1 : $0 }
    }

    /// The learned model, per letter.
    public func statistics() -> [String: KeyStatistics] {
        var grouped: [String: [TouchSample]] = [:]
        for sample in samples { grouped[sample.character, default: []].append(sample) }
        return grouped.mapValues(KeyStatistics.init)
    }
}

/// Where taps on one key land, in key sizes relative to its centre. Shrunk towards the default
/// (centre, `defaultDeviation`) when there are only a few samples.
public struct KeyStatistics: Equatable, Sendable {
    public let count: Int
    public let meanX: Double
    public let meanY: Double
    public let deviationX: Double
    public let deviationY: Double

    /// About a third of a key: with this, the most likely key is simply the nearest one.
    public static let defaultDeviation = 0.33
    /// How many imaginary "default" taps each key starts with.
    static let priorWeight = 4.0
    static let deviationRange = 0.15...0.65

    public static let `default` = KeyStatistics(count: 0, meanX: 0, meanY: 0,
                                                deviationX: defaultDeviation, deviationY: defaultDeviation)

    init(count: Int, meanX: Double, meanY: Double, deviationX: Double, deviationY: Double) {
        self.count = count
        self.meanX = meanX
        self.meanY = meanY
        self.deviationX = deviationX
        self.deviationY = deviationY
    }

    init(samples: [TouchSample]) {
        let n = Double(samples.count)
        let k = Self.priorWeight
        let sumX = samples.reduce(0) { $0 + $1.x }
        let sumY = samples.reduce(0) { $0 + $1.y }
        let meanX = sumX / (n + k)
        let meanY = sumY / (n + k)
        // Spread around the shrunk mean, plus the prior's spread for the imaginary taps.
        let prior = Self.defaultDeviation * Self.defaultDeviation * k
        let varX = (prior + samples.reduce(0) { $0 + ($1.x - meanX) * ($1.x - meanX) }) / (n + k)
        let varY = (prior + samples.reduce(0) { $0 + ($1.y - meanY) * ($1.y - meanY) }) / (n + k)
        self.init(count: samples.count, meanX: meanX, meanY: meanY,
                  deviationX: sqrt(varX).clamped(to: Self.deviationRange),
                  deviationY: sqrt(varY).clamped(to: Self.deviationRange))
    }

    /// How far a tap is from this key once the learned habits are taken into account, in points
    /// (negative = inside, deeper is better). The key is moved by the average offset of your taps,
    /// and the distance is stretched where your taps are tight and shrunk where they spread out.
    /// With no samples this is exactly the plain distance, so an untrained key acts like normal.
    func adjustedDistance(from point: CGPoint, to rect: CGRect) -> Double {
        let shifted = CGPoint(x: point.x - meanX * rect.width, y: point.y - meanY * rect.height)
        return KeyHitTester.signedDistance(from: shifted, to: rect,
                                           scaleX: Self.defaultDeviation / deviationX,
                                           scaleY: Self.defaultDeviation / deviationY)
    }
}

/// Decides which key a touch belongs to.
public struct KeyHitTester: Sendable {
    public let kind: TouchModelKind
    private let statistics: [String: KeyStatistics]

    /// With `.larger`, how many points letters reach into shift, delete, the space bar and other special keys.
    public static let largerReach = 6.0
    /// The widest gap between keys (between rows); a letter must be at least this close to claim a tap.
    static let maxGap = KeyboardMetrics.rowSpacing + 1

    public init(kind: TouchModelKind, profile: TouchProfile? = nil) {
        self.kind = kind
        self.statistics = kind == .custom ? (profile?.statistics() ?? [:]) : [:]
    }

    public func frame(at point: CGPoint, in frames: [KeyFrame]) -> KeyFrame? {
        // Every touch goes to the closest key, so taps in the gaps between keys still count.
        guard let nearest = Self.nearest(point, in: frames) else { return nil }
        switch kind {
        case .normal:
            return nearest
        case .larger:
            return largerLetter(point, nearest: nearest, in: frames) ?? nearest
        case .custom:
            // Special keys (shift, delete, space…) keep their rectangles; only letters are learned.
            guard nearest.key.character != nil else { return nearest }
            return mostLikelyLetter(point, in: frames) ?? nearest
        }
    }

    /// A letter just next to the special key that was hit, if the touch is near that key's edge.
    private func largerLetter(_ point: CGPoint, nearest: KeyFrame, in frames: [KeyFrame]) -> KeyFrame? {
        guard nearest.key.character == nil,
              let letter = Self.nearest(point, in: frames.filter { $0.key.character != nil })
        else { return nil }
        let depth = max(0, -Self.signedDistance(from: point, to: nearest.rect))
        guard depth < Self.largerReach,
              Self.signedDistance(from: point, to: letter.rect) <= depth + Self.maxGap
        else { return nil }
        return letter
    }

    private func mostLikelyLetter(_ point: CGPoint, in frames: [KeyFrame]) -> KeyFrame? {
        var best: KeyFrame?
        var bestScore = Double.infinity
        for frame in frames {
            guard let character = frame.key.character else { continue }
            // Only nearby keys can win, so an odd sample can't steal taps from across the keyboard.
            guard abs(point.x - frame.rect.midX) < frame.rect.width * 1.6,
                  abs(point.y - frame.rect.midY) < frame.rect.height * 1.3
            else { continue }
            let score = (statistics[character] ?? .default).adjustedDistance(from: point, to: frame.rect)
            if score < bestScore {
                bestScore = score
                best = frame
            }
        }
        return best
    }

    static func nearest(_ point: CGPoint, in frames: [KeyFrame]) -> KeyFrame? {
        frames.min { signedDistance(from: point, to: $0.rect) < signedDistance(from: point, to: $1.rect) }
    }

    /// Distance from the point to the rectangle's edge: positive outside, negative inside.
    /// `scaleX` / `scaleY` stretch the horizontal and vertical parts.
    static func signedDistance(from point: CGPoint, to rect: CGRect, scaleX: Double = 1, scaleY: Double = 1) -> Double {
        let outsideX = max(rect.minX - point.x, 0, point.x - rect.maxX) * scaleX
        let outsideY = max(rect.minY - point.y, 0, point.y - rect.maxY) * scaleY
        if outsideX > 0 || outsideY > 0 {
            return (outsideX * outsideX + outsideY * outsideY).squareRoot()
        }
        let depthX = min(point.x - rect.minX, rect.maxX - point.x) * scaleX
        let depthY = min(point.y - rect.minY, rect.maxY - point.y) * scaleY
        return -min(depthX, depthY)
    }
}

/// Saves the touch profile in the App Group, next to the settings.
public struct TouchProfileStore {
    static let key = "touchProfile.v1"
    private let defaults: UserDefaults

    public init() {
        self.defaults = UserDefaults(suiteName: SettingsStore.appGroupID) ?? .standard
    }

    /// For tests.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> TouchProfile {
        guard let data = defaults.data(forKey: Self.key),
              let profile = try? JSONDecoder().decode(TouchProfile.self, from: data)
        else { return TouchProfile() }
        return profile
    }

    public func save(_ profile: TouchProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
