import SwiftUI
import FitnessCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Persönlich") {
                NavigationLink { ProfileEditView() } label: { Label("Persönliches Profil", systemImage: "person.crop.circle") }
                NavigationLink { GoalsView() } label: { Label("Trainingsziele", systemImage: "target") }
                NavigationLink { HealthSettingsView() } label: { Label("Gesundheit & Einschränkungen", systemImage: "cross.case") }
            }
            Section("Daten") {
                NavigationLink { DevicesView() } label: { Label("Geräteverbindungen", systemImage: "applewatch.radiowaves.left.and.right") }
                NavigationLink { SourcePriorityView() } label: { Label("Datenquellen & Prioritäten", systemImage: "arrow.up.arrow.down") }
                NavigationLink { PrivacyView() } label: { Label("Datenschutz, Export & Löschen", systemImage: "lock.shield") }
            }
            Section("Training") {
                Toggle("Bildschirm während des Trainings an", isOn: Binding(get: { model.settings.keepScreenOnDuringWorkout },
                                                                          set: { var s = model.settings; s.keepScreenOnDuringWorkout = $0; model.updateSettings(s) }))
            }
            Section {
                Text("Kettlebell & TRX Training · Version 1.0\n\(TrainingAssistant.medicalDisclaimer)")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        .navigationTitle("Einstellungen")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
    }
}

struct ProfileEditView: View {
    @Environment(AppModel.self) private var model
    @State private var p: UserProfile = .initial()
    @State private var loaded = false
    @State private var newBell = 20.0
    @State private var sportsText = ""

    var body: some View {
        Form {
            Section("Person") {
                TextField("Name (optional)", text: $p.displayName)
                Stepper("Geburtsjahr: \(String(p.birthYear))", value: $p.birthYear, in: 1930...2010)
                Stepper("Körpergröße: \(Int(p.heightCm)) cm", value: $p.heightCm, in: 140...220)
                Stepper("Körpergewicht: \(p.bodyWeightKg.map { "\(Int($0)) kg" } ?? "nicht angegeben")",
                        onIncrement: { p.bodyWeightKg = (p.bodyWeightKg ?? 85) + 1 }, onDecrement: { p.bodyWeightKg = max(40, (p.bodyWeightKg ?? 85) - 1) })
                Picker("Erfahrung", selection: $p.experience) { ForEach(ExperienceLevel.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                TextField("Sportarten (kommagetrennt)", text: $sportsText)
                LabeledContent("Geschätzte max. Herzfrequenz", value: "\(p.estimatedMaxHeartRate()) S/min (Schätzung)")
            }
            Section("Ausrüstung") {
                ForEach(p.kettlebellsKg, id: \.self) { kg in Text("Kettlebell \(kg.kgText)") }
                    .onDelete { p.kettlebellsKg.remove(atOffsets: $0) }
                HStack {
                    Stepper("Neue: \(newBell.kgText)", value: $newBell, in: 4...48, step: 2)
                    Button("Hinzufügen") { if !p.kettlebellsKg.contains(newBell) { p.kettlebellsKg.append(newBell); p.kettlebellsKg.sort() } }
                }
                Toggle("TRX-Schlingentrainer vorhanden", isOn: $p.hasTRX)
            }
            Section("Trainingsrhythmus") {
                ForEach(Weekday.allCases, id: \.self) { d in
                    Toggle(d.displayName, isOn: Binding(get: { p.trainingDays.contains(d) }, set: { on in
                        if on { p.trainingDays.append(d); p.trainingDays.sort() } else { p.trainingDays.removeAll { $0 == d } }
                    }))
                }
                Stepper("Dauer bis \(p.sessionMinutes.upperBound) min", value: Binding(
                    get: { p.sessionMinutes.upperBound },
                    set: { p.sessionMinutes = min(p.sessionMinutes.lowerBound, $0)...$0 }), in: 15...75, step: 5)
            }
            Section {
                Button("Sichern") { save(regenerate: false) }
                Button("Sichern und Plan ab dieser Woche neu erstellen") { save(regenerate: true) }
            } footer: {
                Text("Geänderte Ausrüstung, Trainingstage oder Dauer wirken sich erst nach Neuerstellung des Plans aus.")
            }
        }
        .navigationTitle("Profil")
        .onAppear {
            guard !loaded else { return }
            p = model.profile; sportsText = p.sports.joined(separator: ", "); loaded = true
        }
    }

    private func save(regenerate: Bool) {
        p.sports = sportsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if p.trainingDays.isEmpty { p.trainingDays = [.monday, .wednesday, .friday] }
        p.sessionsPerWeek = p.trainingDays.count
        model.updateProfile(p)
        if regenerate { model.regeneratePlan(start: Calendar.iso8601Monday.startOfWeek(for: Date())) }
    }
}

struct GoalsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List(TrainingGoal.allCases, id: \.self) { g in
            Toggle(g.displayName, isOn: Binding(get: { model.profile.goals.contains(g) }, set: { on in
                var p = model.profile
                if on { p.goals.append(g) } else { p.goals.removeAll { $0 == g } }
                model.updateProfile(p)
            }))
        }
        .navigationTitle("Trainingsziele")
    }
}

