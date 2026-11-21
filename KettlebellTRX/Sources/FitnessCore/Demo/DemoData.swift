import Foundation

/// Erzeugt AUSDRÜCKLICH GEKENNZEICHNETE Beispieldaten für Vorführungen.
/// Alle Einheiten tragen `isDemo = true`, alle Messwerte `quality = .demo`, `channel = .demo`.
/// Sie werden in der App mit „Beispieldaten“ markiert und lassen sich gesammelt löschen.
/// Deterministisch (fester Seed), damit Tests reproduzierbar sind.
public struct DemoDataGenerator: Sendable {
    struct LCG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

    public var seed: UInt64 = 42
    public init(seed: UInt64 = 42) { self.seed = seed }

    public func sessions(plan: TrainingPlan, upTo now: Date, calendar: Calendar = .iso8601Monday) -> [WorkoutSession] {
        var rng = LCG(s: seed)
        var out: [WorkoutSession] = []
        for w in plan.allWorkouts {
            let day = plan.date(of: w, calendar: calendar)
            guard day < calendar.startOfDay(for: now) else { continue }
            let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day)!
            var run = WorkoutRun.from(planned: w, now: start)
            run.start(at: start)
            var t = start
            while case .performing = run.phase {
                t = t.addingTimeInterval(40)
                run.recordHeartRate([HeartRatePoint(date: t, bpm: 95 + rng.next() * 35)])
                run.completeSet(at: t)
                t = t.addingTimeInterval(Double(run.restRemaining(at: t) ?? 0))
                run.tick(at: t)
            }
            run.finish(at: t, feedback: PostWorkoutFeedback(rpe: 5 + Int(rng.next() * 3), weightFit: .appropriate, wellbeing: .good,
                                                            note: "Beispieldaten"))
            var s = run.session
            s.isDemo = true
            out.append(s)
        }
        return out
    }

    public func vitals(days: Int, endingAt now: Date, calendar: Calendar = .iso8601Monday) -> [VitalSample] {
        var rng = LCG(s: seed &+ 7)
        var out: [VitalSample] = []
        for d in 0..<days {
            let day = calendar.date(byAdding: .day, value: -d, to: calendar.startOfDay(for: now))!
            let wake = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day)!
            let sleepStart = wake.addingTimeInterval(-7.2 * 3600)
            func add(_ t: VitalType, _ v: Double, _ src: DataSource) {
                out.append(VitalSample(type: t, value: v, start: sleepStart, end: wake, source: src, channel: .demo,
                                       sourceRecordId: "demo-\(t.rawValue)-\(src.rawValue)-\(d)", quality: .demo))
            }
            add(.restingHeartRate, 56 + rng.next() * 5, .whoop)
            add(.hrvRMSSD, 38 + rng.next() * 12, .whoop)
            add(.recoveryScore, 45 + rng.next() * 45, .whoop)
            add(.sleepDuration, 390 + rng.next() * 70, .whoop)
            add(.restingHeartRate, 57 + rng.next() * 5, .appleWatch)
            add(.hrvSDNN, 32 + rng.next() * 15, .appleWatch)
            add(.steps, 6000 + rng.next() * 6000, .garmin)
        }
        return out
    }
}
