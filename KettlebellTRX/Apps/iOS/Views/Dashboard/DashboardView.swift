import SwiftUI
import FitnessCore

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    var openTraining: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if model.hasDemoData {
                    HStack { DemoBadge(); Text("Es sind Beispieldaten geladen.").font(.footnote); Spacer() }
                }
                statusBanner
                nextWorkoutCard
                weekCard
                vitalsCard
                alertsCard
                proposalsCard
            }
            .padding()
        }
        .navigationTitle(model.profile.displayName.isEmpty ? "Heute" : "Hallo, \(model.profile.displayName)")
        .refreshable { await model.syncNow() }
    }

    @ViewBuilder private var statusBanner: some View {
        switch model.profile.programStatus {
        case .paused(let reason, let since, _):
            Card(title: "Programm pausiert", systemImage: "pause.circle") {
                Text("\(reason.displayName) seit \(since.formatted(date: .abbreviated, time: .omitted)).")
                Text("Fortsetzen unter Einstellungen → Gesundheit.").font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        case .returning(let reason, _):
            Card(title: "Schonender Wiedereinstieg", systemImage: "tortoise") {
                Text("Nach \(reason.displayName): Die App empfiehlt keine Rückkehr zu intensivem Training. Steigere nur, wenn du dich gesund fühlst – im Zweifel nach ärztlicher Rücksprache.")
                    .font(.callout)
            }
        case .active: EmptyView()
        }
    }

    private var nextWorkoutCard: some View {
        Card(title: "Nächstes Training", systemImage: "figure.strengthtraining.functional") {
            if let w = model.nextWorkout, let plan = model.plan {
                let date = plan.date(of: w)
                VStack(alignment: .leading, spacing: 6) {
                    Text(w.dayType.displayName).font(.title2.bold())
                    Text("\(w.weekday.displayName), \(date.formatted(date: .abbreviated, time: .omitted)) · Woche \(w.week) – \(PlanPhase.forWeek(w.week).displayName)")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    Text("ca. \(w.estimatedDurationSeconds() / 60) min · \(w.exercises(in: .main).count) Hauptübungen")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                Button(action: openTraining) {
                    Label("Zum Training", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Text("Der aktuelle Zyklus ist abgeschlossen.")
                NavigationLink("Neuen Zyklus planen") { PlanView() }
            }
        }
    }

    private var weekCard: some View {
        let analytics = TrainingAnalytics()
        let thisWeek = analytics.sessionsThisWeek(model.sessions, now: Date())
        let planned = model.plan?.weeks.first { $0.index == model.currentWeek }?.workouts ?? []
        return Card(title: "Diese Woche", systemImage: "calendar") {
            HStack(spacing: 10) {
                ForEach(planned) { w in
                    VStack(spacing: 6) {
                        Image(systemName: w.completedSessionId != nil ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(w.completedSessionId != nil ? Theme.good : Theme.secondaryText)
                        Text(w.weekday.shortName).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(w.weekday.displayName): \(w.completedSessionId != nil ? "erledigt" : "offen")")
                }
            }
            let minutes = thisWeek.reduce(0) { $0 + $1.activeSeconds } / 60
            Text("\(thisWeek.count) Einheiten · \(Int(minutes)) min aktiv").font(.subheadline).foregroundStyle(Theme.secondaryText)
            ProgressView(value: Double(min(planned.filter { $0.completedSessionId != nil }.count, max(planned.count, 1))),
                         total: Double(max(planned.count, 1)))
        }
    }

    private var vitalsCard: some View {
        let h = model.harmonizer
        let today = DayKey.string(for: Date())
        let rows: [VitalType] = [.recoveryScore, .restingHeartRate, .hrvRMSSD, .hrvSDNN, .sleepDuration]
        return Card(title: "Regeneration heute", systemImage: "leaf") {
            ForEach(rows, id: \.self) { type in
                HStack {
                    Label(type.displayName, systemImage: Self.icon(type))
                    Spacer()
                    if let v = h.resolve(type, dayKey: today, in: model.vitals) {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                if v.quality == .demo { DemoBadge() }
                                Text(format(v.value, type)).font(.headline.monospacedDigit())
                            }
                            Text(v.source.displayName + (v.quality == .calibrating ? " · kalibriert noch" : ""))
                                .font(.caption2).foregroundStyle(Theme.secondaryText)
                        }
                    } else {
                        MissingValue(text: "nicht verfügbar")
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text("Fehlende Werte werden nicht geschätzt. HRV-Werte unterschiedlicher Messmethoden (SDNN/RMSSD) werden getrennt dargestellt.")
                .font(.caption2).foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder private var alertsCard: some View {
        let alerts = model.dailyAlerts
        if !alerts.isEmpty {
            Card(title: "Auffälligkeiten", systemImage: "exclamationmark.triangle") {
                ForEach(alerts) { a in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(a.title).font(.headline).foregroundStyle(a.severity == .warning ? Theme.warning : Theme.caution)
                        Text(a.message).font(.callout)
                    }
                }
                Text(TrainingAssistant.medicalDisclaimer).font(.caption2).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    @ViewBuilder private var proposalsCard: some View {
        let proposals = model.progressionProposals
        if !proposals.isEmpty {
            Card(title: "Vorgeschlagene Anpassungen", systemImage: "slider.horizontal.3") {
                ForEach(proposals) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.exercise(p.exerciseId)?.nameDE ?? p.exerciseId).font(.headline)
                        Text("\(p.summary) ab Woche \(p.fromWeek)").font(.subheadline)
                        Text(p.reason).font(.caption).foregroundStyle(Theme.secondaryText)
                        Button("Übernehmen") { model.apply(p) }.buttonStyle(.bordered)
                    }
                    Divider()
                }
                Text("Anpassungen werden nur nach deiner Bestätigung übernommen.").font(.caption2).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    static func icon(_ t: VitalType) -> String {
        switch t {
        case .recoveryScore: return "heart.circle"
        case .restingHeartRate, .heartRate: return "heart"
        case .hrvRMSSD, .hrvSDNN: return "waveform.path.ecg"
        case .sleepDuration, .sleepDeep, .sleepREM, .sleepLight, .sleepAwake: return "bed.double"
        case .steps: return "figure.walk"
        default: return "chart.line.uptrend.xyaxis"
        }
    }

    private func format(_ v: Double, _ t: VitalType) -> String {
        switch t.unit {
        case .minutes: return String(format: "%d:%02d h", Int(v) / 60, Int(v) % 60)
        case .percent: return "\(Int(v.rounded())) %"
        default: return "\(Int(v.rounded())) \(t.unit.symbol)"
        }
    }
}
