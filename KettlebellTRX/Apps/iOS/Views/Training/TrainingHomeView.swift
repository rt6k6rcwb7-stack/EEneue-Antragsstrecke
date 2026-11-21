import SwiftUI
import FitnessCore

/// Vor dem Training: Einheit wählen → Selbsteinschätzung → Empfehlung → Start.
struct TrainingHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedId: UUID?
    @State private var checkIn = ReadinessCheckIn()
    @State private var recommendation: Recommendation?
    @State private var confirmOverride = false

    private var selected: PlannedWorkout? {
        selectedId.flatMap { model.plan?.workout(id: $0) } ?? model.nextWorkout
    }

    var body: some View {
        Form {
            Section("Einheit") {
                if let plan = model.plan {
                    Picker("Training", selection: Binding(get: { selected?.id }, set: { selectedId = $0; recommendation = nil })) {
                        ForEach(plan.allWorkouts.filter { $0.completedSessionId == nil }.prefix(9)) { w in
                            Text("W\(w.week) \(w.weekday.shortName) – \(w.dayType.displayName)").tag(Optional(w.id))
                        }
                    }
                }
                if let w = selected {
                    Text("\(w.exercises(in: .main).count) Hauptübungen · ca. \(w.estimatedDurationSeconds() / 60) min").foregroundStyle(Theme.secondaryText)
                }
            }

            if model.profile.programStatus.isPaused {
                Section {
                    Label("Das Programm ist pausiert. Fortsetzen unter Einstellungen → Gesundheit.", systemImage: "pause.circle")
                }
            }

            Section {
                ratingRow("Schlafqualität", value: $checkIn.sleepQuality, low: "schlecht", high: "sehr gut")
                ratingRow("Energie", value: $checkIn.energy, low: "niedrig", high: "hoch")
                ratingRow("Muskelkater", value: $checkIn.soreness, low: "keiner", high: "stark")
                Toggle("Erkältung / Infektzeichen", isOn: $checkIn.hasAcuteIllnessSymptoms)
                Toggle("Fieber", isOn: $checkIn.hasFever)
                Toggle("Brustschmerz, Atemnot, Schwindel oder Herzstolpern", isOn: $checkIn.hasWarningSymptoms)
                NavigationLink {
                    RegionPicker(selection: $checkIn.currentPainRegions)
                } label: {
                    LabeledContent("Aktuelle Beschwerden", value: checkIn.currentPainRegions.isEmpty ? "keine" : checkIn.currentPainRegions.map(\.displayName).joined(separator: ", "))
                }
            } header: { Text("Wie geht es dir heute?") }

            Section {
                Button {
                    recommendation = model.evaluateReadiness(checkIn: checkIn, for: selected)
                } label: { Label("Empfehlung berechnen", systemImage: "wand.and.stars").frame(maxWidth: .infinity) }
                .controlSize(.large)
            }

            if let rec = recommendation { RecommendationSection(rec: rec) }

            if let rec = recommendation, let w = selected {
                Section {
                    if rec.kind == .noTrainingSeeDoctor || rec.kind == .extraRecovery {
                        Text(rec.kind == .noTrainingSeeDoctor ? "Heute bitte kein Training." : "Heute Regeneration – kein Training.")
                            .font(.headline).foregroundStyle(Theme.color(for: rec.kind))
                    } else if rec.kind == .mobilityInstead {
                        startButton("Regenerationseinheit starten") { model.startWorkout(w, recommendation: rec, useRecoveryInstead: true) }
                        Button("Trotzdem wie geplant (reduziert)") { confirmOverride = true }
                    } else {
                        startButton(rec.kind == .asPlanned ? "Training starten" : "Angepasst starten (\(Int(rec.intensityFactor * 100)) %)") {
                            model.startWorkout(w, recommendation: rec, painRegions: checkIn.currentPainRegions)
                        }
                    }
                }
                .disabled(model.profile.programStatus.isPaused)
                .confirmationDialog("Gegen die Empfehlung trainieren?", isPresented: $confirmOverride, titleVisibility: .visible) {
                    Button("Mit 80 % Intensität starten") {
                        var r = rec; r.kind = .reduceIntensity
                        model.startWorkout(w, recommendation: r, painRegions: checkIn.currentPainRegions)
                    }
                    Button("Abbrechen", role: .cancel) {}
                } message: { Text("Die Entscheidung wird protokolliert. Brich ab, wenn sich etwas nicht gut anfühlt.") }
            }
        }
        .navigationTitle("Training")
    }

    private func startButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "play.fill").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .listRowInsets(EdgeInsets())
    }

    private func ratingRow(_ title: String, value: Binding<Int>, low: String, high: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            Picker(title, selection: value) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }
                .pickerStyle(.segmented)
            HStack { Text(low); Spacer(); Text(high) }.font(.caption2).foregroundStyle(Theme.secondaryText)
        }
    }
}

struct RecommendationSection: View {
    let rec: Recommendation
    var body: some View {
        Section {
            Label(rec.kind.displayName, systemImage: "lightbulb").font(.headline).foregroundStyle(Theme.color(for: rec.kind))
            if let notice = rec.medicalNotice {
                Text(notice).font(.callout).foregroundStyle(Theme.warning)
            }
            ForEach(rec.hits) { h in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(h.ruleId): \(h.message)").font(.callout)
                    Text(h.evidence).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            if !rec.missingData.isEmpty {
                Text("Nicht verfügbar: " + rec.missingData.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Text(TrainingAssistant.medicalDisclaimer).font(.caption2).foregroundStyle(Theme.secondaryText)
        } header: { Text("Empfehlung") }
    }
}

struct RegionPicker: View {
    @Binding var selection: [BodyRegion]
    var body: some View {
        List(BodyRegion.allCases, id: \.self) { r in
            Button {
                if let i = selection.firstIndex(of: r) { selection.remove(at: i) } else { selection.append(r) }
            } label: {
                HStack {
                    Text(r.displayName).foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(r) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                }
            }
        }
        .navigationTitle("Beschwerden")
    }
}
