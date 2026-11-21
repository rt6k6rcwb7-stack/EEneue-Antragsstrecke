import SwiftUI
import FitnessCore

@main
struct KettlebellTRXApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task { RestNotifications.requestPermission() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.tick()
                Task { await model.syncNow() }
            }
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.91, green: 0.60, blue: 0.32)       // Kupfer
    static let background = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let card = Color(white: 0.11)
    static let cardHighlight = Color(white: 0.16)
    static let secondaryText = Color(white: 0.62)
    static let good = Color(red: 0.45, green: 0.78, blue: 0.55)
    static let caution = Color(red: 0.96, green: 0.76, blue: 0.33)
    static let warning = Color(red: 0.93, green: 0.40, blue: 0.36)

    static func color(for kind: RecommendationKind) -> Color {
        switch kind {
        case .asPlanned: return good
        case .adjustReps, .reduceIntensity: return caution
        case .mobilityInstead, .extraRecovery: return Color(red: 0.45, green: 0.65, blue: 0.95)
        case .noTrainingSeeDoctor: return warning
        }
    }
}

/// Einheitliche Karte im dunklen Design.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label(title, systemImage: systemImage ?? "circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .labelStyle(.titleAndIcon)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Kennzeichnung für Beispieldaten und fehlende Messwerte.
struct DemoBadge: View {
    var body: some View {
        Text("BEISPIELDATEN")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.caution.opacity(0.2), in: Capsule())
            .foregroundStyle(Theme.caution)
            .accessibilityLabel("Beispieldaten, keine echten Messwerte")
    }
}

struct MissingValue: View {
    var text = "Keine Daten"
    var body: some View {
        Text(text).font(.callout).foregroundStyle(Theme.secondaryText).italic()
            .accessibilityLabel("\(text), Wert nicht verfügbar")
    }
}

extension Double {
    var kgText: String { rounded() == self ? "\(Int(self)) kg" : String(format: "%.1f kg", self) }
}

func durationText(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

func targetText(_ kind: TargetKind, _ value: Int, perSide: Bool) -> String {
    (kind == .reps ? "\(value) Wdh." : "\(value) s") + (perSide ? " je Seite" : "")
}
