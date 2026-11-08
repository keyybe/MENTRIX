import Foundation
import Logging

// Планировщик: работает по правилам и не зависит от ИИ.
enum Planner {
    private static func pool(_ sources: [Source], _ p: ProfileRequest) -> [(source: Source, task: TaskDef)] {
        sources
            .filter { $0.area == p.area && !(p.level == .continuing && $0.basic) }
            .flatMap { s in s.tasks.map { (s, $0) } }
    }

    static func build(_ sources: [Source], _ p: ProfileRequest) -> [Mission] {
        pool(sources, p)
            .prefix(MentorService.weeks * p.daysPerWeek)
            .map { Mission(sourceId: $0.source.id, task: $0.task, minutes: p.minutesPerDay) }
    }

    // Больше занятий в неделю – добираем в план ещё не использованные задания из базы
    static func extend(_ sources: [Source], _ st: inout UserState) {
        let target = MentorService.weeks * st.profile.daysPerWeek
        let lessons = st.missions.filter { !$0.review }
        let used = Set(lessons.map { "\($0.sourceId)\u{0}\($0.task.title)" })
        let minutes = st.profile.minutesPerDay
        st.missions += pool(sources, st.profile)
            .filter { !used.contains("\($0.source.id)\u{0}\($0.task.title)") }
            .prefix(max(target - lessons.count, 0))
            .map { Mission(sourceId: $0.source.id, task: $0.task, minutes: minutes) }
    }

    static func reflow(_ missions: inout [Mission], daysPerWeek: Int) {
        for i in missions.indices {
            missions[i].week = i / daysPerWeek + 1
            missions[i].day = i % daysPerWeek + 1
        }
    }
}

public final class MentorService: Sendable {
    public static let weeks = 8          // длина плана
    public static let pass = 60          // порог зачёта, %
    public static let pauseDays = 3      // после стольких дней паузы план пересобирается
    public static let maxAttempts = 2    // после двух неудач идём дальше, тема вернётся повторением
    public static let minMinutes = 15    // диапазон времени в день (такой же у ползунка в приложении)
    public static let maxMinutes = 40
    public static let maxAnswer = 4000   // символов в ответе
    public static let minWords = 3       // короче – не засчитываем, что бы ни сказала модель
    public static let llmDailyLimit = 40 // запросов к внешней модели на человека в день, дальше – офлайн-режим
    public static let chatHistory = 12   // сколько последних сообщений чата отправляем модели
    public static let maxChatMessage = 2000
    public static let keepDoneDates = 60 // сколько дней активности хранить
    public static let pregenerateCount = 2 // сколько следующих заданий держать готовыми
    public static let reviewDays = [1, 3, 7] // интервалы повторения ошибочной темы, дней

    private let sources: [String: Source]
    private let allSources: [Source]
    private let llm: any LlmClient
    private let store: any UserStore
    private let offline: any LlmClient
    private let today: @Sendable () -> Day
    private let locks = KeyedLock()
    // фоновая генерация следующих заданий: человек не ждёт ИИ, когда открывает миссию
    private let background = BackgroundTasks()

    public init(
        sources: [Source],
        llm: any LlmClient,
        store: any UserStore = InMemoryUserStore(),
        offline: any LlmClient = RuleBasedLlm(),
        today: @escaping @Sendable () -> Day = { Day.today() }
    ) {
        self.sources = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.allSources = sources
        self.llm = llm
        self.store = store
        self.offline = offline
        self.today = today
    }

    // Для тестов: дождаться фоновой генерации
    public func awaitBackground() async {
        await background.waitAll()
    }

    // Все операции одного пользователя выполняются по очереди: прочитали состояние, изменили, сохранили.
    // Блокировка в памяти процесса – сервер рассчитан на один экземпляр.
    private func withUser<T>(_ userId: String, save: Bool = true, _ body: (inout UserState) async throws -> T) async throws -> T {
        try await locks.withLock(userId) {
            guard var st = try await store.load(userId) else { throw APIError.notFound("Профиль не найден") }
            let result = try await body(&st)
            if save { try await store.save(userId, st) }
            return result
        }
    }

    private struct PregenTarget: Sendable {
        let missionId: String
        let base: TaskDef
        let topic: String
        let profile: ProfileRequest
        let client: any LlmClient
        let previous: [String]
    }

