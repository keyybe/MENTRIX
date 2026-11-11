import Foundation
import Observation

// Состояние всего приложения и действия пользователя. Методы-действия возвращают Task,
// чтобы тесты могли дождаться их окончания; экраны результат игнорируют.
@Observable
@MainActor
final class MentorViewModel {
    // ---------- Состояние ----------
    var signedIn = false
    var loading = true
    var submitting = false
    var hasProfile = false
    var changingArea = false // человек выбирает новое направление – показываем онбординг с кнопкой «Отмена»
    var offline = false      // показаны сохранённые данные, сервер недоступен
    var plan: PlanDto?
    var today: TodayDto?
    var progress: ProgressDto?
    var evaluation: EvaluationDto?
    var reminderMinutes: Int? // минуты от полуночи, nil – напоминания выключены
    var userName: String?
    var avatarFile: String?
    var error: String?
    var notice: String? // короткое всплывающее сообщение

    @ObservationIgnored private let api: MentorBackend
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let cache: CacheStore
    @ObservationIgnored private let reminders: ReminderScheduler
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?

    init(api: MentorBackend, session: SessionStore, cache: CacheStore, reminders: ReminderScheduler,
         clock: @escaping () -> Date = Date.init) {
        self.api = api
        self.session = session
        self.cache = cache
        self.reminders = reminders
        self.clock = clock
        let hasToken = session.token != nil
        signedIn = hasToken
        loading = hasToken
        reminderMinutes = session.reminderMinutes
        userName = session.name
        avatarFile = session.avatarFile
        if hasToken { load() }
    }

    private var todayString: String { Self.dayString(clock()) }

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func resetState() {
        loading = false; submitting = false; hasProfile = false; changingArea = false; offline = false
        plan = nil; today = nil; progress = nil; evaluation = nil; error = nil
    }

    // Запуск с общей обработкой ошибок: истёкший вход, понятные ошибки сервера и нет сети
    @discardableResult
    private func launchSafely(_ networkError: String, _ block: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
        Task {
            do {
                try await block()
            } catch is CancellationError {
            } catch is SessionExpired {
                signOut(notice: "Сессия истекла, войди снова.")
            } catch let e as ServerMessage {
                loading = false; submitting = false; error = e.message
            } catch {
                loading = false; submitting = false; self.error = networkError
            }
        }
    }

    // ---------- Вход и регистрация ----------

    @discardableResult
    func register(name: String, email: String, password: String) -> Task<Void, Never> {
        authenticate {
            let auth = try await self.api.register(RegisterRequest(
                name: name.trimmingCharacters(in: .whitespaces), email: email.trimmingCharacters(in: .whitespaces), password: password))
            self.applyAuth(token: auth.token, name: auth.name)
        }
    }

    @discardableResult
    func login(email: String, password: String) -> Task<Void, Never> {
        authenticate {
            let auth = try await self.api.login(LoginRequest(email: email.trimmingCharacters(in: .whitespaces), password: password))
            self.applyAuth(token: auth.token, name: auth.name)
        }
    }

    @discardableResult
    func loginWithGoogle(idToken: String, name: String?) -> Task<Void, Never> {
        authenticate {
            let auth = try await self.api.loginGoogle(idToken: idToken)
            self.applyAuth(token: auth.token, name: name ?? auth.name)
        }
    }

    @discardableResult
    func loginDev() -> Task<Void, Never> {
        authenticate {
            let auth = try await self.api.loginDev(deviceId: self.session.deviceId)
            self.applyAuth(token: auth.token, name: auth.name)
        }
    }

