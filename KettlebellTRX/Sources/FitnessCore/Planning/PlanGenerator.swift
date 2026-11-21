import Foundation

/// Vorlage einer Übung in einer Tagesstruktur.
public struct TemplateItem: Sendable, Hashable {
    public var exerciseId: String
    public var block: BlockKind
    /// Überschreibt die Standardvorgabe der Übung (optional).
    public var target: Int?
    public var restSeconds: Int?
    /// Nur bis zu dieser Woche (z. B. Technikübungen) bzw. ab Woche.
    public var fromWeek: Int = 1
    public init(_ id: String, _ block: BlockKind, target: Int? = nil, rest: Int? = nil, fromWeek: Int = 1) {
        self.exerciseId = id; self.block = block; self.target = target; self.restSeconds = rest; self.fromWeek = fromWeek
    }
}

/// Tagesvorlagen gemäß Trainingskonzept (Mo Kraft, Mi Mobilität, Fr Ganzkörper/Kondition).
public enum DayTemplates {
    public static func items(for type: WorkoutDayType) -> [TemplateItem] {
        switch type {
        case .strength:
            return [
                .init("warm_march", .warmup, target: 60),
                .init("warm_hip_circles", .warmup, target: 30),
                .init("bw_hip_hinge_drill", .warmup, target: 10),
                .init("mob_arm_circles", .warmup, target: 30),
                .init("bw_squat", .warmup, target: 10),
                .init("kb_goblet_squat", .main, target: 10, rest: 75),
                .init("kb_deadlift", .main, target: 10, rest: 75),
                .init("trx_row", .main, target: 10, rest: 60),
                .init("trx_chest_press", .main, target: 10, rest: 60),
                .init("kb_suitcase_carry", .main, target: 30, rest: 45),
                .init("dead_bug", .main, target: 6, rest: 30),
                .init("cool_supine_hamstring_stretch", .cooldown, target: 30),
                .init("mob_hip_flexor_stretch", .cooldown, target: 30),
                .init("cool_crocodile_breathing", .cooldown, target: 60),
            ]
        case .mobility:
            return [
                .init("warm_march", .warmup, target: 60),
                .init("mob_cat_cow", .warmup, target: 8),
                .init("warm_leg_swings", .warmup, target: 10),
                .init("mob_arm_circles", .warmup, target: 30),
                .init("trx_assisted_reverse_lunge", .main, target: 8, rest: 45),
                .init("kb_halo", .main, target: 5, rest: 45),
                .init("trx_squat_to_row", .main, target: 10, rest: 45),
                .init("bird_dog", .main, target: 6, rest: 30),
                .init("trx_pallof_press", .main, target: 8, rest: 30),
                .init("bw_single_leg_balance", .main, target: 6, rest: 30),
                .init("mob_open_book", .main, target: 6, rest: 15),
                .init("mob_worlds_greatest_stretch", .main, target: 4, rest: 15),
                .init("trx_deep_squat_hold", .cooldown, target: 30),
                .init("mob_hip_90_90", .cooldown, target: 8),
                .init("cool_childs_pose", .cooldown, target: 45),
                .init("cool_crocodile_breathing", .cooldown, target: 60),
            ]
        case .conditioning:
            return [
                .init("warm_march", .warmup, target: 60),
                .init("warm_hip_circles", .warmup, target: 30),
                .init("bw_hip_hinge_drill", .warmup, target: 10),
                .init("mob_arm_circles", .warmup, target: 30),
                .init("bw_squat", .warmup, target: 10),
                .init("kb_swing", .main, target: 12, rest: 60),
                .init("trx_row", .main, target: 12, rest: 45),
                .init("kb_goblet_squat", .main, target: 10, rest: 45),
                .init("trx_chest_press", .main, target: 10, rest: 45),
                .init("kb_floor_press", .main, target: 8, rest: 45),
                .init("side_plank", .main, target: 20, rest: 30),
                .init("kb_farmers_carry", .main, target: 40, rest: 45),
                .init("trx_chest_stretch", .cooldown, target: 30),
                .init("cool_supine_hamstring_stretch", .cooldown, target: 30),
                .init("cool_thoracic_rotation_seated", .cooldown, target: 6),
                .init("cool_crocodile_breathing", .cooldown, target: 60),
            ]
        case .recovery:
            return [
                .init("warm_march", .warmup, target: 60),
                .init("mob_cat_cow", .main, target: 8, rest: 10),
                .init("mob_open_book", .main, target: 6, rest: 10),
                .init("mob_hip_90_90", .main, target: 8, rest: 10),
                .init("bird_dog", .main, target: 6, rest: 20),
                .init("dead_bug", .main, target: 6, rest: 20),
                .init("mob_worlds_greatest_stretch", .main, target: 4, rest: 10),
                .init("mob_wall_slide", .main, target: 8, rest: 10),
                .init("mob_chin_tuck", .main, target: 8, rest: 10),
                .init("cool_childs_pose", .cooldown, target: 45),
                .init("cool_crocodile_breathing", .cooldown, target: 90),
            ]
        }
    }

    /// Zuordnung der Trainingstage zu Tagestypen (bei 3 Tagen: Kraft, Mobilität, Kondition).
    public static func dayTypes(count: Int) -> [WorkoutDayType] {
        switch count {
        case ...1: return [.strength]
        case 2: return [.strength, .conditioning]
        case 3: return [.strength, .mobility, .conditioning]
        default:
            let base: [WorkoutDayType] = [.strength, .mobility, .conditioning]
            return base + Array(repeating: .recovery, count: count - 3)
        }
    }
}

