import Foundation

/// Prioritäten je Messwerttyp. Vom Nutzer anpassbar (Einstellungen → Datenquellen).
public struct SourcePriorities: Codable, Hashable, Sendable {
    public var order: [VitalType: [DataSource]]
    /// Quellen, deren über Apple Health gespiegelte Kopien ignoriert werden, weil die Quelle
    /// direkt angebunden ist (verhindert Doppelzählung z. B. WHOOP → Health → App).
    public var suppressHealthKitCopiesOf: Set<DataSource>
    /// Vom Nutzer deaktivierte Quellen werden bei Auswertungen nicht berücksichtigt (Rohdaten bleiben erhalten).
    public var disabledSources: Set<DataSource>

    public init(order: [VitalType: [DataSource]], suppressHealthKitCopiesOf: Set<DataSource> = [], disabledSources: Set<DataSource> = []) {
        self.order = order; self.suppressHealthKitCopiesOf = suppressHealthKitCopiesOf; self.disabledSources = disabledSources
    }

    public static let standard: SourcePriorities = {
        var o: [VitalType: [DataSource]] = [:]
        let live: [DataSource] = [.appleWatch, .garmin, .whoop, .iPhone, .otherHealthApp, .manual]
        let recovery: [DataSource] = [.whoop, .appleWatch, .garmin, .otherHealthApp, .manual]
        let activity: [DataSource] = [.garmin, .appleWatch, .iPhone, .whoop, .otherHealthApp]
        o[.heartRate] = live
        o[.restingHeartRate] = recovery
        o[.hrvRMSSD] = [.whoop, .otherHealthApp]
        o[.hrvSDNN] = [.appleWatch, .garmin, .otherHealthApp]
        for t in [VitalType.sleepDuration, .sleepDeep, .sleepREM, .sleepLight, .sleepAwake] { o[t] = recovery }
        o[.recoveryScore] = [.whoop]
        o[.strain] = [.whoop]
        o[.respiratoryRate] = recovery
        o[.oxygenSaturation] = recovery
        o[.activeEnergy] = activity
        o[.steps] = activity
        o[.workoutDuration] = [.app, .appleWatch, .garmin, .whoop]
        o[.perceivedExertion] = [.app, .manual]
        return SourcePriorities(order: o)
    }()

    public func ranked(_ type: VitalType) -> [DataSource] {
        (order[type] ?? DataSource.allCases).filter { !disabledSources.contains($0) }
    }
}

public struct IngestResult: Hashable, Sendable {
    public var inserted: Int = 0
    public var duplicates: Int = 0
    public var suppressed: Int = 0
    public var rejected: Int = 0
}

/// Aufgelöster Tageswert inkl. Herkunft und Alternativen anderer Quellen.
public struct ResolvedValue: Hashable, Sendable {
    public var type: VitalType
    public var dayKey: String
    public var value: Double
    public var source: DataSource
    public var quality: MeasurementQuality
    public var alternatives: [DataSource: Double]
}

public struct Baseline: Hashable, Sendable {
    public var mean: Double
    public var median: Double
    public var standardDeviation: Double
    public var count: Int
    public var source: DataSource
}

public struct DayPoint: Hashable, Sendable {
    public var dayKey: String
    public var value: Double?   // nil = keine Messung (wird NICHT interpoliert)
}

/// Zusammenführung von Vitaldaten mehrerer Quellen.
public struct VitalHarmonizer: Sendable {
    public var priorities: SourcePriorities
    public var calendar: Calendar

    public init(priorities: SourcePriorities = .standard, calendar: Calendar = .iso8601Monday) {
        self.priorities = priorities; self.calendar = calendar
    }

    // MARK: Plausibilität

    static func isPlausible(_ s: VitalSample) -> Bool {
        guard s.value.isFinite, s.value >= 0 else { return false }
        switch s.type {
        case .heartRate: return (25...250).contains(s.value)
        case .restingHeartRate: return (25...150).contains(s.value)
        case .hrvSDNN, .hrvRMSSD: return s.value > 0 && s.value < 400
        case .recoveryScore, .oxygenSaturation: return s.value <= 100
        case .sleepDuration, .sleepDeep, .sleepREM, .sleepLight, .sleepAwake: return s.value <= 24 * 60
        case .perceivedExertion: return s.value >= 1 && s.value <= 10
        case .strain: return s.value <= 21
        default: return true
        }
    }

    // MARK: Aufnahme / Duplikate

    private static func recordKey(_ s: VitalSample) -> String? {
        s.sourceRecordId.map { "\(s.channel.rawValue)|\(s.type.rawValue)|\($0)" }
    }
    private static func contentKey(_ s: VitalSample) -> String {
        "\(s.source.rawValue)|\(s.type.rawValue)|\(Int(s.start.timeIntervalSince1970))|\(Int((s.value * 100).rounded()))"
    }

    /// Fügt neue Rohdaten hinzu. Mehrfachsynchronisierungen erzeugen keine Duplikate.
    public func ingest(_ incoming: [VitalSample], into store: inout [VitalSample]) -> IngestResult {
        var result = IngestResult()
        var recordKeys = Set(store.compactMap(Self.recordKey))
        var contentKeys = Set(store.map(Self.contentKey))
        for s in incoming {
            guard Self.isPlausible(s) else { result.rejected += 1; continue }
            if s.channel == .healthKit && priorities.suppressHealthKitCopiesOf.contains(s.source) {
                result.suppressed += 1; continue
            }
            if let rk = Self.recordKey(s), recordKeys.contains(rk) { result.duplicates += 1; continue }
            let ck = Self.contentKey(s)
            if contentKeys.contains(ck) { result.duplicates += 1; continue }
            store.append(s)
            if let rk = Self.recordKey(s) { recordKeys.insert(rk) }
            contentKeys.insert(ck)
            result.inserted += 1
        }
        return result
    }

