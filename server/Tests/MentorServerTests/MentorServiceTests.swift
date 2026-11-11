import Foundation
import Testing
@testable import MentorServer

@Suite struct MentorServiceTests {
    let clock = Clock()
    let llm = FakeLlm()
    let store = InMemoryUserStore()
    let uid = "test:user"

    func makeService(llm: (any LlmClient)? = nil, offline: any LlmClient = RuleBasedLlm()) -> MentorService {
        let clock = clock
        return MentorService(sources: sources, llm: llm ?? self.llm, store: store, offline: offline, today: { clock.now })
    }

    // ---------- База источников ----------

    @Test func sourcesAreValid() {
        #expect(Set(sources.map(\.id)).count == sources.count, "id источников должны быть уникальны")
        for area in ItArea.allCases {
            let tasks = sources.filter { $0.area == area }.flatMap(\.tasks)
            #expect(tasks.count >= MentorService.weeks, "мало заданий для \(area)")
        }
        for s in sources {
            #expect(s.url.hasPrefix("https://"), "\(s.id): ссылка должна быть https")
            #expect(!s.tasks.isEmpty, "\(s.id): нет заданий")
            for t in s.tasks {
                #expect(!t.title.trimmed.isEmpty && !t.prompt.trimmed.isEmpty, "\(s.id): пустое задание")
                #expect(!t.keywords.isEmpty, "\(s.id) / \(t.title): нет ключевых понятий")
            }
        }
    }

    // ---------- План ----------

    @Test func planIsBuiltFromCuratedSources() async throws {
        let service = makeService()
        let plan = try await service.createProfile(uid, profile(.backend, days: 5))
        let missions = plan.missions
        let backendTitles = Set(sources.filter { $0.area == .backend }.map(\.title))

        #expect(plan.area == .backend && plan.version == 1)
        #expect(missions.count == MentorService.weeks * 5)
        #expect(missions.allSatisfy { backendTitles.contains($0.topic) })
        #expect(missions.first?.week == 1 && missions.first?.day == 1)
        #expect(plan.weeks.map(\.index) == Array(1...MentorService.weeks))
        #expect(plan.weeks.allSatisfy { $0.missions.count == 5 })
    }

    @Test func profileInputIsNormalized() async throws {
        let service = makeService()
        var request = profile(days: 12, minutes: 500)
        request.goal = "  " + String(repeating: "я", count: 300) + "  "
        let plan = try await service.createProfile(uid, request)
        #expect(plan.daysPerWeek == 7)
        #expect(plan.minutesPerDay == MentorService.maxMinutes)
        #expect(plan.goal.count == 200)

        request.goal = "   "
        #expect(await apiError { try await service.createProfile(uid, request) }?.status == .badRequest)
    }

    @Test func continuingLevelSkipsBasics() async throws {
        let service = makeService()
        let plan = try await service.createProfile(uid, profile(.frontend, level: .continuing))
        let basics = Set(sources.filter { $0.area == .frontend && $0.basic }.map(\.title))
        #expect(!plan.missions.isEmpty)
        #expect(plan.missions.allSatisfy { !basics.contains($0.topic) })
    }

    @Test func stateSurvivesNewServiceInstance() async throws {
        let first = makeService()
        _ = try await first.createProfile(uid, profile())
        try await first.answerToday(uid, goodAnswer)
        await first.awaitBackground()

        let second = makeService()
        let progress = try await second.progress(uid)
        #expect(progress.doneMissions == 1)
        #expect(progress.streak == 1)
    }

    @Test func unknownUserGetsNotFound() async {
        let service = makeService()
        #expect(await apiError { try await service.today("nobody") }?.status == .notFound)
        #expect(await apiError { try await service.plan("nobody") }?.status == .notFound)
    }

    // ---------- Ответы и серия ----------

    @Test func goodAnswerCompletesMissionAndStartsStreak() async throws {
        let service = makeService()
        _ = try await service.createProfile(uid, profile())
        let (mission, result) = try await service.answerToday(uid, goodAnswer)

        #expect(result.passed && result.score == 100 && result.streak == 1)
        let progress = try await service.progress(uid)
        #expect(progress.doneMissions == 1 && progress.doneToday)

        let again = await apiError { try await service.answer(uid, AnswerRequest(missionId: mission.id, answer: goodAnswer)) }
        #expect(again == .badRequest("Миссия уже выполнена"))

        let next = try await service.today(uid).mission
        #expect(next != nil && next?.id != mission.id)
    }

