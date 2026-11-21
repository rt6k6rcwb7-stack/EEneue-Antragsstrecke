import SwiftUI
import Charts
import FitnessCore

/// Interaktiver Trainingsplayer. Große Bedienelemente, wenige Berührungen.
/// Jede Aktion wird sofort lokal gesichert (Wiederherstellung nach Absturz/Neustart).
struct WorkoutPlayerView: View {
    @Environment(AppModel.self) private var model
    @State private var achieved: Int?
    @State private var showReplace = false
    @State private var showFinish = false
    @State private var finishAborted = false
    @State private var confirmAbort = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            if let run = model.run {
                content(run: run, now: context.date)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if model.tick() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            }
        }
        .sheet(isPresented: $showReplace) {
            if let ex = model.run?.currentExercise {
                NavigationStack {
                    AlternativePicker(exerciseId: ex.exerciseId) { pick in
                        let w = WeightSelector(available: model.profile.kettlebellsKg).recommended(for: pick, experience: model.profile.experience)
                        model.mutateRun { $0.replaceCurrentExercise(with: pick, weightKg: w, at: $1) }
                        showReplace = false
                    }
                }
            }
        }
        .sheet(isPresented: $showFinish) {
            NavigationStack {
                PostWorkoutFeedbackView(aborted: finishAborted) { feedback in
                    model.finishWorkout(aborted: finishAborted, feedback: feedback)
                }
            }
            .interactiveDismissDisabled()
        }
        .confirmationDialog("Training vorzeitig beenden?", isPresented: $confirmAbort, titleVisibility: .visible) {
            Button("Beenden und speichern", role: .destructive) { finishAborted = true; showFinish = true }
            Button("Weiter trainieren", role: .cancel) {}
        } message: { Text("Bereits absolvierte Sätze bleiben gespeichert.") }
    }

    @ViewBuilder
    private func content(run: WorkoutRun, now: Date) -> some View {
        VStack(spacing: 14) {
            header(run: run, now: now)
            if let alert = model.liveAlert {
                Text(alert.message)
                    .font(.callout.weight(.semibold))
                    .padding(10).frame(maxWidth: .infinity)
                    .background((alert.severity == .warning ? Theme.warning : Theme.caution).opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            }
            switch run.phase {
            case .allDone:
                allDone
            case .paused:
                pausedView(run: run, now: now)
            default:
                exerciseView(run: run, now: now)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: Kopfzeile

    private func header(run: WorkoutRun, now: Date) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text(durationText(run.elapsed(at: now))).font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    Text("Trainingsdauer").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                heartRate(run: run, now: now)
            }
            ProgressView(value: run.progress).tint(Theme.accent)
            HStack {
                Button { run.isPaused ? model.resumeWorkout() : model.pauseWorkout() } label: {
                    Label(run.isPaused ? "Fortsetzen" : "Pause", systemImage: run.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(role: .destructive) { confirmAbort = true } label: { Label("Beenden", systemImage: "stop.fill") }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }

    private func heartRate(run: WorkoutRun, now: Date) -> some View {
        let maxHR = model.profile.health.heartRateUpperLimit ?? model.profile.estimatedMaxHeartRate()
        return VStack(alignment: .trailing, spacing: 2) {
            if let hr = run.heartRate.current(at: now) {
                let zone = HeartRateZone.zone(for: hr.bpm, maxHR: model.profile.estimatedMaxHeartRate())
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(Theme.warning)
                    Text("\(Int(hr.bpm))").font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                }
                Text("S/min · \(zone.displayName)").font(.caption).foregroundStyle(Theme.secondaryText)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "heart.slash").foregroundStyle(Theme.secondaryText)
                    Text("––").font(.system(size: 34, weight: .semibold, design: .rounded))
                }
                Text(run.heartRate.points.isEmpty ? "Kein Puls (Watch?)" : "Puls-Signal unterbrochen")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            let recent = run.heartRate.window(endingAt: now, seconds: 600)
            if recent.count > 1 {
                Chart(recent, id: \.date) { p in
                    LineMark(x: .value("Zeit", p.date), y: .value("Puls", p.bpm)).interpolationMethod(.monotone)
                }
                .chartYScale(domain: 50...max(180, maxHR))
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(width: 120, height: 34)
                .accessibilityLabel("Pulsverlauf der letzten zehn Minuten")
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Übung / Pause

    @ViewBuilder
    private func exerciseView(run: WorkoutRun, now: Date) -> some View {
        if let ex = run.currentExercise, let def = model.exercise(ex.exerciseId) {
            ScrollView {
                VStack(spacing: 12) {
                    if case .resting(let until, let total) = run.phase {
                        restView(remaining: max(0, until.timeIntervalSince(now)), total: total, next: def, setNumber: run.currentSetNumber, of: ex.plannedSets)
                    } else {
                        ExerciseAnimationView(animationId: def.animation, height: 190)
                            .accessibilityHidden(true)
                        Text(ex.block.displayName.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                        Text(def.nameDE).font(.title.bold()).multilineTextAlignment(.center)
                        Text("Satz \(run.currentSetNumber) von \(ex.plannedSets)").font(.title3).foregroundStyle(Theme.secondaryText)
                        valueControls(ex: ex, def: def)
                        if let cue = def.techniqueCues.first {
                            Text("💡 \(cue)").font(.callout).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
                        }
                    }
                    if let next = run.nextExercise, let nd = model.exercise(next.exerciseId) {
                        Text("Als Nächstes: \(nd.nameDE)").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            if case .resting = run.phase {
                HStack(spacing: 12) {
                    bigButton("−15 s", systemImage: "minus", style: .secondary) { model.mutateRun { $0.adjustRest(by: -15, at: $1) } }
                    bigButton("+15 s", systemImage: "plus", style: .secondary) { model.mutateRun { $0.adjustRest(by: 15, at: $1) } }
                }
                bigButton("Pause überspringen", systemImage: "forward.fill", style: .primary) { model.mutateRun { $0.skipRest(at: $1) } }
            } else {
                bigButton("Satz erledigt", systemImage: "checkmark", style: .primary) {
                    let a = achieved
                    model.mutateRun { $0.completeSet(achieved: a, at: $1) }
                    achieved = nil
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                HStack(spacing: 12) {
                    bigButton("Überspringen", systemImage: "forward.end", style: .secondary) { achieved = nil; model.mutateRun { $0.skipExercise(at: $1) } }
                    bigButton("Ersetzen", systemImage: "arrow.triangle.2.circlepath", style: .secondary) { showReplace = true }
                }
            }
        }
    }

    private func valueControls(ex: SessionExercise, def: Exercise) -> some View {
        let value = achieved ?? ex.target
        return VStack(spacing: 10) {
            HStack(spacing: 16) {
                circleButton("minus") { achieved = max(0, value - (ex.targetKind == .reps ? 1 : 5)) }
                    .accessibilityLabel(ex.targetKind == .reps ? "Eine Wiederholung weniger" : "Fünf Sekunden weniger")
                VStack {
                    Text("\(value)").font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    Text(ex.targetKind == .reps ? (ex.perSide ? "Wdh. je Seite" : "Wiederholungen") : (ex.perSide ? "Sek. je Seite" : "Sekunden"))
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
                .frame(minWidth: 120)
                .accessibilityElement(children: .combine)
                circleButton("plus") { achieved = value + (ex.targetKind == .reps ? 1 : 5) }
                    .accessibilityLabel(ex.targetKind == .reps ? "Eine Wiederholung mehr" : "Fünf Sekunden mehr")
            }
            if def.load.kind == .kettlebell {
                HStack(spacing: 8) {
                    ForEach(model.profile.kettlebellsKg, id: \.self) { kg in
                        Button { model.mutateRun { $0.setWeight(kg, at: $1) } } label: {
                            Text(kg.kgText).font(.headline).frame(minWidth: 64, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(ex.weightKg == kg ? Theme.accent : .gray)
                        .accessibilityAddTraits(ex.weightKg == kg ? .isSelected : [])
                    }
                }
            } else if let lever = def.load.leverHint {
                Text(lever).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if value != ex.target {
                Button("Vorgabe für restliche Sätze auf \(value) setzen") { model.mutateRun { $0.setTarget(value, at: $1) }; achieved = nil }
                    .font(.footnote)
            }
        }
    }

    private func restView(remaining: Double, total: Int, next: Exercise, setNumber: Int, of sets: Int) -> some View {
        VStack(spacing: 12) {
            Text("PAUSE").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
            ZStack {
                Circle().stroke(Theme.cardHighlight, lineWidth: 14)
                Circle().trim(from: 0, to: total > 0 ? remaining / Double(total) : 0)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(durationText(remaining)).font(.system(size: 60, weight: .bold, design: .rounded).monospacedDigit())
            }
            .frame(width: 220, height: 220)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pause, noch \(Int(remaining)) Sekunden")
            Text("Danach: \(next.nameDE) – Satz \(setNumber) von \(sets)").font(.headline).multilineTextAlignment(.center)
            ExerciseAnimationView(animationId: next.animation, height: 120).accessibilityHidden(true)
        }
        .padding(.top, 8)
    }

    private func pausedView(run: WorkoutRun, now: Date) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "pause.circle").font(.system(size: 80)).foregroundStyle(Theme.accent)
            Text("Training pausiert").font(.title.bold())
            if let r = run.restRemaining(at: now), r > 0 { Text("Restpause: \(durationText(r))").foregroundStyle(Theme.secondaryText) }
            Spacer()
            bigButton("Fortsetzen", systemImage: "play.fill", style: .primary) { model.resumeWorkout() }
        }
    }

    private var allDone: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 80)).foregroundStyle(Theme.good)
            Text("Alle Übungen erledigt").font(.title.bold())
            Spacer()
            bigButton("Training abschließen", systemImage: "flag.checkered", style: .primary) { finishAborted = false; showFinish = true }
        }
    }

    // MARK: Bausteine

    enum BigStyle { case primary, secondary }

    private func bigButton(_ title: String, systemImage: String, style: BigStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(style == .primary ? .title2.bold() : .headline)
                .frame(maxWidth: .infinity, minHeight: style == .primary ? 72 : 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(style == .primary ? Theme.accent : Theme.cardHighlight)
        .foregroundStyle(style == .primary ? Color.black : Color.white)
    }

    private func circleButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.title.bold()).frame(width: 64, height: 64)
        }
        .buttonStyle(.bordered).clipShape(Circle())
    }
}