/// Phasenregeln für das Haupttraining.
public struct PhaseRule: Sendable, Hashable {
    public var sets: Int
    public var repDelta: Int
    public var secondsDelta: Int
    /// −1 = eine Gewichtsstufe leichter als empfohlen, 0 = empfohlen.
    public var weightStepOffset: Int

    public static func forWeek(_ week: Int, totalWeeks: Int = 8) -> PhaseRule {
        if week == totalWeeks { return PhaseRule(sets: 2, repDelta: 0, secondsDelta: 0, weightStepOffset: 0) } // Überprüfung/Entlastung
        switch PlanPhase.forWeek(week) {
        case .technique: return PhaseRule(sets: 2, repDelta: 0, secondsDelta: 0, weightStepOffset: -1)
        case .volume: return PhaseRule(sets: 3, repDelta: 0, secondsDelta: 0, weightStepOffset: 0)
        case .progression: return PhaseRule(sets: 3, repDelta: 2, secondsDelta: 5, weightStepOffset: 0)
        case .individual: return PhaseRule(sets: 3, repDelta: 2, secondsDelta: 10, weightStepOffset: 0)
        }
    }
}

public struct PlanGenerator: Sendable {
    public var library: ExerciseLibrary
    public var profile: UserProfile
    public var totalWeeks: Int = 8

    public init(library: ExerciseLibrary, profile: UserProfile, totalWeeks: Int = 8) {
        self.library = library; self.profile = profile; self.totalWeeks = totalWeeks
    }

    public func generate(startDate: Date, recentPain: [PainReport] = [], cycleNumber: Int = 1) -> TrainingPlan {
        let days = profile.trainingDays.sorted()
        let types = DayTemplates.dayTypes(count: days.count)
        var weeks: [PlanWeek] = []
        for w in 1...totalWeeks {
            var workouts: [PlannedWorkout] = []
            for (i, day) in days.enumerated() {
                workouts.append(PlannedWorkout(week: w, weekday: day, dayType: types[i],
                                               exercises: buildExercises(for: types[i], week: w, recentPain: recentPain)))
            }
            weeks.append(PlanWeek(index: w, phase: PlanPhase.forWeek(w), workouts: workouts))
        }
        return TrainingPlan(name: "Zyklus \(cycleNumber) – Kettlebell & TRX", startDate: startDate, weeks: weeks, cycleNumber: cycleNumber)
    }

    public func buildExercises(for type: WorkoutDayType, week: Int, recentPain: [PainReport] = []) -> [PlannedExercise] {
        let filter = SafetyFilter(profile: profile, recentPain: recentPain)
        let selector = WeightSelector(available: profile.kettlebellsKg)
        let rule = PhaseRule.forWeek(week, totalWeeks: totalWeeks)
        var used = Set<String>()
        var result: [PlannedExercise] = []

        for item in DayTemplates.items(for: type) where week >= item.fromWeek {
            guard let original = library[item.exerciseId] else { continue }
            var exercise = original
            var substitutedFrom: String?
            var reason: String?
            let verdict = filter.evaluate(original)
            if verdict.level == .excluded {
                guard let sub = filter.safeSubstitute(for: original, in: library, excluding: used) else { continue }
                exercise = sub
                substitutedFrom = original.id
                reason = verdict.reasons.joined(separator: "; ")
            }
            if used.contains(exercise.id) && item.block == .main { continue }
            used.insert(exercise.id)

            let rx = exercise.defaultPrescription
            let isMain = item.block == .main
            let baseTarget = substitutedFrom == nil ? (item.target ?? rx.target) : rx.target
            var target = baseTarget
            if isMain {
                target += rx.targetKind == .reps ? rule.repDelta : rule.secondsDelta
            }
            let sets = isMain ? rule.sets : 1   // Auf-/Abwärmen: je ein Durchgang
            var rest = item.restSeconds ?? rx.restSeconds
            if type == .conditioning && isMain { rest = min(rest, 60) }

            var weight: Double?
            if exercise.load.kind == .kettlebell, let rec = selector.recommended(for: exercise, experience: profile.experience) {
                weight = rec
                if isMain && rule.weightStepOffset < 0, exercise.load.tier != .light, let lighter = selector.next(below: rec) {
                    weight = lighter
                }
            }

            result.append(PlannedExercise(
                exerciseId: exercise.id, block: item.block, sets: sets, targetKind: rx.targetKind, target: target,
                perSide: rx.perSide, weightKg: weight, restSeconds: isMain ? rest : 0,
                note: verdict.level == .caution ? verdict.reasons.joined(separator: "; ") : "",
                substitutedFrom: substitutedFrom, substitutionReason: reason))
        }
        return fitToTimeBudget(result)
    }

    /// Hält das Zeitbudget ein: zuerst Pausen im Haupttraining moderat kürzen (nicht unter 45 s),
    /// erst danach die letzte Hauptübung streichen (mind. 4 Hauptübungen bleiben).
    func fitToTimeBudget(_ list: [PlannedExercise]) -> [PlannedExercise] {
        var items = list
        let limit = profile.sessionMinutes.upperBound * 60
        func duration() -> Int { PlannedWorkout(week: 1, weekday: .monday, dayType: .strength, exercises: items).estimatedDurationSeconds() }
        for i in items.indices where duration() > limit && items[i].block == .main && items[i].restSeconds > 45 {
            items[i].restSeconds = max(45, items[i].restSeconds - 15)
        }
        while duration() > limit {
            let mains = items.indices.filter { items[$0].block == .main }
            guard mains.count > 4, let last = mains.last else { break }
            items.remove(at: last)
        }
        return items
    }
}