    @Test func streakGrowsOnNextDayAndResetsAfterGap() async throws {
        let service = makeService()
        _ = try await service.createProfile(uid, profile())
        #expect(try await service.answerToday(uid, goodAnswer).1.streak == 1)
        // второй урок в тот же день серию не увеличивает
        #expect(try await service.answerToday(uid, goodAnswer).1.streak == 1)
        clock.advance(1)
        #expect(try await service.answerToday(uid, goodAnswer).1.streak == 2)
        clock.advance(2) // пропущен день
        #expect(try await service.answerToday(uid, goodAnswer).1.streak == 1)
    }

    @Test func tooShortAnswerNeverPasses() async throws {
        let service = makeService()
        _ = try await service.createProfile(uid, profile())
        let (_, result) = try await service.answerToday(uid, "GOOD")
        #expect(!result.passed)
        #expect(result.score < MentorService.pass)
    }

    @Test func answerValidation() async throws {
        let service = makeService()
        _ = try await service.createProfile(uid, profile())
        let id = try #require(try await service.today(uid).mission).id

        #expect(await apiError { try await service.answer(uid, AnswerRequest(missionId: id, answer: "  ")) }?.status == .badRequest)
        let long = String(repeating: "a", count: MentorService.maxAnswer + 1)
        #expect(await apiError { try await service.answer(uid, AnswerRequest(missionId: id, answer: long)) }?.status == .badRequest)
        #expect(await apiError { try await service.answer(uid, AnswerRequest(missionId: "nope", answer: goodAnswer)) }?.status == .notFound)
    }