    private func applyAuth(token: String, name: String?) {
        session.token = token
        if session.name == nil, let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            session.name = name
        }
        userName = session.name
    }

    private func authenticate(_ block: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
        launchSafely("Нет связи с сервером. Проверь, что он запущен.") {
            self.submitting = true
            self.error = nil
            try await block()
            self.signedIn = true
            self.submitting = false
            self.loading = true
            try await self.refresh()
        }
    }

    func loginFailed(_ message: String) { error = message }

    func clearError() { error = nil }

    // Имя и фото привязаны к аккаунту: при выходе стираем, чтобы их не увидел следующий человек
    func signOut(notice: String? = nil) {
        session.token = nil
        session.name = nil
        AvatarStore.delete(session.avatarFile)
        session.avatarFile = nil
        cache.clear()
        resetState()
        signedIn = false
        userName = nil
        avatarFile = nil
        reminderMinutes = session.reminderMinutes
        self.notice = notice
    }

    // ---------- Данные ----------

    @discardableResult
    func load() -> Task<Void, Never> {
        // сначала показываем сохранённое, чтобы экран не был пустым, потом обновляем с сервера
        if plan == nil, let cached = cache.plan {
            loading = false
            hasProfile = true
            plan = cached
            today = cache.today
            progress = cache.progress
        }
        let task = Task {
            loading = plan == nil
            error = nil
            do {
                try await refresh()
            } catch is CancellationError {
            } catch is SessionExpired {
                signOut(notice: "Сессия истекла, войди снова.")
            } catch {
                loading = false
                if plan != nil {
                    offline = true
                } else {
                    self.error = "Нет связи с сервером. Проверь интернет и попробуй ещё раз."
                }
            }
        }
        loadTask = task
        return task
    }

    private func refresh() async throws {
        guard let plan = try await api.plan() else {
            cache.clear()
            loading = false; submitting = false; hasProfile = false
            self.plan = nil; today = nil; progress = nil; offline = false
            return
        }
        // генерация миссии на сервере может занять время, прогресс грузим параллельно
        // (задачи остаются на главном акторе, а пока ждут сеть – идут одновременно)
        let todayCall = Task { try await api.today() }
        let progressCall = Task { try await api.progress() }
        let today = try await todayCall.value
        let progress = try await progressCall.value
        // после перерыва сервер пересобирает план при запросе today – тогда план нужен свежий
        let fresh = today.planRebuilt ? (try await api.plan() ?? plan) : plan
        cache.plan = fresh
        cache.today = today
        cache.progress = progress
        loading = false; submitting = false; hasProfile = true; offline = false; error = nil
        self.plan = fresh
        self.today = today
        self.progress = progress
        if progress.doneToday { session.lastPassedDay = todayString }
        rescheduleReminder()
    }

    @discardableResult
    func createProfile(_ req: ProfileRequest) -> Task<Void, Never> {
        launchSafely("Не удалось составить план. Попробуй ещё раз.") {
            self.submitting = true
            self.error = nil
            _ = try await self.api.createProfile(req)
            self.changingArea = false
            self.evaluation = nil
            try await self.refresh()
        }
    }

    func startChangeArea() { changingArea = true; error = nil }

    func cancelChangeArea() { changingArea = false; error = nil }

    @discardableResult
    func submitAnswer(_ text: String) -> Task<Void, Never>? {
        guard let mission = today?.mission else { return nil }
        return launchSafely("Не удалось проверить ответ. Попробуй ещё раз.") {
            self.submitting = true
            self.error = nil
            let ev = try await self.api.answer(AnswerRequest(missionId: mission.id, answer: text))
            if ev.passed {
                self.session.lastPassedDay = self.todayString
                self.rescheduleReminder()
            }
            self.submitting = false
            self.evaluation = ev
        }
    }

    // После разбора ответа: убрать оценку и подтянуть следующую миссию, план и прогресс
    @discardableResult
    func next() -> Task<Void, Never> {
        launchSafely("Нет связи с сервером.") {
            try await self.refresh()
            self.evaluation = nil
        }
    }

    // ---------- Настройки ----------

    // Новая цель – сервер пересобирает непройденную часть плана
    @discardableResult
    func saveSettings(goal: String, minutesPerDay: Int, daysPerWeek: Int) -> Task<Void, Never> {
        let trimmed = goal.trimmingCharacters(in: .whitespaces)
        let replans = trimmed != plan?.goal
        return launchSafely("Не удалось сохранить настройки.") {
            self.submitting = true
            self.error = nil
            _ = try await self.api.updateSettings(SettingsRequest(
                goal: trimmed, minutesPerDay: minutesPerDay, daysPerWeek: daysPerWeek))
            try await self.refresh()
            self.notice = replans ? "План пересобран под новую цель" : "Настройки сохранены"
        }
    }

    // Вопросы мини-теста; nil – не удалось загрузить (тогда тест можно пропустить)
    func loadQuiz(area: ItArea) async -> [QuizQuestionDto]? {
        do {
            return try await api.quiz(area: area)
        } catch is SessionExpired {
            signOut(notice: "Сессия истекла, войди снова.")
            return nil
        } catch {
            return nil
        }
    }

    // minutes – время в минутах от полуночи, nil – выключить напоминания
    func setReminder(_ minutes: Int?) {
        session.reminderMinutes = minutes
        reminderMinutes = minutes
        rescheduleReminder()
    }

    // Обновить запланированные напоминания (при открытии приложения и после урока)
    func rescheduleReminder() {
        guard let minutes = session.reminderMinutes, session.token != nil else {
            reminders.cancel()
            return
        }
        reminders.schedule(hour: minutes / 60, minute: minutes % 60, skipToday: session.lastPassedDay == todayString)
    }

    // ---------- Профиль на устройстве ----------

    func updateName(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        session.name = trimmed.isEmpty ? nil : trimmed
        userName = session.name
        notice = "Профиль сохранён"
    }

    // file – уже сохранённый файл (AvatarStore.save), nil – удалить фото
    func setAvatar(_ file: String?) {
        let old = session.avatarFile
        if old != file { AvatarStore.delete(old) }
        session.avatarFile = file
        avatarFile = file
    }

    func avatarFailed() { notice = "Не удалось загрузить фото" }

    @discardableResult
    func deleteAccount() -> Task<Void, Never> {
        launchSafely("Не удалось удалить аккаунт.") {
            try await self.api.deleteAccount()
            self.cache.clear()
            self.setReminder(nil)
            self.setAvatar(nil)
            self.resetState()
            self.signedIn = true
            self.userName = self.session.name
            self.notice = "Аккаунт и данные удалены"
        }
    }

    func consumeNotice() { notice = nil }
}

