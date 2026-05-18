import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @Query private var users: [UserProfile]

    var body: some View {
        Group {
            switch appState.modelSetupState {
            case .checking:
                LaunchPreparationView()
            case .setupRequired, .downloading, .failed:
                ModelSetupView()
                    .environmentObject(appState)
            case .ready:
                if let user = users.first, user.onboardingCompleted {
                    MainTabView()
                        .environmentObject(appState)
                } else {
                    OnboardingFlowView()
                        .environmentObject(appState)
                }
            }
        }
        .task {
            await appState.prepareForLaunch()
        }
        .onChange(of: scenePhase) { _, newPhase in
            appState.handleScenePhaseChange(newPhase)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue
    @Query(sort: \JournalEntry.date, order: .reverse)
    private var journalEntries: [JournalEntry]
    @State private var hasUnreadJournal = false

    private var text: AppText {
        let mode = AppLanguageMode(rawValue: appLanguageRawValue) ?? .system
        return AppText(language: mode.resolvedLanguage)
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label(text.homeTab, systemImage: "house.fill")
                }
            JournalListView()
                .tabItem {
                    Label(text.journalTab, systemImage: "book.fill")
                }
                .badge(hasUnreadJournal ? "" : nil)
            #if DEBUG
            if AppEnvironment.shouldShowDebugAdminTab {
                AdminView()
                    .tabItem {
                        Label(text.adminTab, systemImage: "wrench.and.screwdriver.fill")
                    }
            }
            SettingsView()
                .tabItem {
                    Label(text.settingsTab, systemImage: "gearshape.fill")
                }
            #else
            SettingsView()
                .tabItem {
                    Label(text.settingsTab, systemImage: "gearshape.fill")
                }
            #endif
        }
        .tint(QuietNativeTheme.accent)
        .toolbarBackground(QuietNativeTheme.backgroundWarm, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onAppear(perform: refreshUnreadJournalState)
        .onChange(of: journalEntries.count) {
            refreshUnreadJournalState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .journalUnreadStateDidChange)) { _ in
            refreshUnreadJournalState()
        }
    }

    private func refreshUnreadJournalState() {
        hasUnreadJournal = JournalUnreadStore.hasUnread(entries: journalEntries)
    }
}
