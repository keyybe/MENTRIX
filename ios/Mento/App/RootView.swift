import SwiftUI

private enum AppDestination { case login, loading, onboarding, main }

struct RootView: View {
    @Environment(MentorViewModel.self) private var vm

    private var destination: AppDestination {
        if !vm.signedIn { return .login }
        if vm.loading && vm.plan == nil { return .loading }
        if !vm.hasProfile || vm.changingArea { return .onboarding }
        return .main
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            switch destination {
            case .login:
                LoginView().transition(.screen)
            case .loading:
                ProgressView().tint(Palette.accent).controlSize(.large).transition(.opacity)
            case .onboarding:
                OnboardingView().transition(.screen)
            case .main:
                MainView().transition(.screen)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: destination)
        .overlay(alignment: .bottom) { NoticeToast() }
    }
}

private extension AnyTransition {
    static var screen: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(x: 28)), removal: .opacity.combined(with: .offset(x: -28)))
    }
}

// Короткое сообщение внизу экрана (аналог Snackbar)
private struct NoticeToast: View {
    @Environment(MentorViewModel.self) private var vm

    var body: some View {
        ZStack {
            if let notice = vm.notice {
                Text(notice)
                    .font(.bodyMedium)
                    .foregroundStyle(Palette.background)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(Palette.ink.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(3))
                        vm.consumeNotice()
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: vm.notice)
    }
}

// ---------- Главная часть: вкладки, урок и чат поверх них ----------

private enum MainTab: Int, CaseIterable {
    case home, plan, profile

    var title: String {
        switch self {
        case .home: "Главная"
        case .plan: "План"
        case .profile: "Профиль"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .plan: "chart.line.uptrend.xyaxis"
        case .profile: "person.fill"
        }
    }
}

struct MainView: View {
    @Environment(MentorViewModel.self) private var vm
    @State private var tab: MainTab = .home
    @State private var lessonOpen = false
    @State private var chatOpen = false
    @State private var editProfileOpen = false

    var body: some View {
        TabView(selection: $tab) {
            ForEach(MainTab.allCases, id: \.self) { t in
                content(for: t)
                    .tabItem { Label(t.title, systemImage: t.icon) }
                    .tag(t)
            }
        }
        .tint(Palette.accent)
        // Урок открывается на весь экран; если его закрыли после проверки – обновляем данные
        .fullScreenCover(isPresented: $lessonOpen, onDismiss: {
            if vm.evaluation != nil { vm.next() }
        }) {
            LessonView(onClose: { lessonOpen = false })
        }
        .fullScreenCover(isPresented: $editProfileOpen) {
            EditProfileView(onClose: { editProfileOpen = false })
        }
        .sheet(isPresented: $chatOpen) {
            if let mission = vm.today?.mission {
                ChatView(mission: mission, onClose: { chatOpen = false })
            }
        }
    }

    @ViewBuilder
    private func content(for t: MainTab) -> some View {
        switch t {
        case .home:
            HomeView(
                onStartLesson: { lessonOpen = true },
                onOpenChat: { chatOpen = true },
                onOpenPlan: { tab = .plan }
            )
        case .plan:
            PlanView(onStart: { lessonOpen = true })
        case .profile:
            ProfileView(onEditProfile: { editProfileOpen = true })
        }
    }
}