    // Заранее генерирует задания для следующих уроков. Запрос к модели идёт без блокировки пользователя,
    // а результат сохраняется, только если задание ещё не показывали человеку.
    private func pregenerate(_ userId: String) async {
        await background.run { [self] in
            for _ in 0..<Self.pregenerateCount {
                let reserved = try? await withUser(userId) { st -> PregenTarget? in
                    guard let i = st.missions.firstIndex(where: { $0.status == .todo && !$0.taskGenerated && !$0.review }) else {
                        return nil
                    }
                    let m = st.missions[i]
                    let previous = st.missions
                        .filter { $0.sourceId == m.sourceId && $0.taskGenerated && $0.id != m.id }
                        .map(\.task.prompt)
                    // резервируем миссию, чтобы параллельная генерация её не взяла
                    st.missions[i].taskGenerated = true
                    st.missions[i].pregenerating = true
                    return PregenTarget(
                        missionId: m.id, base: m.task, topic: try source(m).title,
                        profile: st.profile, client: llmFor(&st), previous: previous
                    )
                }
                guard let target = reserved ?? nil else { return }

                let generated = (try? await target.client.generateTask(
                    base: target.base, topic: target.topic, level: target.profile.level,
                    area: target.profile.area, previous: target.previous
                )) ?? target.base

                _ = try? await withUser(userId) { st in
                    guard let i = st.missions.firstIndex(where: { $0.id == target.missionId }) else { return }
                    // человек уже увидел базовое задание – не подменяем его
                    if st.missions[i].pregenerating { st.missions[i].task = generated }
                    st.missions[i].pregenerating = false
                }
            }
        }
    }

    private func source(_ m: Mission) throws -> Source {
        guard let s = sources[m.sourceId] else { throw ConfigError(message: "Нет источника \(m.sourceId)") }
        return s
    }

    private func dto(_ m: Mission) throws -> MissionDto {
        let s = try source(m)
        return MissionDto(
            id: m.id, week: m.week, day: m.day, title: m.task.title, topic: s.title,
            material: SourceRef(title: s.title, url: s.url), task: m.task.prompt,
            minutes: m.minutes, status: m.status, review: m.review, code: m.task.code,
            availableFrom: m.notBefore?.description
        )
    }

    // Внешняя модель, пока не исчерпан дневной лимит, затем – офлайн-проверка
    private func llmFor(_ st: inout UserState) -> any LlmClient {
        let now = today()
        if st.llmDay != now {
            st.llmDay = now
            st.llmCalls = 0
        }
        if st.llmCalls >= Self.llmDailyLimit { return offline }
        st.llmCalls += 1
        return llm
    }

