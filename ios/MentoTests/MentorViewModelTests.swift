import Foundation
import Testing
@testable import Mento

// Перенос app/src/test/.../MentorViewModelTest.kt

private let testMission = MissionDto(
    id: "m1", week: 1, day: 1, title: "Теги", topic: "HTML",
    material: SourceRef(title: "HTML", url: "https://example.com"), task: "Объясни теги",
    minutes: 30, status: .todo)
private let testPlan = PlanDto(version: 1, area: .frontend, goal: "Работа", weeks: [WeekDto(index: 1, title: "Неделя 1", missions: [testMission])])
private let testToday = TodayDto(mission: testMission, message: "Миссия готова")
private let testProgress = ProgressDto(streak: 0, doneMissions: 0, totalMissions: 1, planVersion: 1, gaps: [])

private final class FakeSession: SessionStore {
    var token: String?
    let deviceId = "device-0001"
    var reminderMinutes: Int?
    var lastPassedDay: String?
    var name: String?
    var avatarFile: String?
    init(token: String? = nil) { self.token = token }
}

private final class FakeCache: CacheStore {
    var plan: PlanDto?
    var today: TodayDto?
    var progress: ProgressDto?
    func clear() { plan = nil; today = nil; progress = nil }
}

private final class FakeReminders: ReminderScheduler {
    var time: (Int, Int)?
    var skipToday = false
    func schedule(hour: Int, minute: Int, skipToday: Bool) { time = (hour, minute); self.skipToday = skipToday }
    func cancel() { time = nil }
}

// Сервер, поведение которого задаёт тест
private final class FakeBackend: MentorBackend {
    var hasProfile = true
    var failWith: Error?
    var evaluation = EvaluationDto(score: 80, passed: true, feedback: "ok", gaps: [], streak: 1)
    var calls = 0
    var lastSettings: SettingsRequest?

    private func check() throws {
        calls += 1
        if let failWith { throw failWith }
    }

    func register(_ req: RegisterRequest) async throws -> AuthResponse { try check(); return AuthResponse(token: "reg-token", userId: "e:1", name: req.name) }
    func login(_ req: LoginRequest) async throws -> AuthResponse { try check(); return AuthResponse(token: "login-token", userId: "e:1", name: "Аня") }
    func loginGoogle(idToken: String) async throws -> AuthResponse { try check(); return AuthResponse(token: "google-token", userId: "g:1") }
    func loginDev(deviceId: String) async throws -> AuthResponse { try check(); return AuthResponse(token: "dev-token", userId: "dev:\(deviceId)") }
    func quiz(area: ItArea) async throws -> [QuizQuestionDto] {
        try check()
        return [QuizQuestionDto(id: "fe-html", topic: "HTML", question: "Что такое HTML?", options: ["Разметка", "Язык стилей"])]
    }
    func plan() async throws -> PlanDto? { try check(); return hasProfile ? testPlan : nil }
    func createProfile(_ req: ProfileRequest) async throws -> PlanDto { try check(); hasProfile = true; return testPlan }
    func updateSettings(_ req: SettingsRequest) async throws -> PlanDto {
        try check(); lastSettings = req; var p = testPlan; p.goal = req.goal; return p
    }
    func today() async throws -> TodayDto { try check(); return testToday }
    func progress() async throws -> ProgressDto { try check(); return testProgress }
    func answer(_ req: AnswerRequest) async throws -> EvaluationDto { try check(); return evaluation }
    func chat(_ req: ChatRequest) async throws -> ChatReply { try check(); return ChatReply(reply: "Подумай о тегах") }
    func deleteAccount() async throws { try check() }
}

