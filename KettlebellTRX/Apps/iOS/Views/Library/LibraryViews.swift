import SwiftUI
import FitnessCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var category: ExerciseCategory?

    var body: some View {
        let items = model.library.search(query, category: category)
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip("Alle", selected: category == nil) { category = nil }
                        ForEach(ExerciseCategory.allCases, id: \.self) { c in chip(c.displayName, selected: category == c) { category = c } }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
            Section("\(items.count) Übungen") {
                ForEach(items) { ex in
                    NavigationLink { ExerciseDetailView(exercise: ex) } label: {
                        HStack(spacing: 12) {
                            ExerciseAnimationView(animationId: ex.animation, height: 54, animated: false)
                                .frame(width: 54).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.nameDE).font(.body.weight(.medium))
                                Text("\(ex.category.displayName) · \(ex.primaryMuscles.map(\.displayName).joined(separator: ", "))")
                                    .font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Übung oder Muskel suchen")
        .navigationTitle("Übungsbibliothek")
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Theme.accent : Theme.cardHighlight, in: Capsule())
                .foregroundStyle(selected ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ExerciseDetailView: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise

    var body: some View {
        let verdict = SafetyFilter(profile: model.profile, recentPain: model.painReports.filter { Date().timeIntervalSince($0.date) < 7 * 86400 }).evaluate(exercise)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ExerciseAnimationView(animationId: exercise.animation, height: 240)
                    .frame(maxWidth: .infinity)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Animierte Darstellung: \(PoseLibrary.animation(for: exercise.animation)?.caption ?? exercise.nameDE)")
                if let cap = PoseLibrary.animation(for: exercise.animation)?.caption {
                    Text(cap).font(.footnote).foregroundStyle(Theme.secondaryText).frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.nameDE).font(.title.bold())
                    if let en = exercise.nameEN, en != exercise.nameDE { Text(en).foregroundStyle(Theme.secondaryText) }
                    Text(([exercise.category.displayName, exercise.difficulty.displayName] + Self.extraEquipment(exercise)).joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                if verdict.level != .allowed {
                    Card(title: verdict.level == .excluded ? "Für dich derzeit ausgeschlossen" : "Bitte beachten", systemImage: "exclamationmark.shield") {
                        ForEach(verdict.reasons, id: \.self) { Text("• \($0)").font(.callout) }
                    }
                }
                Text(exercise.summary)
                Card(title: "Vorgabe", systemImage: "list.number") {
                    let rx = exercise.defaultPrescription
                    Text("\(rx.sets) × \(targetText(rx.targetKind, rx.target, perSide: rx.perSide)) · Pause \(rx.restSeconds) s")
                    Text(loadText).foregroundStyle(Theme.secondaryText)
                }
                section("Ausgangsposition", "figure.stand", [exercise.startingPosition])
                section("Bewegung", "arrow.up.and.down", [exercise.movementDirection])
                section("Atmung", "wind", [exercise.breathing])
                section("Technik", "checkmark.circle", exercise.techniqueCues)
                section("Häufige Fehler", "xmark.circle", exercise.commonMistakes)
                section("Sicherheit", "cross.case", exercise.safetyNotes)
                Card(title: "Muskeln", systemImage: "figure.arms.open") {
                    Text("Primär: " + exercise.primaryMuscles.map(\.displayName).joined(separator: ", "))
                    if !exercise.secondaryMuscles.isEmpty {
                        Text("Sekundär: " + exercise.secondaryMuscles.map(\.displayName).joined(separator: ", ")).foregroundStyle(Theme.secondaryText)
                    }
                }
                let alts = model.library.alternatives(for: exercise.id).prefix(6)
                if !alts.isEmpty {
                    Card(title: "Alternativen", systemImage: "arrow.triangle.2.circlepath") {
                        ForEach(Array(alts)) { a in
                            NavigationLink(a.nameDE) { ExerciseDetailView(exercise: a) }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(exercise.nameDE)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Geräte, die nicht schon durch die Kategorie genannt sind (z. B. kein doppeltes „Kettlebell“).
    static func extraEquipment(_ e: Exercise) -> [String] {
        let implied: Set<Equipment>
        switch e.category {
        case .kettlebell: implied = [.kettlebell]
        case .trx: implied = [.trx]
        case .bodyweight: implied = [.bodyweight]
        default: implied = [.bodyweight]
        }
        let extra = e.equipment.filter { !implied.contains($0) }.map(\.displayName)
        return extra.isEmpty ? [] : [extra.joined(separator: ", ")]
    }

    private var loadText: String {
        switch exercise.load.kind {
        case .kettlebell:
            let w = WeightSelector(available: model.profile.kettlebellsKg).recommended(for: exercise, experience: model.profile.experience)
            return "Empfohlene Kettlebell: " + (w?.kgText ?? "keine passende vorhanden")
        case .trx: return "TRX: " + (exercise.load.leverHint ?? "Intensität über den Körperwinkel steuern")
        case .bodyweight, .none: return "Eigengewicht"
        }
    }

    @ViewBuilder private func section(_ title: String, _ icon: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            Card(title: title, systemImage: icon) {
                ForEach(lines, id: \.self) { Text(lines.count > 1 ? "• \($0)" : $0).font(.callout) }
            }
        }
    }
}

/// Eigene, animierte Strichfigur-Darstellung (keine Fremdinhalte).
struct ExerciseAnimationView: View {
    let animationId: String
    var height: CGFloat = 200
    var animated = true

    var body: some View {
        if let anim = PoseLibrary.animation(for: animationId) {
            if animated {
                TimelineView(.animation) { ctx in
                    figure(anim, t: ctx.date.timeIntervalSinceReferenceDate)
                }
            } else {
                figure(anim, t: anim.cycleSeconds)
            }
        } else {
            Image(systemName: "figure.strengthtraining.functional").font(.largeTitle).frame(height: height)
        }
    }

    private func figure(_ anim: MovementAnimation, t: Double) -> some View {
        Canvas { ctx, size in
            let s = PoseRenderer.skeleton(for: anim, at: t)
            let scale = min(size.width, size.height)
            let ox = (size.width - scale) / 2, oy = (size.height - scale) / 2
            func p(_ j: Joint) -> CGPoint { CGPoint(x: ox + s[j].x * scale, y: oy + s[j].y * scale) }
            let line = max(2, scale * 0.035)

            // Boden
            var floor = Path()
            floor.move(to: CGPoint(x: ox + 0.05 * scale, y: oy + PoseRenderer.floorY * scale))
            floor.addLine(to: CGPoint(x: ox + 0.95 * scale, y: oy + PoseRenderer.floorY * scale))
            ctx.stroke(floor, with: .color(.white.opacity(0.15)), lineWidth: 1)

            // TRX-Schlingen
            if anim.straps != .none {
                let anchor = CGPoint(x: ox + anim.strapAnchorX * scale, y: oy + 0.02 * scale)
                var straps = Path()
                for j in anim.straps == .hands ? [Joint.handA, .handB] : [.footA, .footB] {
                    straps.move(to: anchor); straps.addLine(to: p(j))
                }
                ctx.stroke(straps, with: .color(.yellow.opacity(0.7)), lineWidth: max(1, line * 0.35))
            }

            func limb(_ joints: [Joint], _ color: Color) {
                var path = Path()
                path.move(to: p(joints[0]))
                for j in joints.dropFirst() { path.addLine(to: p(j)) }
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
            }
            let far = Color.white.opacity(0.35)
            limb([.hip, .kneeB, .footB], far)
            limb([.shoulder, .elbowB, .handB], far)
            limb([.shoulder, .hip], .white)
            limb([.hip, .kneeA, .footA], .white)
            limb([.shoulder, .elbowA, .handA], Theme.accent)
            let r = s.headRadius * scale
            let h = p(.head)
            ctx.fill(Path(ellipseIn: CGRect(x: h.x - r, y: h.y - r, width: 2 * r, height: 2 * r)), with: .color(.white))

            if anim.kettlebellInHands.a || anim.kettlebellInHands.b {
                let kb = anim.kettlebellInHands.a ? p(.handA) : p(.handB)
                let kr = scale * 0.045
                ctx.fill(Path(ellipseIn: CGRect(x: kb.x - kr, y: kb.y, width: 2 * kr, height: 2 * kr)), with: .color(Theme.accent))
            }
        }
        .frame(height: height)
    }
}