    @Test func concurrentAnswersToSameMissionCountOnce() async throws {
        let service = makeService()
        _ = try await service.createProfile(uid, profile())
        let id = try #require(try await service.today(uid).mission).id

        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    (try? await service.answer(uid, AnswerRequest(missionId: id, answer: goodAnswer))) != nil
                }
            }
            return await group.reduce(into: [Bool]()) { $0.append($1) }
        }
        #expect(results.count { $0 } == 1)
        #expect(try await service.progress(uid).doneMissions == 1)
    }

    // ---------- Повторения и перестройка плана ----------

    @Test func twoBadAnswersMoveOnAndScheduleReview() async throws {
        let service = makeService()
        _ = try await service.createProfile(uid, profile())
        let (mission, first) = try await service.answerToday(uid, badAnswer)
        #expect(!first.passed)
        #expect(try await service.today(uid).mission?.id == mission.id, "после первой неудачи миссия остаётся")

        let second = try await service.answer(uid, AnswerRequest(missionId: mission.id, answer: badAnswer))
        #expect(!second.passed && second.feedback.contains("повторении"))

        let plan = try await service.plan(uid)
        let review = try #require(plan.missions.first { $0.review })
        #expect(review.title == mission.title)
        #expect(review.availableFrom == clock.now.adding(days: MentorService.reviewDays[0]).description)
        #expect(try await service.progress(uid).gaps == [mission.topic])

        // сегодня повторение ещё закрыто, завтра идёт раньше нового урока
        #expect(try await service.today(uid).mission?.review == false)
        clock.advance(1)
        #expect(try await service.today(uid).mission?.id == review.id)
        #expect(try await service.progress(uid).reviewsDue == 1)
    }

    @Test func reviewsFollowGrowingIntervals() async throws {
        let service = makeService()
        _ = try await service.createProfile(uid, profile())
        let (mission, _) = try await service.answerToday(uid, badAnswer)
        _ = try await service.answer(uid, AnswerRequest(missionId: mission.id, answer: badAnswer))

        var expectedDay = clock.now
        for (stage, days) in MentorService.reviewDays.enumerated() {
            expectedDay = expectedDay.adding(days: days)
            let reviews = try await service.plan(uid).missions.filter { $0.review && $0.status == .todo }
            #expect(reviews.count == 1, "этап \(stage + 1)")
            #expect(reviews.first?.availableFrom == expectedDay.description)

            clock.advance(days)
            let (shown, result) = try await service.answerToday(uid, goodAnswer)
            #expect(shown.review && result.passed)
            expectedDay = clock.now
        }
        // после последнего интервала повторений больше нет, тема закрыта
        #expect(try await service.plan(uid).missions.allSatisfy { !$0.review || $0.status == .done })
        #expect(try await service.progress(uid).gaps.isEmpty)
    }

    @Test func longPauseRebuildsPlan() async throws {
        let service = makeService()
        _ = try await service.createProfile(uid, profile())
        let (done, _) = try await service.answerToday(uid, goodAnswer)

        clock.advance(MentorService.pauseDays)
        let today = try await service.today(uid)
        #expect(today.planRebuilt)
        #expect(today.mission?.review == true && today.mission?.title == done.title)
        #expect(try await service.plan(uid).version == 2)

        // на следующий день перестройки уже нет
        clock.advance(1)
        #expect(try await service.today(uid).planRebuilt == false)
    }

    @Test func settingsChangeMinutesAndExtendPlan() async throws {
        let service = makeService()
        let before = try await service.createProfile(uid, profile(days: 3, minutes: 20))
        try await service.answerToday(uid, goodAnswer)

        let after = try await service.updateSettings(uid, SettingsRequest(goal: "Новая цель", minutesPerDay: 30, daysPerWeek: 5))
        #expect(after.goal == "Новая цель" && after.daysPerWeek == 5)
        #expect(after.missions.count > before.missions.count)
        #expect(after.missions.filter { $0.status == .todo }.allSatisfy { $0.minutes == 30 })
        #expect(after.missions.filter { $0.status == .done }.allSatisfy { $0.minutes == 20 })
        #expect(Set(after.missions.map(\.id)).count == after.missions.count, "задания не дублируются")
        #expect(after.weeks.allSatisfy { $0.missions.count <= 5 })
    }

    // ---------- Генерация заданий ИИ ----------

    @Test func generatedTaskIsPreparedInBackgroundAndKeepsTitle() async throws {
        let service = makeService()
        let plan = try await service.createProfile(uid, profile())
        await service.awaitBackground()

        let mission = try #require(try await service.today(uid).mission)
        let base = try #require(plan.missions.first { $0.id == mission.id })
        #expect(mission.task == "AI: " + base.task)
        #expect(mission.title == base.title)
    }

    @Test func todayDoesNotWaitForAiAndShownTaskNeverChanges() async throws {
        let slow = FakeLlm(generateDelay: .milliseconds(300))
        let service = makeService(llm: slow)
        let plan = try await service.createProfile(uid, profile())

        let started = ContinuousClock.now
        let shown = try #require(try await service.today(uid).mission)
        #expect(ContinuousClock.now - started < .milliseconds(250), "today ждал генерацию")
        #expect(shown.task == plan.missions.first { $0.id == shown.id }?.task)

        await service.awaitBackground()
        let later = try #require(try await service.plan(uid).missions.first { $0.id == shown.id })
        #expect(later.task == shown.task, "показанное задание не должно меняться")
    }

    @Test func failingModelFallsBackToOffline() async throws {
        let service = makeService(llm: FallbackLlm(primary: FailingLlm(), fallback: RuleBasedLlm()))
        _ = try await service.createProfile(uid, profile())
        await service.awaitBackground()
        let (mission, result) = try await service.answerToday(uid, badAnswer)
        #expect(!result.feedback.isEmpty)
        #expect(mission.task == (try await service.plan(uid).missions.first { $0.id == mission.id }?.task))
        let reply = try await service.chat(uid, ChatRequest(missionId: mission.id, messages: [ChatMessage(role: .user, text: "помоги")]))
        #expect(reply.reply.contains("ИИ-ментор недоступен"))
    }

    @Test func dailyLlmLimitFallsBackToOffline() async throws {
        let offline = FakeLlm(generatePrefix: nil)
        let service = makeService(offline: offline)
        _ = try await service.createProfile(uid, profile())
        await service.awaitBackground()
        let id = try #require(try await service.today(uid).mission).id
        await service.awaitBackground()

        let question = ChatRequest(missionId: id, messages: [ChatMessage(role: .user, text: "подскажи")])
        for _ in 0..<(MentorService.llmDailyLimit + 5) { _ = try await service.chat(uid, question) }
        #expect(llm.calls.total == MentorService.llmDailyLimit)
        #expect(offline.calls["hint"] > 0)

        // на следующий день лимит снова доступен
        clock.advance(1)
        _ = try await service.chat(uid, question)
        #expect(llm.calls.total == MentorService.llmDailyLimit + 1)
    }

    // ---------- Чат ----------

    @Test func chatRequiresUserQuestion() async throws {
        let service = makeService()
        _ = try await service.createProfile(uid, profile())
        let id = try #require(try await service.today(uid).mission).id

        let empty = ChatRequest(missionId: id, messages: [])
        let mentorLast = ChatRequest(missionId: id, messages: [ChatMessage(role: .user, text: "?"), ChatMessage(role: .mentor, text: "ответ")])
        let blank = ChatRequest(missionId: id, messages: [ChatMessage(role: .user, text: "   ")])
        let long = ChatRequest(missionId: id, messages: [ChatMessage(role: .user, text: String(repeating: "x", count: MentorService.maxChatMessage + 1))])
        for request in [empty, mentorLast, blank, long] {
            #expect(await apiError { try await service.chat(uid, request) }?.status == .badRequest)
        }
        let ok = try await service.chat(uid, ChatRequest(missionId: id, messages: [ChatMessage(role: .user, text: "Как начать?")]))
        #expect(ok.reply == "fake hint")
    }

    // ---------- Удаление и статистика ----------

    @Test func deleteRemovesUserAndStats() async throws {
        let service = makeService()
        _ = try await service.createProfile(uid, profile())
        try await service.answerToday(uid, goodAnswer)
        await service.awaitBackground()

        var stats = try await service.stats()
        #expect(stats.users == 1 && stats.active1d == 1 && stats.profiles7d == 1 && stats.passed7d == 1)

        try await service.delete(uid)
        #expect(await apiError { try await service.plan(uid) }?.status == .notFound)
        stats = try await service.stats()
        #expect(stats == StatsDto(users: 0, active1d: 0, active7d: 0, active30d: 0, profiles7d: 0, answers7d: 0, passed7d: 0, chats7d: 0))
    }
}