struct HealthSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newRegion: BodyRegion = .lumbarSpine
    @State private var newSeverity: RestrictionSeverity = .mild
    @State private var newNote = ""
    @State private var painRegion: BodyRegion = .shoulder
    @State private var painValue = 3
    @State private var pauseReason: PauseReason = .illness
    @State private var confirmResume = false

    var body: some View {
        Form {
            Section {
                Text("Alle Angaben sind freiwillig und bleiben auf diesem Gerät. Die App stellt keine Diagnosen und erteilt keine Trainingsfreigabe.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            programSection
            Section("Sicherheitseinstellungen") {
                toggle("Kardiovaskuläre Einschränkung bekannt", \.hasCardiovascularRestriction)
                Stepper("Pulsobergrenze: \(model.profile.health.heartRateUpperLimit.map { "\($0) S/min" } ?? "keine")",
                        onIncrement: { setLimit((model.profile.health.heartRateUpperLimit ?? 140) + 5) },
                        onDecrement: { setLimit((model.profile.health.heartRateUpperLimit ?? 140) - 5) })
                if model.profile.health.heartRateUpperLimit != nil { Button("Pulsobergrenze entfernen") { setLimit(nil) } }
                toggle("Überkopfbelastung vermeiden", \.avoidOverheadLoading)
                toggle("Hüftbeuge-Technik für Swings sicher (bestätigt)", \.ballisticTechniqueConfirmed)
                VStack(alignment: .leading) {
                    Text("Allgemeine Intensität: \(Int(model.profile.health.intensityFactor * 100)) %")
                    Slider(value: Binding(get: { model.profile.health.intensityFactor }, set: { v in
                        var p = model.profile; p.health.intensityFactor = (v * 20).rounded() / 20; model.updateProfile(p)
                    }), in: 0.6...1.0)
                }
            }
            Section("Körperliche Einschränkungen") {
                ForEach(model.profile.restrictions) { r in
                    VStack(alignment: .leading) {
                        Text("\(r.region.displayName) – \(r.severity.displayName)")
                        if !r.note.isEmpty { Text(r.note).font(.caption).foregroundStyle(Theme.secondaryText) }
                    }
                }
                .onDelete { idx in var p = model.profile; p.restrictions.remove(atOffsets: idx); model.updateProfile(p) }
                Picker("Bereich", selection: $newRegion) { ForEach(BodyRegion.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                Picker("Ausprägung", selection: $newSeverity) { ForEach(RestrictionSeverity.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                TextField("Notiz", text: $newNote)
                Button("Einschränkung hinzufügen") {
                    var p = model.profile
                    p.restrictions.append(PhysicalRestriction(region: newRegion, severity: newSeverity, note: newNote))
                    model.updateProfile(p); newNote = ""
                }
            }
            Section {
                Picker("Bereich", selection: $painRegion) { ForEach(BodyRegion.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                Stepper("Stärke: \(painValue)/10", value: $painValue, in: 0...10)
                Button("Beschwerde dokumentieren") { model.addPain(PainReport(region: painRegion, intensity: painValue)) }
                ForEach(model.painReports.sorted { $0.date > $1.date }.prefix(20)) { p in
                    LabeledContent("\(p.date.formatted(date: .abbreviated, time: .omitted)) · \(p.region.displayName)", value: "\(p.intensity)/10")
                }
                .onDelete { idx in
                    let sorted = model.painReports.sorted { $0.date > $1.date }
                    idx.forEach { model.deletePain(sorted[$0].id) }
                }
            } header: { Text("Schmerz- und Beschwerdeprotokoll") } footer: {
                Text("Beschwerden ≥ 5/10 führen 7 Tage lang zum Ersatz belastender Übungen. Bei starken, anhaltenden oder ausstrahlenden Schmerzen bitte ärztlich abklären.")
            }
        }
        .navigationTitle("Gesundheit")
    }

    @ViewBuilder private var programSection: some View {
        Section("Trainingsprogramm") {
            switch model.profile.programStatus {
            case .active:
                Picker("Grund", selection: $pauseReason) { ForEach(PauseReason.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                Button("Programm pausieren") { model.setProgramStatus(.paused(reason: pauseReason, since: Date(), note: "")) }
            case .paused(let reason, let since, _):
                Text("Pausiert seit \(since.formatted(date: .abbreviated, time: .omitted)) (\(reason.displayName)).")
                Button("Training wieder aufnehmen") {
                    model.setProgramStatus(reason.requiresCautiousReturn ? .returning(after: reason, since: Date()) : .active)
                }
                if reason == .feverishIllness {
                    Text("Nach fieberhaften Erkrankungen startet die App im schonenden Wiedereinstieg und empfiehlt keine Rückkehr zu intensivem Training.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            case .returning(let reason, let since):
                Text("Schonender Wiedereinstieg seit \(since.formatted(date: .abbreviated, time: .omitted)) nach \(reason.displayName).")
                Button("Wiedereinstieg beenden …") { confirmResume = true }
                    .confirmationDialog("Normales Training wieder aufnehmen?", isPresented: $confirmResume, titleVisibility: .visible) {
                        Button("Ich bin beschwerdefrei – ggf. ärztlich abgeklärt") { model.setProgramStatus(.active) }
                        Button("Abbrechen", role: .cancel) {}
                    } message: { Text("Diese Entscheidung triffst du selbst. Die App leitet aus Vitaldaten keine Freigabe ab.") }
            }
        }
    }

    private func toggle(_ title: String, _ kp: WritableKeyPath<HealthSettings, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { model.profile.health[keyPath: kp] }, set: { v in
            var p = model.profile; p.health[keyPath: kp] = v; model.updateProfile(p)
        }))
    }

    private func setLimit(_ v: Int?) { var p = model.profile; p.health.heartRateUpperLimit = v.map { min(max($0, 90), 200) }; model.updateProfile(p) }
}

struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @State private var whoopClientId = ""
    @State private var whoopRedirect = "kbtrx://oauth/whoop"
    @State private var whoopBroker = ""
    @State private var revokeKind: IntegrationKind?
    @State private var report: SourceAvailabilityReport?

    var body: some View {
        Form {
            Section {
                deviceHeader(.appleHealth)
                if model.device(.appleHealth).status.isUsable == false {
                    Button("Mit Apple Health verbinden") { Task { await model.connectAppleHealth() } }
                }
                Toggle("Abgeschlossene Workouts in Apple Health speichern", isOn: Binding(get: { model.profile.consents.saveWorkoutsToAppleHealth }, set: { v in
                    var p = model.profile; p.consents.saveWorkoutsToAppleHealth = v; model.updateProfile(p)
                    if v { Task { await model.connectAppleHealth() } }
                }))
            } header: { Text("Apple Health") } footer: {
                Text("Gelesen werden nur: Ruhepuls, HRV (SDNN), Schlaf, aktive Energie, Schritte, Atemfrequenz, Sauerstoffsättigung, Workouts.")
            }

            Section {
                deviceHeader(.appleWatch)
                Text("Starte ein Training am iPhone – die Watch-App öffnet sich automatisch und überträgt den Live-Puls (Workout Mirroring). Bei Verbindungsabbruch zeichnet die Watch weiter auf und überträgt die Daten danach.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            } header: { Text("Apple Watch") }

            Section {
                deviceHeader(.garminViaHealth)
                Toggle("Garmin-Daten aus Apple Health nutzen", isOn: Binding(get: { model.device(.garminViaHealth).isEnabled },
                                                                          set: { model.setDevice(.garminViaHealth, enabled: $0) }))
                Button("Verfügbare Garmin-Datenarten prüfen") { Task { await model.syncNow(); report = model.garminAvailability() } }
                if let r = report {
                    ForEach(r.entries, id: \.type) { e in
                        LabeledContent(e.type.displayName, value: e.sampleCount > 0 ? "\(e.sampleCount) Werte" : "nicht vorhanden")
                    }
                }
                deviceHeader(.garminPersonalAPI)
            } header: { Text("Garmin Approach S70") } footer: {
                Text("Voraussetzung: In der Garmin-Connect-App unter Einstellungen → Verbundene Apps → Apple Health die Freigabe aktivieren. Eine direkte Garmin-Schnittstelle wird erst angebunden, wenn ein offizieller Zugang vorliegt (siehe Dokumentation).")
            }

            Section {
                deviceHeader(.whoop)
                if model.device(.whoop).isEnabled {
                    Button("Jetzt synchronisieren") { Task { await model.syncNow() } }
                    Button("Verbindung widerrufen", role: .destructive) { revokeKind = .whoop }
                } else {
                    TextField("WHOOP Client-ID", text: $whoopClientId).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Redirect-URI", text: $whoopRedirect).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Token-Broker-URL (https://…)", text: $whoopBroker).textInputAutocapitalization(.never).keyboardType(.URL)
                    Button("Mit WHOOP verbinden") {
                        guard let url = URL(string: whoopBroker) else { return }
                        let cfg = WhoopConfiguration(clientId: whoopClientId, redirectURI: whoopRedirect, brokerBaseURL: url)
                        Task { await model.connectWhoop(config: cfg) }
                    }
                    .disabled(whoopClientId.isEmpty || !whoopBroker.hasPrefix("https://"))
                }
            } header: { Text("WHOOP (optional)") } footer: {
                Text("Berechtigungen: read:recovery, read:sleep, read:cycles, read:workout, offline. Das Client-Secret liegt ausschließlich in deinem Token-Broker, nicht in der App. Token werden im Schlüsselbund gespeichert.")
            }

            Section("Synchronisierung") {
                ForEach([IntegrationKind.appleHealth, .garminViaHealth, .whoop], id: \.self) { k in
                    let s = model.syncState(k)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(k.displayName).font(.subheadline.weight(.medium))
                        Text(s.lastSuccess.map { "Zuletzt erfolgreich: \($0.formatted(date: .abbreviated, time: .shortened)) · \(s.lastImportedCount) neue Werte" } ?? "Noch nicht synchronisiert")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                        if let e = s.lastError {
                            Text("Fehler (\(s.consecutiveFailures)×): \(e.message)").font(.caption).foregroundStyle(Theme.warning)
                        }
                    }
                }
                Button(model.isSyncing ? "Synchronisiere …" : "Alle synchronisieren") { Task { await model.syncNow() } }.disabled(model.isSyncing)
            }
        }
        .navigationTitle("Geräte")
        .onAppear {
            if let c = model.settings.whoop { whoopClientId = c.clientId; whoopRedirect = c.redirectURI; whoopBroker = c.brokerBaseURL.absoluteString }
        }
        .confirmationDialog("Verbindung widerrufen", isPresented: Binding(get: { revokeKind != nil }, set: { if !$0 { revokeKind = nil } }), titleVisibility: .visible) {
            Button("Widerrufen, Daten behalten") { if let k = revokeKind { Task { await model.revoke(k, deleteData: false) } } }
            Button("Widerrufen und importierte Daten löschen", role: .destructive) { if let k = revokeKind { Task { await model.revoke(k, deleteData: true) } } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func deviceHeader(_ k: IntegrationKind) -> some View {
        let d = model.device(k)
        return HStack {
            Text(k.displayName)
            Spacer()
            Text(d.status.displayText).font(.caption)
                .foregroundStyle(d.status.isUsable ? Theme.good : (d.status.displayText.hasPrefix("Fehler") ? Theme.warning : Theme.secondaryText))
                .multilineTextAlignment(.trailing)
        }
    }
}

struct SourcePriorityView: View {
    @Environment(AppModel.self) private var model
    @State private var type: VitalType = .restingHeartRate

    var body: some View {
        let p = model.settings.sourcePriorities
        Form {
            Section {
                ForEach(DataSource.allCases, id: \.self) { s in
                    Toggle(s.displayName, isOn: Binding(get: { !p.disabledSources.contains(s) }, set: { on in
                        var np = p
                        if on { np.disabledSources.remove(s) } else { np.disabledSources.insert(s) }
                        model.updatePriorities(np)
                    }))
                }
            } header: { Text("Datenquellen verwenden") } footer: { Text("Deaktivierte Quellen bleiben gespeichert, werden aber nicht ausgewertet.") }
            Section {
                Picker("Messwert", selection: $type) { ForEach(VitalType.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                ForEach(p.order[type] ?? [], id: \.self) { s in Text(s.displayName) }
                    .onMove { from, to in
                        var np = p
                        var list = np.order[type] ?? []
                        list.move(fromOffsets: from, toOffset: to)
                        np.order[type] = list
                        model.updatePriorities(np)
                    }
                Button("Standard wiederherstellen") { var np = p; np.order = SourcePriorities.standard.order; model.updatePriorities(np) }
            } header: { Text("Priorität je Messwert (ziehen zum Sortieren)") } footer: {
                Text("Die oberste verfügbare Quelle wird angezeigt. Werte verschiedener Quellen werden nicht vermischt; HRV (SDNN) und HRV (RMSSD) sind getrennte Messwerte.")
            }
            .environment(\.editMode, .constant(.active))
        }
        .navigationTitle("Datenquellen")
    }
}

struct PrivacyView: View {
    @Environment(AppModel.self) private var model
    @State private var exportURLs: [URL] = []
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("Grundsätze") {
                Label("Alle Daten liegen lokal auf diesem Gerät (verschlüsselt durch iOS-Datenschutz).", systemImage: "iphone")
                Label("Keine Werbung, keine Analyse- oder Werbe-SDKs, keine Weitergabe an Dritte.", systemImage: "hand.raised")
                Label("Cloud-Funktionen und KI-Dienste sind in Version 1 nicht enthalten.", systemImage: "icloud.slash")
                Label("Zugangstoken liegen im Schlüsselbund und werden nicht exportiert.", systemImage: "key")
            }
            Section("Export") {
                Button("Daten exportieren (JSON + CSV)") {
                    do { exportURLs = try model.exportFiles() } catch { model.errorMessage = "Export fehlgeschlagen: \(error.localizedDescription)" }
                }
                if !exportURLs.isEmpty {
                    ShareLink(items: exportURLs) { Label("Exportdateien teilen/sichern", systemImage: "square.and.arrow.up") }
                }
            }
            Section {
                if model.hasDemoData {
                    Button("Beispieldaten entfernen", role: .destructive) { model.deleteDemoData() }
                } else {
                    Button("Beispieldaten laden (gekennzeichnet)") { model.loadDemoData() }
                }
            } header: { Text("Beispieldaten") } footer: {
                Text("Beispieldaten dienen nur der Vorführung, sind überall als „Beispieldaten“ markiert und fließen nicht in den Assistenten ein.")
            }
            Section {
                Button("Alle persönlichen Daten löschen", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Löscht Profil, Plan, Trainingshistorie, Vitaldaten, Protokolle und Zugangstoken auf diesem Gerät. In Apple Health gespeicherte Workouts verwaltest du in der Health-App.")
            }
        }
        .navigationTitle("Datenschutz")
        .confirmationDialog("Wirklich alle Daten löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Endgültig löschen", role: .destructive) { Task { await model.deleteAllData() } }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}
