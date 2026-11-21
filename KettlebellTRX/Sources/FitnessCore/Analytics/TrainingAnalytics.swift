import Foundation

public enum AnalyticsPeriod: String, CaseIterable, Sendable, Identifiable {
    case days7, days30, weeks8, months3, months12
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .days7: return "7 Tage"
        case .days30: return "30 Tage"
        case .weeks8: return "8 Wochen"
        case .months3: return "3 Monate"
        case .months12: return "12 Monate"
        }
    }

    public enum Bucket: Sendable { case day, week, month }
    public var bucket: Bucket {
        switch self {
        case .days7, .days30: return .day
        case .weeks8, .months3: return .week
        case .months12: return .month
        }
    }

    public func startDate(endingAt end: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: end)
        switch self {
        case .days7: return calendar.date(byAdding: .day, value: -6, to: today)!
        case .days30: return calendar.date(byAdding: .day, value: -29, to: today)!
        case .weeks8: return calendar.date(byAdding: .weekOfYear, value: -7, to: calendar.startOfWeek(for: today))!
        case .months3: return calendar.date(byAdding: .weekOfYear, value: -12, to: calendar.startOfWeek(for: today))!
        case .months12:
            let m = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            return calendar.date(byAdding: .month, value: -11, to: m)!
        }
    }
}

/// Ein Datenpunkt eines Diagramms. `value == nil` bedeutet „keine Daten“ (nicht 0).
public struct ChartPoint: Hashable, Sendable, Identifiable {
    public var id: Date { start }
    public var start: Date
    public var value: Double?
    public var label: String
}

public struct TrainingSummary: Hashable, Sendable {
    public var sessions: Int
    public var totalMinutes: Double
    public var totalSets: Int
    public var totalReps: Int
    public var tonnageKg: Double
    public var averageRPE: Double?
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    /// Absolvierte geplante Einheiten / geplante Einheiten im Zeitraum (nil ohne Plan).
    public var adherence: Double?
}

public struct StrengthPoint: Hashable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var maxWeightKg: Double
    public var repsAtMaxWeight: Int
}

public struct TrainingAnalytics: Sendable {
    public var calendar: Calendar
    public init(calendar: Calendar = .iso8601Monday) { self.calendar = calendar }

    func completed(_ s: [WorkoutSession]) -> [WorkoutSession] { s.filter { $0.state == .completed } }

    public func summary(_ sessions: [WorkoutSession], period: AnalyticsPeriod, endingAt end: Date, plan: TrainingPlan? = nil) -> TrainingSummary {
        let from = period.startDate(endingAt: end, calendar: calendar)
        let list = completed(sessions).filter { $0.startedAt >= from && $0.startedAt <= end }
        let rpes = list.compactMap { $0.feedback?.rpe }
        let hrs = list.compactMap(\.heartRate.averageBpm)
        var adherence: Double?
        if let plan {
            let planned = plan.allWorkouts.filter { let d = plan.date(of: $0, calendar: calendar); return d >= from && d <= end }
            if !planned.isEmpty {
                adherence = Double(planned.filter { $0.completedSessionId != nil }.count) / Double(planned.count)
            }
        }
        return TrainingSummary(
            sessions: list.count,
            totalMinutes: list.reduce(0) { $0 + $1.activeSeconds } / 60,
            totalSets: list.reduce(0) { $0 + $1.completedSetCount },
            totalReps: list.reduce(0) { $0 + $1.totalReps },
            tonnageKg: list.reduce(0) { $0 + $1.tonnageKg },
            averageRPE: rpes.isEmpty ? nil : Double(rpes.reduce(0, +)) / Double(rpes.count),
            averageHeartRate: hrs.isEmpty ? nil : hrs.reduce(0, +) / Double(hrs.count),
            maxHeartRate: list.compactMap(\.heartRate.maxBpm).max(),
            adherence: adherence)
    }

    /// Bucket-Startzeitpunkte eines Zeitraums.
    public func buckets(_ period: AnalyticsPeriod, endingAt end: Date) -> [Date] {
        let start = period.startDate(endingAt: end, calendar: calendar)
        var result: [Date] = []
        var d = start
        let comp: Calendar.Component = period.bucket == .day ? .day : (period.bucket == .week ? .weekOfYear : .month)
        while d <= end {
            result.append(d)
            d = calendar.date(byAdding: comp, value: 1, to: d)!
        }
        return result
    }

    func label(_ d: Date, _ bucket: AnalyticsPeriod.Bucket) -> String {
        let c = calendar.dateComponents([.day, .month, .weekOfYear, .year], from: d)
        switch bucket {
        case .day: return "\(c.day!).\(c.month!)."
        case .week: return "KW \(c.weekOfYear!)"
        case .month: return ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"][c.month! - 1]
        }
    }

