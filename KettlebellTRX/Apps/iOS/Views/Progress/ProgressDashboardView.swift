import SwiftUI
import Charts
import FitnessCore

struct ProgressDashboardView: View {
    @Environment(AppModel.self) private var model
    enum Mode: String, CaseIterable { case training = "Training", vitals = "Vitaldaten" }
    @State private var mode: Mode = .training
    @State private var period: AnalyticsPeriod = .weeks8
    @State private var metric: TrainingAnalytics.TrainingMetric = .sessions
    @State private var vitalType: VitalType = .restingHeartRate
    @State private var vitalSource: DataSource?
    @State private var strengthExercise = "kb_goblet_squat"

    private let analytics = TrainingAnalytics()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Ansicht", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                Picker("Zeitraum", selection: $period) { ForEach(AnalyticsPeriod.allCases) { Text($0.displayName).tag($0) } }
                    .pickerStyle(.segmented)
                if model.hasDemoData { HStack { DemoBadge(); Text("Diagramme enthalten Beispieldaten.").font(.footnote); Spacer() } }
                if mode == .training { trainingSection } else { vitalsSection }
            }
            .padding()
        }
        .navigationTitle("Fortschritt")
    }

    // MARK: Training

    @ViewBuilder private var trainingSection: some View {
        let s = analytics.summary(model.sessions, period: period, endingAt: Date(), plan: model.plan)
        Card(title: "Überblick \(period.displayName)", systemImage: "chart.bar") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow { stat("Einheiten", "\(s.sessions)"); stat("Dauer", "\(Int(s.totalMinutes)) min") }
                GridRow { stat("Sätze", "\(s.totalSets)"); stat("Wiederholungen", "\(s.totalReps)") }
                GridRow { stat("Bewegte Last", "\(Int(s.tonnageKg)) kg"); stat("Ø RPE", s.averageRPE.map { String(format: "%.1f", $0) } ?? "–") }
                GridRow { stat("Ø Trainingspuls", s.averageHeartRate.map { "\(Int($0))" } ?? "–"); stat("Max. Puls", s.maxHeartRate.map { "\(Int($0))" } ?? "–") }
                GridRow { stat("Regelmäßigkeit", s.adherence.map { "\(Int($0 * 100)) %" } ?? "–"); Color.clear }
            }
            Text("Bewegte Last zählt nur Kettlebell-Sätze; TRX und Eigengewicht werden nicht geschätzt.")
                .font(.caption2).foregroundStyle(Theme.secondaryText)
        }

        Card(title: metric.displayName, systemImage: "chart.xyaxis.line") {
            Picker("Kennzahl", selection: $metric) {
                ForEach(TrainingAnalytics.TrainingMetric.allCases) { Text($0.displayName).tag($0) }
            }
            let points = analytics.series(metric, sessions: model.sessions, period: period, endingAt: Date())
            if points.allSatisfy({ ($0.value ?? 0) == 0 }) {
                MissingValue(text: "Noch keine Trainingsdaten im Zeitraum")
            } else {
                Chart(points) { p in
                    if let v = p.value {
                        BarMark(x: .value("Zeitraum", p.label), y: .value(metric.displayName, v))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
                .frame(height: 200)
                .accessibilityLabel("\(metric.displayName) je Zeitabschnitt")
            }
        }

        Card(title: "Kraftentwicklung", systemImage: "dumbbell") {
            let kbExercises = model.library.exercises.filter { $0.load.kind == .kettlebell }
            Picker("Übung", selection: $strengthExercise) { ForEach(kbExercises) { Text($0.nameDE).tag($0.id) } }
            let pts = analytics.strengthProgress(exerciseId: strengthExercise, sessions: model.sessions)
                .filter { $0.date >= period.startDate(endingAt: Date(), calendar: .iso8601Monday) }
            if pts.isEmpty { MissingValue(text: "Keine Sätze mit dieser Übung im Zeitraum") } else {
                Chart(pts) { p in
                    LineMark(x: .value("Datum", p.date), y: .value("Gewicht (kg)", p.maxWeightKg))
                    PointMark(x: .value("Datum", p.date), y: .value("Gewicht (kg)", p.maxWeightKg))
                        .annotation(position: .top) { Text("\(p.repsAtMaxWeight)").font(.caption2) }
                }
                .chartYAxisLabel("kg")
                .frame(height: 180)
                Text("Punkte: höchstes Gewicht je Einheit, Beschriftung = Wiederholungen bei diesem Gewicht.")
                    .font(.caption2).foregroundStyle(Theme.secondaryText)
            }
        }

        Card(title: "Trainingshistorie", systemImage: "clock.arrow.circlepath") {
            let recent = model.sessions.filter { $0.isFinished }.sorted { $0.startedAt > $1.startedAt }.prefix(15)
            if recent.isEmpty { MissingValue(text: "Noch keine Einheiten") }
            ForEach(Array(recent)) { s in
                NavigationLink { SessionDetailView(session: s) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack { Text(s.dayType.displayName).font(.body.weight(.medium)); if s.isDemo { DemoBadge() } }
                            Text("\(s.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(Int(s.activeSeconds / 60)) min · \(s.completedSetCount) Sätze")
                                .font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        if s.state == .aborted { Text("vorzeitig").font(.caption).foregroundStyle(Theme.caution) }
                        if let r = s.feedback?.rpe { Text("RPE \(r)").font(.caption.monospacedDigit()) }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }

    // MARK: Vitaldaten

    @ViewBuilder private var vitalsSection: some View {
        let types: [VitalType] = [.restingHeartRate, .hrvRMSSD, .hrvSDNN, .sleepDuration, .recoveryScore, .strain, .steps, .heartRate]
        let sources = analytics.availableSources(vitalType, samples: model.vitals)
        let source = vitalSource.flatMap { sources.contains($0) ? $0 : nil } ?? model.settings.sourcePriorities.ranked(vitalType).first { sources.contains($0) } ?? sources.first
        Card(title: "Vitaldaten-Trend", systemImage: "waveform.path.ecg") {
            Picker("Messwert", selection: $vitalType) { ForEach(types, id: \.self) { Text($0.displayName).tag($0) } }
            if sources.count > 1 {
                Picker("Quelle", selection: Binding(get: { source }, set: { vitalSource = $0 })) {
                    ForEach(sources, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
            }
            if let source {
                let pts = analytics.vitalSeries(vitalType, source: source, samples: model.vitals, period: period, endingAt: Date(), harmonizer: model.harmonizer)
                if pts.allSatisfy({ $0.value == nil }) {
                    MissingValue(text: "Keine Messwerte von \(source.displayName) im Zeitraum")
                } else {
                    Chart(pts) { p in
                        if let v = p.value {
                            LineMark(x: .value("Datum", p.start), y: .value(vitalType.displayName, v))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Datum", p.start), y: .value(vitalType.displayName, v)).symbolSize(16)
                        }
                    }
                    .chartYAxisLabel(vitalType.unit.symbol)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                    Text("Quelle: \(source.displayName). Lücken = keine Messung (nicht interpoliert). Trends werden nur innerhalb derselben Quelle verglichen.")
                        .font(.caption2).foregroundStyle(Theme.secondaryText)
                }
            } else {
                MissingValue(text: "Für diesen Messwert ist keine Datenquelle verbunden")
            }
        }
        Card(title: "Regenerationsanalyse", systemImage: "leaf") {
            let rpe = analytics.series(.averageRPE, sessions: model.sessions, period: period, endingAt: Date())
            let rec = analytics.vitalSeries(.recoveryScore, source: .whoop, samples: model.vitals, period: period, endingAt: Date(), harmonizer: model.harmonizer)
            if rpe.allSatisfy({ $0.value == nil }) && rec.allSatisfy({ $0.value == nil }) {
                MissingValue(text: "Noch keine Belastungs- oder Recovery-Daten")
            } else {
                Chart {
                    ForEach(rec) { p in
                        if let v = p.value { LineMark(x: .value("Datum", p.start), y: .value("Wert", v / 10), series: .value("Reihe", "Recovery (÷10)")).foregroundStyle(Theme.good) }
                    }
                    ForEach(rpe) { p in
                        if let v = p.value { LineMark(x: .value("Datum", p.start), y: .value("Wert", v), series: .value("Reihe", "Ø RPE")).foregroundStyle(Theme.accent) }
                    }
                }
                .chartForegroundStyleScale(["Recovery (÷10)": Theme.good, "Ø RPE": Theme.accent])
                .frame(height: 180)
                Text("Subjektive Belastung (RPE 1–10) im Vergleich zum WHOOP Recovery Score (auf 0–10 skaliert).")
                    .font(.caption2).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    let session: WorkoutSession

    var body: some View {
        List {
            Section {
                LabeledContent("Datum", value: session.startedAt.formatted(date: .long, time: .shortened))
                LabeledContent("Aktive Dauer", value: durationText(session.activeSeconds))
                LabeledContent("Ø Puls", value: session.heartRate.averageBpm.map { "\(Int($0)) S/min" } ?? "nicht verfügbar")
                LabeledContent("Max. Puls", value: session.heartRate.maxBpm.map { "\(Int($0)) S/min" } ?? "nicht verfügbar")
                if session.heartRate.gapSeconds > 0 {
                    LabeledContent("Messlücken", value: durationText(session.heartRate.gapSeconds))
                }
                LabeledContent("In Apple Health", value: session.savedToAppleHealth ? "gespeichert" : "nein")
                if session.appliedIntensityFactor < 1 { LabeledContent("Intensität", value: "\(Int(session.appliedIntensityFactor * 100)) %") }
                if session.isDemo { DemoBadge() }
            }
            if let f = session.feedback {
                Section("Rückmeldung") {
                    LabeledContent("Anstrengung", value: "\(f.rpe)/10")
                    LabeledContent("Gewichte", value: f.weightFit.displayName)
                    LabeledContent("Befinden", value: f.wellbeing.displayName)
                    ForEach(f.painReports) { p in LabeledContent("Beschwerden", value: "\(p.region.displayName) \(p.intensity)/10") }
                    if !f.note.isEmpty { Text(f.note) }
                }
            }
            ForEach(session.exercises.filter { !$0.sets.isEmpty || $0.skipped }) { ex in
                Section(model.exercise(ex.exerciseId)?.nameDE ?? ex.exerciseId) {
                    if ex.skipped { Text("übersprungen").foregroundStyle(Theme.secondaryText) }
                    if let orig = ex.replacedExerciseId { Text("ersetzt: \(model.exercise(orig)?.nameDE ?? orig)").font(.caption) }
                    ForEach(ex.sets) { s in
                        LabeledContent("Satz \(s.setIndex + 1)",
                                       value: targetText(s.targetKind, s.achieved, perSide: s.perSide) + (s.weightKg.map { " · \($0.kgText)" } ?? ""))
                    }
                }
            }
        }
        .navigationTitle(session.dayType.displayName)
    }
}
