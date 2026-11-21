import SwiftUI
import FitnessCore

/// Hauptnavigation. Fünf Tabs + Einstellungen über das Zahnrad (iOS blendet ab sechs Tabs „Mehr“ ein,
/// was die Bedienung verschlechtern würde).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0
    @State private var showSettings = false

    var body: some View {
        if model.needsOnboarding {
            OnboardingView()
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            screen(DashboardView(openTraining: { tab = 2 })).tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }.tag(0)
            screen(PlanView()).tabItem { Label("Plan", systemImage: "calendar") }.tag(1)
            screen(TrainingHomeView()).tabItem { Label("Training", systemImage: "figure.strengthtraining.functional") }.tag(2)
            screen(LibraryView()).tabItem { Label("Übungen", systemImage: "books.vertical") }.tag(3)
            screen(ProgressDashboardView()).tabItem { Label("Fortschritt", systemImage: "chart.xyaxis.line") }.tag(4)
        }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .fullScreenCover(isPresented: Binding(get: { model.run != nil }, set: { _ in })) {
            WorkoutPlayerView()
        }
        .alert("Hinweis", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }

    private func screen<V: View>(_ v: V) -> some View {
        NavigationStack {
            v.toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Einstellungen")
                }
            }
            .background(Theme.background)
            .scrollContentBackground(.hidden)
        }
    }
}
