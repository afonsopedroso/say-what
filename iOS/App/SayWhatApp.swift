import SwiftUI
import SayWhatKit

@main
struct SayWhatApp: App {
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var engine = DictationEngine.shared
    @StateObject private var session = KeyboardSession.shared
    @StateObject private var history = HistoryStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(engine)
                .environmentObject(session)
                .environmentObject(history)
                .tint(Theme.accent)
                .onOpenURL { session.handle(url: $0) }
                .task {
                    if settings.onboarded { await engine.prepareModel() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var session: KeyboardSession

    var body: some View {
        TabView {
            DictateView().tabItem { Label("Dictate", systemImage: "waveform") }
            HistoryView().tabItem { Label("History", systemImage: "clock") }
            DictionaryView().tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: Binding(get: { !settings.onboarded }, set: { _ in })) {
            OnboardingView()
        }
        .fullScreenCover(isPresented: $session.showHandoff) {
            HandoffView()
        }
    }
}