@MainActor
struct MentorViewModelTests {
    private let backend = FakeBackend()
    private let cache = FakeCache()
    private let reminders = FakeReminders()
    // 6 ноября 2026, полдень по местному времени
    private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12))!

    private func vm(_ session: SessionStore) async -> MentorViewModel {
        let vm = MentorViewModel(api: backend, session: session, cache: cache, reminders: reminders, clock: { [day] in day })
        await vm.loadTask?.value
        return vm
    }

    @Test func withoutTokenShowsLoginAndDoesNotCallServer() async {
        let vm = await vm(FakeSession())
        #expect(!vm.signedIn)
        #expect(!vm.loading)
        #expect(backend.calls == 0)
    }

    @Test func registerSavesTokenAndNameAndOpensOnboarding() async {
        backend.hasProfile = false
        let session = FakeSession()
        let vm = await vm(session)
        await vm.register(name: "Аня", email: "anya@mail.ru", password: "password1").value
        #expect(session.token == "reg-token")
        #expect(session.name == "Аня")
        #expect(vm.signedIn)
        #expect(!vm.hasProfile)
    }

    @Test func emailLoginSavesTokenAndLoadsData() async {
        let session = FakeSession()
        let vm = await vm(session)
        await vm.login(email: "anya@mail.ru", password: "password1").value
        #expect(session.token == "login-token")
        #expect(session.name == "Аня")
        #expect(vm.signedIn)
        #expect(vm.hasProfile)
    }

    @Test func devLoginSavesTokenAndOpensOnboarding() async {
        backend.hasProfile = false
        let session = FakeSession()
        let vm = await vm(session)
        await vm.loginDev().value
        #expect(session.token == "dev-token")
        #expect(vm.signedIn)
        #expect(!vm.hasProfile)
    }

    @Test func loadsPlanAndCachesIt() async {
        let vm = await vm(FakeSession(token: "t"))
        #expect(vm.hasProfile)
        #expect(vm.today?.mission?.id == testMission.id)
        #expect(cache.plan == testPlan)
    }

    @Test func withoutNetworkShowsCachedDataOffline() async {
        cache.plan = testPlan
        cache.today = testToday
        backend.failWith = URLError(.notConnectedToInternet)
        let vm = await vm(FakeSession(token: "t"))
        #expect(vm.offline)
        #expect(vm.hasProfile)
        #expect(vm.plan == testPlan)
        #expect(vm.error == nil)
    }

    @Test func quizIsLoadedAndOfflineQuizCanBeSkipped() async {
        let vm = await vm(FakeSession(token: "t"))
        #expect(await vm.loadQuiz(area: .frontend)?.first?.id == "fe-html")
        backend.failWith = URLError(.notConnectedToInternet)
        #expect(await vm.loadQuiz(area: .frontend) == nil)
        #expect(vm.signedIn)
    }

    @Test func newGoalRebuildsPlan() async {
        let vm = await vm(FakeSession(token: "t"))
        await vm.saveSettings(goal: "Пройти собеседование", minutesPerDay: 20, daysPerWeek: 5).value
        #expect(backend.lastSettings?.goal == "Пройти собеседование")
        #expect(vm.notice == "План пересобран под новую цель")

        await vm.saveSettings(goal: testPlan.goal, minutesPerDay: 30, daysPerWeek: 5).value
        #expect(backend.lastSettings?.minutesPerDay == 30)
        #expect(vm.notice == "Настройки сохранены")
    }

    @Test func expiredSessionSignsOut() async {
        let session = FakeSession(token: "old")
        backend.failWith = SessionExpired()
        let vm = await vm(session)
        #expect(!vm.signedIn)
        #expect(session.token == nil)
        #expect(vm.notice?.contains("Сессия") == true)
    }

    @Test func passedAnswerMarksDaySoReminderIsSkipped() async {
        let session = FakeSession(token: "t")
        session.reminderMinutes = 19 * 60
        let vm = await vm(session)
        await vm.submitAnswer("ответ из нескольких слов")?.value
        #expect(session.lastPassedDay == "2026-11-06")
        #expect(vm.evaluation?.passed == true)
        #expect(reminders.skipToday)
    }

    @Test func serverMessageIsShownAsIs() async {
        let vm = await vm(FakeSession(token: "t"))
        backend.failWith = ServerMessage(message: "Миссия уже выполнена")
        await vm.submitAnswer("ответ")?.value
        #expect(vm.error == "Миссия уже выполнена")
        #expect(!vm.submitting)
    }

    @Test func reminderIsScheduledAndCancelled() async {
        let session = FakeSession(token: "t")
        let vm = await vm(session)
        vm.setReminder(20 * 60 + 30)
        #expect(reminders.time?.0 == 20 && reminders.time?.1 == 30)
        #expect(session.reminderMinutes == 20 * 60 + 30)
        #expect(vm.reminderMinutes == 20 * 60 + 30)
        vm.setReminder(nil)
        #expect(reminders.time == nil)
    }

    @Test func nameIsEditedAndKeptOnGoogleLogin() async {
        let session = FakeSession()
        let vm = await vm(session)
        vm.updateName("  Аня  ")
        #expect(vm.userName == "Аня")
        await vm.loginWithGoogle(idToken: "id-token", name: "Anna Google").value
        #expect(session.name == "Аня") // введённое вручную имя не затирается
        vm.updateName("   ")
        #expect(vm.userName == nil)
    }

    @Test func signOutForgetsNameAndAvatar() async {
        let session = FakeSession(token: "t")
        session.name = "Аня"
        session.avatarFile = "no-such-file.jpg"
        let vm = await vm(session)
        #expect(vm.avatarFile == "no-such-file.jpg")
        vm.signOut()
        #expect(session.name == nil)
        #expect(session.avatarFile == nil)
        #expect(vm.avatarFile == nil)
    }

    @Test func deleteAccountClearsEverything() async {
        let vm = await vm(FakeSession(token: "t"))
        vm.setReminder(9 * 60)
        await vm.deleteAccount().value
        #expect(!vm.hasProfile)
        #expect(cache.plan == nil)
        #expect(reminders.time == nil)
    }

    @Test func chatFailureReturnsQuestionToInput() async {
        let chat = ChatViewModel(api: backend)
        chat.open(missionId: testMission.id)
        backend.failWith = URLError(.notConnectedToInternet)
        await chat.send("Что такое тег?")?.value
        #expect(chat.messages.isEmpty)
        #expect(chat.draft == "Что такое тег?")

        backend.failWith = nil
        await chat.send("Что такое тег?")?.value
        #expect(chat.messages.count == 2)
    }

    @Test func decodesServerJsonWithoutDefaultFields() throws {
        // сервер старой версии может не прислать новые поля – приложение берёт значения по умолчанию
        let json = #"{"mission":{"id":"m","week":1,"day":2,"title":"t","topic":"x","material":{"title":"a","url":"b"},"task":"q","minutes":15,"status":"TODO"},"message":"ok"}"#
        let decoded = try JSONDecoder().decode(TodayDto.self, from: Data(json.utf8))
        #expect(decoded.mission?.review == false)
        #expect(decoded.planRebuilt == false)
    }
}
