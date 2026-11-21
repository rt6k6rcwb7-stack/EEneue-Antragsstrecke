import Foundation

public struct VitalAlert: Hashable, Sendable, Identifiable {
    public enum Severity: Int, Sendable, Comparable {
        case info = 0, caution = 1, warning = 2
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }
    public var id: String
    public var severity: Severity
    public var title: String
    public var message: String
    /// Ausdrücklicher Hinweis auf ärztliche Abklärung.
    public var suggestsMedicalCheck: Bool
}

/// Hinweise bei auffälligen Veränderungen. Die App stellt KEINE Diagnose und erteilt
/// KEINE medizinische Trainingsfreigabe.
public struct VitalAlertEvaluator: Sendable {
    public var harmonizer: VitalHarmonizer
    public var restingHRCautionDelta = 7.0
    public var restingHRWarningDelta = 10.0
    public var hrvDropRatio = 0.75
    public var shortSleepMinutes = 360.0

    public init(harmonizer: VitalHarmonizer = VitalHarmonizer()) { self.harmonizer = harmonizer }

    public func dailyAlerts(on day: Date, samples: [VitalSample]) -> [VitalAlert] {
        var alerts: [VitalAlert] = []
        let cal = harmonizer.calendar

        if let r = harmonizer.comparableReading(.restingHeartRate, on: day, in: samples) {
            let delta = r.value - r.baseline.mean
            if delta >= restingHRCautionDelta {
                // Mehrtägig erhöht?
                let elevatedDays = (0..<3).filter { off in
                    guard let d = cal.date(byAdding: .day, value: -off, to: day),
                          let v = harmonizer.series(.restingHeartRate, source: r.baseline.source, days: 1, endingAt: d, in: samples).first?.value
                    else { return false }
                    return v - r.baseline.mean >= restingHRWarningDelta
                }.count
                let persistent = elevatedDays >= 3
                alerts.append(VitalAlert(
                    id: "rhr-elevated", severity: persistent ? .warning : .caution,
                    title: "Ruhepuls erhöht",
                    message: String(format: "Ruhepuls %.0f S/min liegt %.0f über deiner Basislinie (%.0f, %@).",
                                    r.value, delta, r.baseline.mean, r.baseline.source.displayName)
                        + (persistent ? " Seit mehreren Tagen erhöht – bei Krankheitsgefühl oder Beschwerden bitte ärztlich abklären." : ""),
                    suggestsMedicalCheck: persistent))
            }
        }
        for type in [VitalType.hrvRMSSD, .hrvSDNN] {
            if let r = harmonizer.comparableReading(type, on: day, in: samples), r.value < r.baseline.median * hrvDropRatio {
                alerts.append(VitalAlert(
                    id: "hrv-low-\(type.rawValue)", severity: .caution, title: "HRV unter Basislinie",
                    message: String(format: "%@ %.0f ms, Basislinie %.0f ms (%@). Vergleich nur innerhalb derselben Quelle und Methode.",
                                    type.displayName, r.value, r.baseline.median, r.baseline.source.displayName),
                    suggestsMedicalCheck: false))
                break
            }
        }
        let sleepNights = (0..<2).compactMap { off -> Double? in
            guard let d = cal.date(byAdding: .day, value: -off, to: day) else { return nil }
            return harmonizer.resolve(.sleepDuration, dayKey: DayKey.string(for: d, calendar: cal), in: samples)?.value
        }
        if sleepNights.count == 2, sleepNights.allSatisfy({ $0 < shortSleepMinutes }) {
            alerts.append(VitalAlert(id: "sleep-short", severity: .caution, title: "Wenig Schlaf",
                                     message: "Zwei Nächte in Folge unter 6 Stunden Schlaf.", suggestsMedicalCheck: false))
        }
        return alerts.sorted { $0.severity > $1.severity }
    }

    /// Hinweis während des Trainings.
    public func workoutAlert(currentBpm: Double, profile: UserProfile, now: Date = Date()) -> VitalAlert? {
        let maxHR = profile.estimatedMaxHeartRate(on: now)
        if let limit = profile.health.heartRateUpperLimit, currentBpm > Double(limit) {
            return VitalAlert(id: "hr-limit", severity: .warning, title: "Pulsgrenze überschritten",
                              message: "Puls \(Int(currentBpm)) über deiner hinterlegten Grenze von \(limit). Tempo reduzieren und Pause verlängern.",
                              suggestsMedicalCheck: false)
        }
        if currentBpm > Double(maxHR) {
            return VitalAlert(id: "hr-above-max", severity: .warning, title: "Sehr hoher Puls",
                              message: "Puls \(Int(currentBpm)) liegt über der geschätzten Maximalfrequenz (\(maxHR)). Übung beenden und erholen. Bei Brustschmerz, Schwindel oder Atemnot Training abbrechen und ärztliche Hilfe suchen.",
                              suggestsMedicalCheck: true)
        }
        if currentBpm > 0.9 * Double(maxHR) {
            return VitalAlert(id: "hr-high", severity: .caution, title: "Hohe Intensität",
                              message: "Puls über 90 % der geschätzten Maximalfrequenz. Für dieses Programm ist eine moderate Belastung vorgesehen.",
                              suggestsMedicalCheck: false)
        }
        return nil
    }
}