    public enum TrainingMetric: String, CaseIterable, Sendable, Identifiable {
        case sessions, minutes, volumeReps, tonnage, averageRPE, averageHeartRate
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .sessions: return "Einheiten"
            case .minutes: return "Trainingsdauer (min)"
            case .volumeReps: return "Wiederholungen"
            case .tonnage: return "Bewegtes Gewicht (kg)"
            case .averageRPE: return "Ø Anstrengung (RPE)"
            case .averageHeartRate: return "Ø Trainingspuls (S/min)"
            }
        }
        /// Summen-Metriken zeigen 0 bei keinem Training, Mittelwerte zeigen „keine Daten“.
        var isSum: Bool { [.sessions, .minutes, .volumeReps, .tonnage].contains(self) }
    }

    public func series(_ metric: TrainingMetric, sessions: [WorkoutSession], period: AnalyticsPeriod, endingAt end: Date) -> [ChartPoint] {
        let starts = buckets(period, endingAt: end)
        let list = completed(sessions)
        return starts.enumerated().map { i, s in
            let e = i + 1 < starts.count ? starts[i + 1] : end.addingTimeInterval(1)
            let inBucket = list.filter { $0.startedAt >= s && $0.startedAt < e }
            let v: Double?
            switch metric {
            case .sessions: v = Double(inBucket.count)
            case .minutes: v = inBucket.reduce(0) { $0 + $1.activeSeconds } / 60
            case .volumeReps: v = Double(inBucket.reduce(0) { $0 + $1.totalReps })
            case .tonnage: v = inBucket.reduce(0) { $0 + $1.tonnageKg }
            case .averageRPE:
                let r = inBucket.compactMap { $0.feedback?.rpe }
                v = r.isEmpty ? nil : Double(r.reduce(0, +)) / Double(r.count)
            case .averageHeartRate:
                let h = inBucket.compactMap(\.heartRate.averageBpm)
                v = h.isEmpty ? nil : h.reduce(0, +) / Double(h.count)
            }
            return ChartPoint(start: s, value: v, label: label(s, period.bucket))
        }
    }

    /// Kraftentwicklung einer Übung: höchstes Gewicht je Einheit und die dabei erreichten Wiederholungen.
    public func strengthProgress(exerciseId: String, sessions: [WorkoutSession]) -> [StrengthPoint] {
        completed(sessions).sorted { $0.startedAt < $1.startedAt }.compactMap { s in
            let sets = s.allSets.filter { $0.exerciseId == exerciseId && $0.weightKg != nil }
            guard let maxW = sets.compactMap(\.weightKg).max() else { return nil }
            let reps = sets.filter { $0.weightKg == maxW }.map(\.achieved).max() ?? 0
            return StrengthPoint(date: s.startedAt, maxWeightKg: maxW, repsAtMaxWeight: reps)
        }
    }

    /// Vitaldaten einer Quelle, verdichtet auf Buckets (Mittelwert der Tageswerte).
    public func vitalSeries(_ type: VitalType, source: DataSource, samples: [VitalSample], period: AnalyticsPeriod,
                            endingAt end: Date, harmonizer: VitalHarmonizer) -> [ChartPoint] {
        let starts = buckets(period, endingAt: end)
        let firstDay = starts.first ?? end
        let days = (calendar.dateComponents([.day], from: firstDay, to: end).day ?? 0) + 1
        let daily = harmonizer.series(type, source: source, days: days, endingAt: end, in: samples)
        let byKey = Dictionary(uniqueKeysWithValues: daily.map { ($0.dayKey, $0.value) })
        return starts.enumerated().map { i, s in
            let e = i + 1 < starts.count ? starts[i + 1] : end.addingTimeInterval(1)
            var values: [Double] = []
            var d = s
            while d < e {
                if let v = byKey[DayKey.string(for: d, calendar: calendar)] ?? nil { values.append(v) }
                d = calendar.date(byAdding: .day, value: 1, to: d)!
            }
            return ChartPoint(start: s, value: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count), label: label(s, period.bucket))
        }
    }

    /// Quellen, für die zu einem Typ Daten existieren.
    public func availableSources(_ type: VitalType, samples: [VitalSample]) -> [DataSource] {
        Array(Set(samples.filter { $0.type == type }.map(\.source))).sorted { $0.rawValue < $1.rawValue }
    }

    /// Trainingseinheiten der laufenden Woche.
    public func sessionsThisWeek(_ sessions: [WorkoutSession], now: Date) -> [WorkoutSession] {
        let start = calendar.startOfWeek(for: now)
        return completed(sessions).filter { $0.startedAt >= start && $0.startedAt <= now }
    }
}