// ---------- Офлайн-проверка ----------

@Suite struct RuleBasedLlmTests {
    let task = TaskDef(title: "Хеши", prompt: "Что такое хеш-функция?", keywords: ["хеш|hash", "коллизия", "детерминированн"])
    let llm = RuleBasedLlm()

    @Test func fullCoverageScoresHundred() async throws {
        let ev = try await llm.evaluate(task: task, answer: "Hash детерминированная функция, коллизия возможна редко", level: .beginner)
        #expect(ev.score == 100 && ev.gaps.isEmpty)
    }

    @Test func missingKeywordsBecomeGaps() async throws {
        let ev = try await llm.evaluate(task: task, answer: "хеш превращает данные в короткую строку фиксированной длины", level: .beginner)
        #expect(ev.score < 100)
        #expect(ev.gaps == ["коллизия", "детерминированн"])
    }

    @Test func tooShortAnswerIsCapped() async throws {
        let ev = try await llm.evaluate(task: task, answer: "хеш коллизия", level: .beginner)
        #expect(ev.score <= 30)
    }

    @Test func hintRevealsMoreWithEachQuestion() async throws {
        let one = try await llm.hint(task: task, topic: "Криптография", history: [ChatMessage(role: .user, text: "?")], level: .beginner)
        let two = try await llm.hint(task: task, topic: "Криптография",
                                     history: [ChatMessage(role: .user, text: "?"), ChatMessage(role: .mentor, text: "…"), ChatMessage(role: .user, text: "?")],
                                     level: .beginner)
        // на первый вопрос – два понятия, на второй – уже три
        #expect(one.contains("хеш") && one.contains("коллизия") && !one.contains("детерминированн"))
        #expect(two.contains("детерминированн"))
    }
}

// ---------- Календарный день ----------

@Suite struct DayTests {
    @Test func isoRoundTrip() throws {
        for text in ["1970-01-01", "2000-02-29", "2026-12-31", "2100-03-01"] {
            #expect(try #require(Day(iso: text)).description == text)
        }
        #expect(Day(iso: "2026-13-01") == nil)
        #expect(Day(iso: "nonsense") == nil)
    }

    @Test func weekdayAndArithmetic() {
        let monday = Day(2026, 11, 9)
        #expect(monday.weekdayFromMonday == 0)
        #expect(Day(2026, 11, 15).weekdayFromMonday == 6)
        #expect(Day(2026, 11, 12).monday == monday)
        #expect(Day(2026, 2, 28).adding(days: 1) == Day(2026, 3, 1))
        #expect(monday.days(until: Day(2026, 12, 9)) == 30)
    }

    @Test func codableAsString() throws {
        let data = try JSONEncoder().encode([Day(2026, 1, 5)])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-01-05\"]")
        #expect(try JSONDecoder().decode([Day].self, from: data) == [Day(2026, 1, 5)])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([Day].self, from: Data("[\"bad\"]".utf8)) }
    }
}
