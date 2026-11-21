import SwiftUI
import FitnessCore

/// Einrichtungsassistent beim ersten Start – jedes Familienmitglied richtet die App auf seinem
/// eigenen iPhone ein. Alle Angaben bleiben auf diesem Gerät und sind später änderbar.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var p = UserProfile.blank()
    @State private var screening = Set<HealthScreening.Question>()
    @State private var youthConfirmed = false
    @State private var readHealth = true
    @State private var saveWorkouts = false

    private let steps = ["Willkommen", "Über dich", "Ausrüstung", "Trainingsrhythmus", "Gesundheit", "Datenschutz"]
    private static let bellOptions: [Double] = [4, 6, 8, 10, 12, 14, 16, 20, 24, 28, 32]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(steps.count))
                    .padding(.horizontal).padding(.top, 8)
                    .accessibilityLabel("Schritt \(step + 1) von \(steps.count)")
                Form { content }
                    .scrollContentBackground(.hidden)
                navigation
            }
            .background(Theme.background)
            .navigationTitle(steps[step])
        }
    }

    // MARK: Schritte

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: aboutYou
        case 2: equipment
        case 3: rhythm
        case 4: health
        default: privacy
        }
    }

    private var welcome: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "figure.strengthtraining.functional").font(.system(size: 54)).foregroundStyle(Theme.accent)
                Text("Kettlebell & TRX Training").font(.title.bold())
                Text("Dein persönlicher Trainingsplan für Kraft, Beweglichkeit und Stabilität – mit Kettlebell, TRX und Eigengewicht.")
                Label("Diese App nutzt jede Person auf ihrem eigenen iPhone.", systemImage: "person")
                Label("Deine Angaben und Gesundheitsdaten bleiben auf diesem Gerät – auch andere Familienmitglieder sehen sie nicht.", systemImage: "lock.shield")
                Label("Keine Werbung, kein Konto, keine Cloud.", systemImage: "hand.raised")
                Text("Die Einrichtung dauert etwa zwei Minuten.").font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .padding(.vertical, 8)
        }
    }

    private var aboutYou: some View {
        Group {
            Section {
                TextField("Vorname (für die Begrüßung)", text: $p.displayName)
                    .textContentType(.givenName)
                Stepper("Geburtsjahr: \(String(p.birthYear))", value: $p.birthYear, in: 1930...Calendar.current.component(.year, from: Date()) - 10)
                Stepper("Körpergröße: \(Int(p.heightCm)) cm", value: $p.heightCm, in: 120...220)
                Stepper("Körpergewicht: \(p.bodyWeightKg.map { "\(Int($0)) kg" } ?? "optional")",
                        onIncrement: { p.bodyWeightKg = (p.bodyWeightKg ?? 70) + 1 },
                        onDecrement: { p.bodyWeightKg = max(30, (p.bodyWeightKg ?? 70) - 1) })
            }
            Section("Erfahrung mit Kettlebells") {
                Picker("Erfahrung", selection: $p.experience) {
                    ForEach(ExperienceLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.inline).labelsHidden()
            }
            if p.age() < UserProfile.minimumAge {
                Section {
                    Text("Das Programm ist für Erwachsene ausgelegt. Unter \(UserProfile.minimumAge) Jahren bitte nur mit Anleitung durch Eltern oder Trainer und ohne schwere Zusatzgewichte trainieren.")
                        .foregroundStyle(Theme.caution)
                    Toggle("Ein Erwachsener begleitet das Training", isOn: $youthConfirmed)
                }
            }
        }
    }

    private var equipment: some View {
        Group {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 10) {
                    ForEach(Self.bellOptions, id: \.self) { kg in
                        let on = p.kettlebellsKg.contains(kg)
                        Button {
                            if on { p.kettlebellsKg.removeAll { $0 == kg } } else { p.kettlebellsKg.append(kg); p.kettlebellsKg.sort() }
                        } label: {
                            Text(kg.kgText).font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                                .background(on ? Theme.accent : Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(on ? Color.black : Color.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            } header: { Text("Welche Kettlebells hast du?") } footer: {
                Text(p.kettlebellsKg.isEmpty ? "Ohne Kettlebell werden passende Übungen mit TRX oder Eigengewicht gewählt." : "Ausgewählt: \(p.kettlebellsKg.map(\.kgText).joined(separator: ", "))")
            }
            Section {
                Toggle("TRX-Schlingentrainer vorhanden", isOn: $p.hasTRX)
            }
        }
    }

    private var rhythm: some View {
        Group {
            Section {
                ForEach(Weekday.allCases, id: \.self) { d in
                    Toggle(d.displayName, isOn: Binding(get: { p.trainingDays.contains(d) }, set: { on in
                        if on { p.trainingDays.append(d); p.trainingDays.sort() } else { p.trainingDays.removeAll { $0 == d } }
                    }))
                }
            } header: { Text("Trainingstage") } footer: {
                Text("Empfohlen: 3 Tage mit mindestens einem Ruhetag dazwischen, z. B. Mo/Mi/Fr.")
            }
            Section("Dauer pro Einheit") {
                Picker("Dauer", selection: Binding(get: { p.sessionMinutes.upperBound }, set: { p.sessionMinutes = max(15, $0 - 10)...$0 })) {
                    ForEach([25, 30, 40, 50], id: \.self) { Text("bis \($0) min").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Sportarten (optional)") {
                TextField("z. B. Golf, Tennis, Laufen", text: Binding(
                    get: { p.sports.joined(separator: ", ") },
                    set: { p.sports = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
            }
        }
    }

    private var health: some View {
        Group {
            Section {
                ForEach(HealthScreening.Question.allCases, id: \.self) { q in
                    Toggle(isOn: Binding(get: { screening.contains(q) }, set: { on in
                        if on { screening.insert(q) } else { screening.remove(q) }
                    })) { Text(q.text).font(.callout) }
                }
            } header: { Text("Kurzer Gesundheits-Check") } footer: {
                Text("Freiwillig und nur auf diesem Gerät gespeichert. Die App stellt keine Diagnose.")
            }
            let s = HealthScreening(yes: screening)
            if !s.notices.isEmpty {
                Section {
                    ForEach(s.notices, id: \.self) { Label($0, systemImage: "stethoscope").font(.callout) }
                    Text("Die App wählt bis dahin vorsichtige Einstellungen (z. B. keine Swings, Pulswarnung). Du kannst sie später unter Einstellungen → Gesundheit ändern.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private var privacy: some View {
        Group {
            Section {
                Toggle("Apple Health lesen (Ruhepuls, HRV, Schlaf, Aktivität)", isOn: $readHealth)
                Toggle("Trainings in Apple Health speichern", isOn: $saveWorkouts)
            } header: { Text("Apple Health") } footer: {
                Text("Du kannst das jederzeit in den Einstellungen und in der Health-App ändern. Die Daten bleiben auf deinem iPhone.")
            }
            Section("Zusammenfassung") {
                LabeledContent("Name", value: p.displayName.isEmpty ? "–" : p.displayName)
                LabeledContent("Alter", value: "\(p.age()) Jahre")
                LabeledContent("Kettlebells", value: p.kettlebellsKg.isEmpty ? "keine" : p.kettlebellsKg.map(\.kgText).joined(separator: ", "))
                LabeledContent("TRX", value: p.hasTRX ? "ja" : "nein")
                LabeledContent("Training", value: "\(p.trainingDays.map(\.shortName).joined(separator: "/")) · bis \(p.sessionMinutes.upperBound) min")
            }
            Section {
                Text(TrainingAssistant.medicalDisclaimer).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: Navigation

    private var canContinue: Bool {
        switch step {
        case 1: return p.age() >= UserProfile.minimumAge || youthConfirmed
        case 2: return !p.kettlebellsKg.isEmpty || p.hasTRX
        case 3: return !p.trainingDays.isEmpty
        default: return true
        }
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button { withAnimation { step -= 1 } } label: { Text("Zurück").frame(maxWidth: .infinity, minHeight: 50) }
                    .buttonStyle(.bordered)
            }
            Button {
                if step < steps.count - 1 { withAnimation { step += 1 } } else { finish() }
            } label: {
                Text(step < steps.count - 1 ? "Weiter" : "Plan erstellen und loslegen")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canContinue)
        }
        .padding()
    }

    private func finish() {
        var profile = p
        let s = HealthScreening(yes: screening)
        s.apply(to: &profile)
        profile.screening = s
        profile.sessionsPerWeek = profile.trainingDays.count
        profile.consents.readAppleHealth = readHealth
        profile.consents.saveWorkoutsToAppleHealth = saveWorkouts
        profile.goals = TrainingGoal.allCases
        model.completeOnboarding(profile)
        if readHealth || saveWorkouts { Task { await model.connectAppleHealth() } }
    }
}