    private func event(_ userId: String, _ type: EventType) async throws {
        try await store.event(userId, type, today())
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    public func createProfile(_ userId: String, _ req: ProfileRequest) async throws -> PlanDto {
        if req.goal.trimmed.isEmpty { throw APIError.badRequest("Цель не указана") }
        var profile = req
        profile.goal = String(req.goal.trimmed.prefix(200))
        profile.daysPerWeek = Self.clamp(req.daysPerWeek, 1...7)
        profile.minutesPerDay = Self.clamp(req.minutesPerDay, Self.minMinutes...Self.maxMinutes)

        var missions = Planner.build(allSources, profile)
        if missions.isEmpty { throw APIError.badRequest("Для выбранной области пока нет материалов") }
        Planner.reflow(&missions, daysPerWeek: profile.daysPerWeek)
        let st = UserState(profile: profile, missions: missions, lastActive: today())
        try await locks.withLock(userId) { try await store.save(userId, st) }
        try await event(userId, .profile)
        await pregenerate(userId)
        return try planDto(st)
    }

    public func plan(_ userId: String) async throws -> PlanDto {
        try await withUser(userId, save: false) { try planDto($0) }
    }

    public func updateSettings(_ userId: String, _ req: SettingsRequest) async throws -> PlanDto {
        try await withUser(userId) { st in
            if req.goal.trimmed.isEmpty { throw APIError.badRequest("Цель не указана") }
            st.profile.goal = String(req.goal.trimmed.prefix(200))
            st.profile.minutesPerDay = Self.clamp(req.minutesPerDay, Self.minMinutes...Self.maxMinutes)
            st.profile.daysPerWeek = Self.clamp(req.daysPerWeek, 1...7)
            for i in st.missions.indices where st.missions[i].status == .todo {
                st.missions[i].minutes = st.profile.minutesPerDay
            }
            Planner.extend(allSources, &st)
            Planner.reflow(&st.missions, daysPerWeek: st.profile.daysPerWeek)
            return try planDto(st)
        }
    }

    public func today(_ userId: String) async throws -> TodayDto {
        let dto = try await withUser(userId) { st -> TodayDto in
            let now = today()
            let paused = st.lastActive.days(until: now)
            let rebuilt = paused >= Self.pauseDays && rebuildAfterPause(&st, now)
            // повторение, у которого наступил срок, идёт раньше нового урока
            let available = st.missions.indices.filter { st.missions[$0].isAvailable(on: now) }
            guard let i = available.first(where: { st.missions[$0].review }) ?? available.first else {
                let next = st.missions.filter { $0.status == .todo }.compactMap(\.notBefore).min()
                let message = next.map { "На сегодня всё! Следующее повторение откроется \($0)." }
                    ?? "План пройден! Скоро появятся новые темы."
                return TodayDto(mission: nil, message: message, planRebuilt: rebuilt)
            }

            // Миссию отдаём сразу, без ожидания ИИ: если фоновая генерация не успела – берём базовое задание.
            // Показанное задание больше не меняется, иначе ответ проверялся бы по другому вопросу.
            st.missions[i].taskGenerated = true
            st.missions[i].pregenerating = false

            let message = if rebuilt {
                "План пересобран с учётом перерыва."
            } else if st.missions[i].review {
                "Повторение: закрепим тему, в которой были ошибки."
            } else {
                "Миссия на сегодня готова."
            }
            return TodayDto(mission: try dto(st.missions[i]), message: message, planRebuilt: rebuilt)
        }
        try await event(userId, .open)
        await pregenerate(userId)
        return dto
    }

    public func answer(_ userId: String, _ req: AnswerRequest) async throws -> EvaluationDto {
        if req.answer.trimmed.isEmpty { throw APIError.badRequest("Пустой ответ") }
        if req.answer.count > Self.maxAnswer { throw APIError.badRequest("Ответ слишком длинный (до \(Self.maxAnswer) символов)") }

        let (result, passed) = try await withUser(userId) { st -> (EvaluationDto, Bool) in
            guard let i = st.missions.firstIndex(where: { $0.id == req.missionId }) else {
                throw APIError.notFound("Миссия не найдена")
            }
            if st.missions[i].status == .done { throw APIError.badRequest("Миссия уже выполнена") }

            let task = st.missions[i].task
            let ev = try await llmFor(&st).evaluate(task: task, answer: req.answer, level: st.profile.level)
            let score = req.answer.trimmed.wordCount < Self.minWords ? min(ev.score, Self.pass - 1) : ev.score

            let now = today()
            st.lastActive = now
            st.missions[i].attempts += 1
            let passed = score >= Self.pass
            var feedback = ev.feedback
            let topic = try source(st.missions[i]).title
            if passed {
                st.missions[i].status = .done
                st.gaps.removeAll { $0 == topic }
                bumpStreak(&st, now)
                if !st.doneDates.contains(now.description) {
                    st.doneDates.append(now.description)
                    if st.doneDates.count > Self.keepDoneDates { st.doneDates.removeFirst(st.doneDates.count - Self.keepDoneDates) }
                }
                // успешное повторение – следующее через больший интервал, пока интервалы не кончатся
                let m = st.missions[i]
                if m.review && (1..<Self.reviewDays.count).contains(m.reviewStage) {
                    scheduleReview(&st, m, stage: m.reviewStage + 1, now)
                }
            } else {
                if !st.gaps.contains(topic) { st.gaps.append(topic) }
                if st.missions[i].attempts >= Self.maxAttempts {
                    st.missions[i].status = .done
                    scheduleReview(&st, st.missions[i], stage: 1, now)
                    feedback += " Идём дальше, к этой теме вернёмся в повторении через \(Self.reviewDays[0]) дн."
                }
            }
            return (EvaluationDto(score: score, passed: passed, feedback: feedback, gaps: ev.gaps, streak: st.streak), passed)
        }
        try await event(userId, passed ? .answerPass : .answerFail)
        await pregenerate(userId)
        return result
    }

    // Чат «Застрял»: наводящие подсказки по текущему заданию, без готового ответа
    public func chat(_ userId: String, _ req: ChatRequest) async throws -> ChatReply {
        let history = Array(req.messages.suffix(Self.chatHistory))
        guard let last = history.last, last.role == .user else { throw APIError.badRequest("Нет вопроса") }
        if history.contains(where: { $0.text.trimmed.isEmpty || $0.text.count > Self.maxChatMessage }) {
            throw APIError.badRequest("Сообщение пустое или длиннее \(Self.maxChatMessage) символов")
        }
        let reply = try await withUser(userId) { st in
            guard let m = st.missions.first(where: { $0.id == req.missionId }) else { throw APIError.notFound("Миссия не найдена") }
            return try await llmFor(&st).hint(task: m.task, topic: try source(m).title, history: history, level: st.profile.level)
        }
        try await event(userId, .chat)
        return ChatReply(reply: reply)
    }

    public func progress(_ userId: String) async throws -> ProgressDto {
        try await withUser(userId, save: false) { st in
            let now = today()
            return ProgressDto(
                streak: st.streak,
                doneMissions: st.missions.count { $0.status == .done },
                totalMissions: st.missions.count,
                planVersion: st.version,
                gaps: st.gaps,
                weekActivity: weekActivity(st, now),
                doneToday: st.lastDone == now,
                reviewsDue: st.missions.count { $0.review && $0.isAvailable(on: now) }
            )
        }
    }

    // Пн…Вс текущей недели: был ли в этот день засчитанный урок
    private func weekActivity(_ st: UserState, _ now: Day) -> [Bool] {
        let monday = now.monday
        let done = Set(st.doneDates)
        return (0..<7).map { done.contains(monday.adding(days: $0).description) }
    }

    public func delete(_ userId: String) async throws {
        try await locks.withLock(userId) { try await store.delete(userId) }
    }

    public func stats() async throws -> StatsDto {
        try await store.stats(today: today())
    }

    private func bumpStreak(_ st: inout UserState, _ now: Day) {
        st.streak = switch st.lastDone {
        case now: st.streak
        case now.adding(days: -1): st.streak + 1
        default: 1
        }
        st.lastDone = now
    }

    // Повторение ставим в план через reviewDays[stage-1] дней. В списке оно стоит примерно там же,
    // где окажутся занятия этого дня, а notBefore не даёт открыть его раньше срока.
    private func scheduleReview(_ st: inout UserState, _ m: Mission, stage: Int, _ now: Day) {
        let days = Self.reviewDays[stage - 1]
        let firstTodo = st.missions.firstIndex { $0.status == .todo } ?? st.missions.count
        let pos = min(firstTodo + days, st.missions.count)
        st.missions.insert(reviewOf(m, stage: stage, notBefore: now.adding(days: days)), at: pos)
        Planner.reflow(&st.missions, daysPerWeek: st.profile.daysPerWeek)
    }

    private func reviewOf(_ m: Mission, stage: Int, notBefore: Day?) -> Mission {
        var task = m.task
        let prefix = "Повторение: "
        if task.title.hasPrefix(prefix) { task.title.removeFirst(prefix.count) }
        return Mission(sourceId: m.sourceId, task: task, minutes: m.minutes, review: true,
                       taskGenerated: true, notBefore: notBefore, reviewStage: stage)
    }

    private func rebuildAfterPause(_ st: inout UserState, _ now: Day) -> Bool {
        st.lastActive = now
        st.version += 1
        let lastDone = st.missions.last { $0.status == .done && !$0.review }
        let firstTodo = st.missions.firstIndex { $0.status == .todo }
        // если повторение уже ждёт по интервалу, второе не добавляем
        let reviewDue = st.missions.contains { $0.review && $0.isAvailable(on: now) }
        if let lastDone, let firstTodo, !reviewDue {
            // одно повторение после перерыва, без цепочки интервалов
            st.missions.insert(reviewOf(lastDone, stage: Self.reviewDays.count, notBefore: nil), at: firstTodo)
        }
        Planner.reflow(&st.missions, daysPerWeek: st.profile.daysPerWeek)
        return true
    }

    private func planDto(_ st: UserState) throws -> PlanDto {
        var order: [Int] = []
        var byWeek: [Int: [Mission]] = [:]
        for m in st.missions {
            if byWeek[m.week] == nil { order.append(m.week) }
            byWeek[m.week, default: []].append(m)
        }
        let weeks = try order.sorted().map { w in
            let ms = byWeek[w] ?? []
            let title = try ms.first.map { "Неделя \(w): \(try source($0).title)" } ?? "Неделя \(w)"
            return WeekDto(index: w, title: title, missions: try ms.map(dto))
        }
        let p = st.profile
        return PlanDto(version: st.version, area: p.area, goal: p.goal, weeks: weeks,
                       level: p.level, minutesPerDay: p.minutesPerDay, daysPerWeek: p.daysPerWeek)
    }
}

// Очередь операций по ключу: пока одна операция пользователя выполняется, следующие ждут
actor KeyedLock {
    private var held: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    private func acquire(_ key: String) async {
        if held.insert(key).inserted { return }
        await withCheckedContinuation { waiters[key, default: []].append($0) }
    }

    private func release(_ key: String) {
        if var queue = waiters[key], !queue.isEmpty {
            // блокировка переходит следующему в очереди
            let next = queue.removeFirst()
            waiters[key] = queue.isEmpty ? nil : queue
            next.resume()
        } else {
            held.remove(key)
        }
    }

    nonisolated func withLock<T>(_ key: String, _ body: () async throws -> T) async throws -> T {
        await acquire(key)
        do {
            let result = try await body()
            await release(key)
            return result
        } catch {
            await release(key)
            throw error
        }
    }
}

// Фоновые задачи сервиса; тесты могут дождаться их окончания
actor BackgroundTasks {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func run(_ work: @escaping @Sendable () async -> Void) {
        let id = UUID()
        tasks[id] = Task.detached { [weak self] in
            await work()
            await self?.finish(id)
        }
    }

    private func finish(_ id: UUID) {
        tasks[id] = nil
    }

    func waitAll() async {
        while let task = tasks.values.first {
            await task.value
        }
    }
}