// ---------- Чат «Застрял» ----------

@Observable
@MainActor
final class ChatViewModel {
    private(set) var missionId: String?
    private(set) var messages: [ChatMessage] = []
    private(set) var sending = false
    var draft = "" // текст, который вернуть в поле ввода, если отправка не удалась
    private(set) var error: String?

    @ObservationIgnored private let api: MentorBackend

    init(api: MentorBackend) {
        self.api = api
    }

    // Для каждой миссии – свой разговор
    func open(missionId: String) {
        guard self.missionId != missionId else { return }
        self.missionId = missionId
        messages = []
        sending = false
        draft = ""
        error = nil
    }

    @discardableResult
    func send(_ text: String) -> Task<Void, Never>? {
        guard let missionId else { return nil }
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !sending else { return nil }
        messages.append(ChatMessage(role: .user, text: question))
        let history = messages
        sending = true
        draft = ""
        error = nil
        return Task {
            do {
                let reply = try await api.chat(ChatRequest(missionId: missionId, messages: history)).reply
                messages.append(ChatMessage(role: .mentor, text: reply))
                sending = false
            } catch {
                switch error {
                case is SessionExpired: self.error = "Сессия истекла, войди снова."
                case let e as ServerMessage: self.error = e.message
                default: self.error = "Не удалось получить ответ. Проверь интернет."
                }
                // убираем неотправленный вопрос и возвращаем его в поле ввода
                if !messages.isEmpty { messages.removeLast() }
                sending = false
                draft = question
            }
        }
    }
}