    // MARK: Tageswerte

    /// Aggregation eines Tages für eine einzelne Quelle.
    public func dailyAggregate(_ samples: [VitalSample], type: VitalType) -> Double? {
        let values = samples.map(\.value)
        guard !values.isEmpty else { return nil }
        switch type {
        case .steps, .activeEnergy, .workoutDuration,
             .sleepDuration, .sleepDeep, .sleepREM, .sleepLight, .sleepAwake:
            return values.reduce(0, +)
        case .recoveryScore, .strain:
            return samples.max { $0.start < $1.start }?.value
        case .heartRate:
            return values.reduce(0, +) / Double(values.count)
        default:
            return values.reduce(0, +) / Double(values.count)
        }
    }

    func dayKey(_ s: VitalSample) -> String {
        // Schlaf und Regeneration werden dem Aufwachtag zugeordnet.
        DayKey.string(for: s.end ?? s.start, calendar: calendar)
    }

    /// Wert eines Tages gemäß Quellenpriorität. Quellen werden NICHT vermischt.
    public func resolve(_ type: VitalType, dayKey key: String, in samples: [VitalSample]) -> ResolvedValue? {
        let ofDay = samples.filter { $0.type == type && dayKey($0) == key && !priorities.disabledSources.contains($0.source) }
        guard !ofDay.isEmpty else { return nil }
        let bySource = Dictionary(grouping: ofDay, by: \.source)
        var alternatives: [DataSource: Double] = [:]
        for (src, list) in bySource { alternatives[src] = dailyAggregate(list, type: type) }
        let ranked = priorities.ranked(type)
        guard let chosen = ranked.first(where: { bySource[$0] != nil }) ?? bySource.keys.sorted(by: { $0.rawValue < $1.rawValue }).first,
              let value = alternatives[chosen] else { return nil }
        alternatives.removeValue(forKey: chosen)
        let quality = bySource[chosen]?.first?.quality ?? .measured
        return ResolvedValue(type: type, dayKey: key, value: value, source: chosen, quality: quality, alternatives: alternatives)
    }

    /// Tageswerte einer EINZELNEN Quelle über einen Zeitraum (fehlende Tage = nil).
    public func series(_ type: VitalType, source: DataSource, days: Int, endingAt end: Date, in samples: [VitalSample]) -> [DayPoint] {
        let relevant = samples.filter { $0.type == type && $0.source == source }
        let grouped = Dictionary(grouping: relevant, by: dayKey)
        return (0..<days).reversed().map { offset in
            let d = calendar.date(byAdding: .day, value: -offset, to: end)!
            let key = DayKey.string(for: d, calendar: calendar)
            return DayPoint(dayKey: key, value: grouped[key].flatMap { dailyAggregate($0, type: type) })
        }
    }

    /// Persönliche Basislinie (Tage VOR `day`, gleiche Quelle). Mindestens `minDays` Messtage.
    public func baseline(_ type: VitalType, source: DataSource, before day: Date, windowDays: Int = 28, minDays: Int = 5,
                         in samples: [VitalSample]) -> Baseline? {
        guard let end = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
        let values = series(type, source: source, days: windowDays, endingAt: end, in: samples).compactMap(\.value)
        guard values.count >= minDays else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let sorted = values.sorted()
        let median = sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(1, values.count - 1))
        return Baseline(mean: mean, median: median, standardDeviation: variance.squareRoot(), count: values.count, source: source)
    }

    /// Höchstpriorisierte Quelle, die für `day` einen Wert UND eine Basislinie hat.
    public func comparableReading(_ type: VitalType, on day: Date, in samples: [VitalSample]) -> (value: Double, baseline: Baseline)? {
        let key = DayKey.string(for: day, calendar: calendar)
        for src in priorities.ranked(type) {
            let today = samples.filter { $0.type == type && $0.source == src && dayKey($0) == key }
            guard let v = dailyAggregate(today, type: type),
                  let b = baseline(type, source: src, before: day, in: samples) else { continue }
            return (v, b)
        }
        return nil
    }

    /// Verdichtete Regenerationskennzahlen eines Tages je Quelle.
    public func recoveryMetrics(dayKey key: String, in samples: [VitalSample]) -> [RecoveryMetric] {
        let ofDay = samples.filter { dayKey($0) == key && $0.type.isDailyMetric }
        return Dictionary(grouping: ofDay, by: \.source).map { src, list in
            func agg(_ t: VitalType) -> Double? { dailyAggregate(list.filter { $0.type == t }, type: t) }
            let hrvRMSSD = agg(.hrvRMSSD), hrvSDNN = agg(.hrvSDNN)
            return RecoveryMetric(dayKey: key, source: src, recoveryScore: agg(.recoveryScore),
                                  hrvMs: hrvRMSSD ?? hrvSDNN, hrvMethod: hrvRMSSD != nil ? "RMSSD" : (hrvSDNN != nil ? "SDNN" : nil),
                                  restingHeartRate: agg(.restingHeartRate), sleepMinutes: agg(.sleepDuration),
                                  deepSleepMinutes: agg(.sleepDeep), remSleepMinutes: agg(.sleepREM),
                                  lightSleepMinutes: agg(.sleepLight), awakeMinutes: agg(.sleepAwake),
                                  strain: agg(.strain), quality: list.contains { $0.quality == .demo } ? .demo : .measured)
        }.sorted { $0.source.rawValue < $1.source.rawValue }
    }
}
