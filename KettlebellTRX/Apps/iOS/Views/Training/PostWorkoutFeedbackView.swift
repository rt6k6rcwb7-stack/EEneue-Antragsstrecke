import SwiftUI
import FitnessCore

/// Kurze Fragen nach dem Training (Grundlage für den Assistenten).
struct PostWorkoutFeedbackView: View {
    let aborted: Bool
    var onSubmit: (PostWorkoutFeedback) -> Void

    @State private var rpe = 6
    @State private var hadPain = false
    @State private var painRegion: BodyRegion = .lumbarSpine
    @State private var painIntensity = 3
    @State private var weightFit: PostWorkoutFeedback.WeightFit = .appropriate
    @State private var wellbeing: PostWorkoutFeedback.Wellbeing = .good
    @State private var note = ""

    var body: some View {
        Form {
            Section("Wie anstrengend war das Training? (1–10)") {
                Picker("Anstrengung", selection: $rpe) { ForEach(1...10, id: \.self) { Text("\($0)").tag($0) } }
                    .pickerStyle(.segmented)
                Text(rpeText).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Section("Gab es Schmerzen oder Einschränkungen?") {
                Toggle("Ja, Beschwerden", isOn: $hadPain)
                if hadPain {
                    Picker("Bereich", selection: $painRegion) { ForEach(BodyRegion.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                    Stepper("Stärke: \(painIntensity)/10", value: $painIntensity, in: 1...10)
                    if painIntensity >= 7 {
                        Text("Starke Schmerzen bitte ärztlich oder physiotherapeutisch abklären. Betroffene Übungen werden bis dahin ersetzt.")
                            .font(.footnote).foregroundStyle(Theme.warning)
                    }
                }
            }
            Section("Waren die Gewichte angemessen?") {
                Picker("Gewichte", selection: $weightFit) {
                    ForEach(PostWorkoutFeedback.WeightFit.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section("Wie fühlst du dich nach dem Training?") {
                Picker("Befinden", selection: $wellbeing) {
                    ForEach(PostWorkoutFeedback.Wellbeing.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented)
                TextField("Notiz (optional)", text: $note, axis: .vertical)
            }
        }
        .navigationTitle(aborted ? "Training beendet" : "Geschafft!")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    let pain = hadPain ? [PainReport(region: painRegion, intensity: painIntensity, note: note)] : []
                    onSubmit(PostWorkoutFeedback(rpe: rpe, hadPain: hadPain, painReports: pain, weightFit: weightFit, wellbeing: wellbeing, note: note))
                }
            }
        }
    }

    private var rpeText: String {
        switch rpe {
        case 1...3: return "Leicht – Unterhaltung problemlos möglich"
        case 4...6: return "Moderat – fordernd, aber gut kontrollierbar"
        case 7...8: return "Hart – nur noch wenige Wiederholungen in Reserve"
        default: return "Sehr hart bis maximal"
        }
    }
}
