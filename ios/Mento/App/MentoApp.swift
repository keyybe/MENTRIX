import SwiftUI

// Настройки сборки из Config.xcconfig попадают в Info.plist
enum AppConfig {
    static var serverURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "MentorServerURL") as? String ?? ""
        return URL(string: raw.isEmpty ? "http://localhost:8080/" : raw)!
    }

    static var googleClientId: String {
        (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }

    static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

// Ручное внедрение зависимостей: всё создаётся в одном месте
@MainActor
final class AppContainer {
    let session: SessionStore
    let cache: CacheStore
    let api: MentorBackend
    let reminders: ReminderScheduler

    init() {
        let session = DefaultsSession()
        self.session = session
        cache = DefaultsCache()
        api = MentorAPI(baseURL: AppConfig.serverURL) { session.token }
        reminders = LocalReminderScheduler()
    }
}

@main
struct MentoApp: App {
    @State private var vm: MentorViewModel
    @State private var chat: ChatViewModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.dark

    init() {
        let c = AppContainer()
        _vm = State(initialValue: MentorViewModel(api: c.api, session: c.session, cache: c.cache, reminders: c.reminders))
        _chat = State(initialValue: ChatViewModel(api: c.api))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vm)
                .environment(chat)
                .preferredColorScheme(theme.colorScheme) // тема из профиля; nil – как в системе
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vm.rescheduleReminder() }
        }
    }
}
