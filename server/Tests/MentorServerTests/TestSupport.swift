import Foundation
import Synchronization
@testable import MentorServer

// Общие помощники для тестов сервера

let sources: [Source] = {
    do { return try SourceBase.load() } catch { fatalError("sources.json не читается: \(error)") }
}()

// Управляемые «часы»: тест сам двигает текущий день
final class Clock: Sendable {
    private let day: Mutex<Day>
    init(_ start: Day = Day(2026, 3, 2)) { day = Mutex(start) } // понедельник
    var now: Day { day.withLock { $0 } }
    func advance(_ days: Int) { day.withLock { $0 = $0.adding(days: days) } }
}

// Счётчик вызовов по имени
final class Calls: Sendable {
    private let counts = Mutex<[String: Int]>([:])
    func hit(_ name: String) { counts.withLock { $0[name, default: 0] += 1 } }
    subscript(_ name: String) -> Int { counts.withLock { $0[name] ?? 0 } }
    var total: Int { counts.withLock { $0.values.reduce(0, +) } }
}

// Последнее значение, переданное фейку
final class LastValue<T: Sendable>: Sendable {
    private let value = Mutex<T?>(nil)
    func set(_ v: T) { value.withLock { $0 = v } }
    var last: T? { value.withLock { $0 } }
}

// Предсказуемая «модель»: ответ со словом GOOD получает 100, остальные – 10
struct FakeLlm: LlmClient {
    var calls = Calls()
    var generatePrefix: String? = "AI: "
    var generateDelay: Duration?
    var draft: CourseDraft?           // что «предложит» ИИ-методист; nil – план по правилам
    let lastCourse = LastValue<CourseRequest>()

    func planCourse(_ request: CourseRequest) async throws -> CourseDraft? {
        calls.hit("plan")
        lastCourse.set(request)
        return draft
    }

    func evaluate(task: TaskDef, answer: String, level: Level) async throws -> Evaluation {
        calls.hit("evaluate")
        return answer.contains("GOOD")
            ? Evaluation(score: 100, feedback: "fake ok", gaps: [])
            : Evaluation(score: 10, feedback: "fake fail", gaps: ["что-то"])
    }

    func generateTask(base: TaskDef, topic: String, level: Level, area: ItArea, goal: String, previous: [String]) async throws -> TaskDef {
        calls.hit("generate")
        if let generateDelay { try await Task.sleep(for: generateDelay) }
        guard let generatePrefix else { return base }
        var task = base
        task.prompt = generatePrefix + base.prompt
        return task
    }

    func hint(task: TaskDef, topic: String, history: [ChatMessage], level: Level) async throws -> String {
        calls.hit("hint")
        return "fake hint"
    }
}

struct FailingLlm: LlmClient {
    struct Boom: Error {}
    func planCourse(_ request: CourseRequest) async throws -> CourseDraft? { throw Boom() }
    func evaluate(task: TaskDef, answer: String, level: Level) async throws -> Evaluation { throw Boom() }
    func generateTask(base: TaskDef, topic: String, level: Level, area: ItArea, goal: String, previous: [String]) async throws -> TaskDef { throw Boom() }
    func hint(task: TaskDef, topic: String, history: [ChatMessage], level: Level) async throws -> String { throw Boom() }
}

func profile(_ area: ItArea = .backend, level: Level = .beginner, days: Int = 5, minutes: Int = 20) -> ProfileRequest {
    ProfileRequest(area: area, goal: "Стать бэкенд-разработчиком", level: level, minutesPerDay: minutes, daysPerWeek: days)
}

let goodAnswer = "GOOD развёрнутый ответ своими словами"
let badAnswer = "не знаю что ответить"

// Ошибка API, которую бросил body, или nil
func apiError(_ body: () async throws -> some Any) async -> APIError? {
    do {
        _ = try await body()
        return nil
    } catch let error as APIError {
        return error
    } catch {
        return nil
    }
}

extension MentorService {
    // Открыть миссию дня и ответить на неё
    @discardableResult
    func answerToday(_ userId: String, _ text: String) async throws -> (MissionDto, EvaluationDto) {
        let today = try await today(userId)
        guard let mission = today.mission else { throw APIError.notFound("Нет миссии на сегодня") }
        return (mission, try await answer(userId, AnswerRequest(missionId: mission.id, answer: text)))
    }
}

// Ответы мини-теста: верно на вопросы тем right, «Не знаю» на остальные
func quizAnswers(_ area: ItArea, right: Set<String>) -> [QuizAnswer] {
    sources.filter { $0.area == area }.compactMap { s in
        s.quiz.map { QuizAnswer(id: s.id, option: right.contains(s.id) ? $0.answer : -1) }
    }
}

func title(_ sourceId: String) -> String {
    sources.first { $0.id == sourceId }?.title ?? sourceId
}

extension PlanDto {
    var missions: [MissionDto] { weeks.flatMap(\.missions) }
}
