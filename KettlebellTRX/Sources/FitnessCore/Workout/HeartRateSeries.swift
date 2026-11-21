import Foundation

public struct HeartRatePoint: Codable, Hashable, Sendable {
    public var date: Date
    public var bpm: Double
    public init(date: Date, bpm: Double) { self.date = date; self.bpm = bpm }
}

/// Live-Herzfrequenz einer Einheit. Werte kommen in unregelmäßigen Abständen an
/// (HealthKit garantiert keine festen Intervalle) – daher zeitgewichtete Mittelwerte
/// und ausdrückliche Kennzeichnung von Lücken.
public struct HeartRateSeries: Codable, Hashable, Sendable {
    public private(set) var points: [HeartRatePoint] = []
    public var source: DataSource?
    /// Abstand, ab dem eine Messlücke angenommen wird.
    public var gapThreshold: TimeInterval = 30
    /// Ein Wert gilt als „aktuell“, solange er nicht älter ist als diese Spanne.
    public var staleAfter: TimeInterval = 15

    public init(source: DataSource? = nil) { self.source = source }

    /// Fügt einen Messwert ein (sortiert, ohne Duplikate gleicher Zeitpunkte, nur plausible Werte).
    @discardableResult
    public mutating func append(_ p: HeartRatePoint) -> Bool {
        guard p.bpm >= 25, p.bpm <= 250 else { return false }
        if let last = points.last, p.date > last.date {
            points.append(p)
            return true
        }
        if points.contains(where: { abs($0.date.timeIntervalSince(p.date)) < 0.5 }) { return false }
        let idx = points.firstIndex { $0.date > p.date } ?? points.endIndex
        points.insert(p, at: idx)
        return true
    }

    public mutating func append(contentsOf list: [HeartRatePoint]) {
        for p in list { append(p) }
    }

    /// Aktueller Puls oder `nil`, wenn kein frischer Messwert vorliegt.
    public func current(at now: Date) -> HeartRatePoint? {
        guard let last = points.last, now.timeIntervalSince(last.date) <= staleAfter else { return nil }
        return last
    }

    public func window(endingAt now: Date, seconds: TimeInterval) -> [HeartRatePoint] {
        points.filter { $0.date > now.addingTimeInterval(-seconds) && $0.date <= now }
    }

    public var maxBpm: Double? { points.map(\.bpm).max() }
    public var minBpm: Double? { points.map(\.bpm).min() }

    /// Zeitgewichteter Mittelwert; Intervalle über `gapThreshold` werden nicht gewichtet.
    public var timeWeightedAverage: Double? {
        guard !points.isEmpty else { return nil }
        guard points.count > 1 else { return points[0].bpm }
        var weighted = 0.0, total = 0.0
        for i in 0..<(points.count - 1) {
            let dt = points[i + 1].date.timeIntervalSince(points[i].date)
            guard dt > 0, dt <= gapThreshold else { continue }
            weighted += (points[i].bpm + points[i + 1].bpm) / 2 * dt
            total += dt
        }
        return total > 0 ? weighted / total : points.map(\.bpm).reduce(0, +) / Double(points.count)
    }

    public var gapSeconds: Double {
        guard points.count > 1 else { return 0 }
        var g = 0.0
        for i in 0..<(points.count - 1) {
            let dt = points[i + 1].date.timeIntervalSince(points[i].date)
            if dt > gapThreshold { g += dt }
        }
        return g
    }

    public var summary: HeartRateSummary {
        guard !points.isEmpty else { return .unavailable }
        return HeartRateSummary(averageBpm: timeWeightedAverage, maxBpm: maxBpm, minBpm: minBpm,
                                sampleCount: points.count, source: source, gapSeconds: gapSeconds)
    }

    /// Prozent der (geschätzten oder vorgegebenen) maximalen Herzfrequenz.
    public static func percentOfMax(_ bpm: Double, maxHR: Int) -> Double { bpm / Double(maxHR) * 100 }
}

/// Fünf Pulszonen relativ zur maximalen Herzfrequenz.
public enum HeartRateZone: Int, CaseIterable, Sendable {
    case z1 = 1, z2, z3, z4, z5
    public static func zone(for bpm: Double, maxHR: Int) -> HeartRateZone {
        let pct = bpm / Double(maxHR)
        switch pct {
        case ..<0.6: return .z1
        case ..<0.7: return .z2
        case ..<0.8: return .z3
        case ..<0.9: return .z4
        default: return .z5
        }
    }
    public var displayName: String {
        switch self {
        case .z1: return "Sehr leicht"
        case .z2: return "Leicht"
        case .z3: return "Moderat"
        case .z4: return "Intensiv"
        case .z5: return "Maximal"
        }
    }
}
