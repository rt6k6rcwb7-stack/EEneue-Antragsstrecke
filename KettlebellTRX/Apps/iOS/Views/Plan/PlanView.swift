import SwiftUI
import FitnessCore

struct PlanView: View {
    @Environment(AppModel.self) private var model
    @State private var showNewCycle = false
    @State private var newStart = Calendar.iso8601Monday.startOfWeek(for: Date())

    var body: some View {
        List {
            if let plan = model.plan {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.name).font(.headline)
                        Text("Start \(plan.startDate.formatted(date: .long, time: .omitted)) · aktuelle Woche \(model.currentWeek) von \(plan.weeks.count)")
                            .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                }
                ForEach(plan.weeks, id: \.index) { week in
                    Section {
                        ForEach(week.workouts) { w in
                            NavigationLink { PlannedWorkoutDetailView(workoutId: w.id) } label: { row(w, plan: plan) }
                        }
                    } header: {
                        HStack {
                            Text("Woche \(week.index)")
                            Spacer()
                            Text(week.phase.displayName).font(.caption)
                        }
                    }
                }
            }
            Section {
                Button("Neuen 8-Wochen-Zyklus erstellen") { showNewCycle = true }
            } footer: {
                Text("Der aktuelle Plan wird archiviert. Manuelle Änderungen gelten nur für den bisherigen Plan.")
            }
        }
        .navigationTitle("Mein Trainingsplan")
        .sheet(isPresented: $showNewCycle) {
            NavigationStack {
                Form {
                    DatePicker("Startwoche", selection: $newStart, displayedComponents: .date)
                    Text("Der Plan berücksichtigt dein aktuelles Profil, Einschränkungen und Beschwerden der letzten 14 Tage.")
                        .font(.footnote)
                }
                .navigationTitle("Neuer Zyklus")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Erstellen") { model.regeneratePlan(start: Calendar.iso8601Monday.startOfWeek(for: newStart)); showNewCycle = false }
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showNewCycle = false } }
                }
            }
        }
    }

    private func row(_ w: PlannedWorkout, plan: TrainingPlan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: w.completedSessionId != nil ? "checkmark.circle.fill" : icon(w.dayType))
                .font(.title3)
                .foregroundStyle(w.completedSessionId != nil ? Theme.good : Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.dayType.displayName).font(.body.weight(.medium))
                Text("\(w.weekday.displayName), \(plan.date(of: w).formatted(.dateTime.day().month()))  ·  ca. \(w.estimatedDurationSeconds() / 60) min")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }

    private func icon(_ t: WorkoutDayType) -> String {
        switch t {
        case .strength: return "dumbbell"
        case .mobility: return "figure.flexibility"
        case .conditioning: return "flame"
        case .recovery: return "leaf"
        }
    }
}

struct PlannedWorkoutDetailView: View {
    @Environment(AppModel.self) private var model
    let workoutId: UUID
    @State private var editing: PlannedExercise?

    var workout: PlannedWorkout? { model.plan?.workout(id: workoutId) }

    var body: some View {
        List {
            if let w = workout {
                ForEach(BlockKind.allCases, id: \.self) { block in
                    let items = w.exercises(in: block)
                    if !items.isEmpty {
                        Section(block.displayName) {
                            ForEach(items) { pe in
                                Button { editing = pe } label: { PlannedExerciseRow(item: pe) }
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                Section {
                    Text("Tippe auf eine Übung, um Sätze, Wiederholungen, Gewicht oder Pause anzupassen oder sie zu ersetzen.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .navigationTitle(workout?.dayType.displayName ?? "Einheit")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { pe in
            if let w = workout { NavigationStack { PlannedExerciseEditor(item: pe, workout: w) } }
        }
    }
}

struct PlannedExerciseRow: View {
    @Environment(AppModel.self) private var model
    let item: PlannedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(model.exercise(item.exerciseId)?.nameDE ?? item.exerciseId).font(.body.weight(.medium))
                if item.userModified { Image(systemName: "pencil.circle").foregroundStyle(Theme.accent).accessibilityLabel("manuell angepasst") }
            }
            Text("\(item.sets) × \(targetText(item.targetKind, item.target, perSide: item.perSide))"
                 + (item.weightKg.map { " · \($0.kgText)" } ?? "")
                 + (item.restSeconds > 0 ? " · Pause \(item.restSeconds) s" : ""))
                .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondaryText)
            if let from = item.substitutedFrom {
                Text("Ersetzt \(model.exercise(from)?.nameDE ?? from): \(item.substitutionReason ?? "")")
                    .font(.caption).foregroundStyle(Theme.caution)
            }
            if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(Theme.secondaryText) }
        }
    }
}

struct PlannedExerciseEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var item: PlannedExercise
    let workout: PlannedWorkout
    @State private var showReplace = false

    init(item: PlannedExercise, workout: PlannedWorkout) {
        _item = State(initialValue: item)
        self.workout = workout
    }

    var body: some View {
        Form {
            Section(model.exercise(item.exerciseId)?.nameDE ?? item.exerciseId) {
                Stepper("Sätze: \(item.sets)", value: $item.sets, in: 1...6)
                Stepper(item.targetKind == .reps ? "Wiederholungen: \(item.target)" : "Dauer: \(item.target) s",
                        value: $item.target, in: 1...(item.targetKind == .reps ? 30 : 180), step: item.targetKind == .reps ? 1 : 5)
                Stepper("Pause: \(item.restSeconds) s", value: $item.restSeconds, in: 0...240, step: 15)
                if model.exercise(item.exerciseId)?.load.kind == .kettlebell {
                    Picker("Gewicht", selection: Binding(get: { item.weightKg ?? 0 }, set: { item.weightKg = $0 })) {
                        ForEach(model.profile.kettlebellsKg, id: \.self) { Text($0.kgText).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                TextField("Notiz", text: $item.note, axis: .vertical)
            }
            Section {
                Button("Übung ersetzen …") { showReplace = true }
            }
        }
        .navigationTitle("Übung anpassen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { model.updatePlannedExercise(item, in: workout); dismiss() }
            }
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        }
        .sheet(isPresented: $showReplace) {
            NavigationStack {
                AlternativePicker(exerciseId: item.exerciseId) { ex in
                    model.replacePlannedExercise(item, with: ex, in: workout)
                    showReplace = false
                    dismiss()
                }
            }
        }
    }
}

/// Auswahl sicherer Alternativen (Einschränkungen werden berücksichtigt).
struct AlternativePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let exerciseId: String
    var onPick: (Exercise) -> Void

    var body: some View {
        let filter = SafetyFilter(profile: model.profile, recentPain: model.painReports.filter { Date().timeIntervalSince($0.date) < 7 * 86400 })
        let options = model.library.alternatives(for: exerciseId)
        List(options) { ex in
            let verdict = filter.evaluate(ex)
            Button { onPick(ex) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.nameDE).foregroundStyle(verdict.level == .excluded ? Theme.secondaryText : .primary)
                    Text("\(ex.category.displayName) · \(ex.difficulty.displayName)").font(.caption).foregroundStyle(Theme.secondaryText)
                    if !verdict.reasons.isEmpty {
                        Text(verdict.reasons.joined(separator: "; ")).font(.caption)
                            .foregroundStyle(verdict.level == .excluded ? Theme.warning : Theme.caution)
                    }
                }
            }
            .disabled(verdict.level == .excluded)
        }
        .navigationTitle("Alternative wählen")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
    }
}
