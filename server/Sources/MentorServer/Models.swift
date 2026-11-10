import Vapor

// DTO API. Названия полей и значения enum совпадают с ios/Mento/Core/Models.swift.

public enum ItArea: String, Codable, CaseIterable, Sendable {
    case frontend = "FRONTEND"
    case backend = "BACKEND"
    case mobile = "MOBILE"

    public var title: String {
        switch self {
        case .frontend: "Веб-фронтенд"
        case .backend: "Бэкенд"
        case .mobile: "Мобильная разработка"
        }
    }
}

public enum Level: String, Codable, Sendable {
    case beginner = "BEGINNER"
    case continuing = "CONTINUING"
}

public enum MissionStatus: String, Codable, Sendable {
    case todo = "TODO"
    case done = "DONE"
}

public struct ProfileRequest: Content, Equatable {
    public var area: ItArea
    public var goal: String
    public var level: Level
    public var minutesPerDay: Int
    public var daysPerWeek: Int

    public init(area: ItArea, goal: String, level: Level, minutesPerDay: Int, daysPerWeek: Int) {
        self.area = area; self.goal = goal; self.level = level
        self.minutesPerDay = minutesPerDay; self.daysPerWeek = daysPerWeek
    }
}

public struct SourceRef: Content, Equatable {
    public var title: String
    public var url: String
}

public struct MissionDto: Content, Equatable {
    public var id: String
    public var week: Int
    public var day: Int
    public var title: String
    public var topic: String
    public var material: SourceRef
    public var task: String
    public var minutes: Int
    public var status: MissionStatus
    public var review: Bool
    public var code: Bool             // в ответе нужно написать код
    public var availableFrom: String? // для повторений: дата (yyyy-MM-dd), раньше которой миссия не откроется
}

public struct WeekDto: Content, Equatable {
    public var index: Int
    public var title: String
    public var missions: [MissionDto]
}

public struct PlanDto: Content, Equatable {
    public var version: Int
    public var area: ItArea
    public var goal: String
    public var weeks: [WeekDto]
    public var level: Level
    public var minutesPerDay: Int
    public var daysPerWeek: Int
}

public struct TodayDto: Content, Equatable {
    public var mission: MissionDto?
    public var message: String
    public var planRebuilt: Bool
}

public struct AnswerRequest: Content {
    public var missionId: String
    public var answer: String

    public init(missionId: String, answer: String) {
        self.missionId = missionId; self.answer = answer
    }
}

public struct EvaluationDto: Content, Equatable {
    public var score: Int
    public var passed: Bool
    public var feedback: String
    public var gaps: [String]
    public var streak: Int
}

public struct ProgressDto: Content, Equatable {
    public var streak: Int
    public var doneMissions: Int
    public var totalMissions: Int
    public var planVersion: Int
    public var gaps: [String]
    public var weekActivity: [Bool] // пн…вс текущей недели: был ли засчитанный урок
    public var doneToday: Bool
    public var reviewsDue: Int      // повторения, у которых уже наступил срок
}

public struct ErrorDto: Content {
    public var error: String
}

// ---------- Вход ----------

public struct GoogleAuthRequest: Content {
    public var idToken: String
    public init(idToken: String) { self.idToken = idToken }
}

// Вход без Google – только для разработки (на сервере включается AUTH_DEV=true)
public struct DevAuthRequest: Content {
    public var deviceId: String
    public init(deviceId: String) { self.deviceId = deviceId }
}

// Регистрация и вход по email и паролю
public struct RegisterRequest: Content {
    public var name: String
    public var email: String
    public var password: String
    public init(name: String, email: String, password: String) {
        self.name = name; self.email = email; self.password = password
    }
}

public struct LoginRequest: Content {
    public var email: String
    public var password: String
    public init(email: String, password: String) {
        self.email = email; self.password = password
    }
}

public struct AuthResponse: Content {
    public var token: String
    public var userId: String
    public var name: String?
}

// ---------- Настройки ----------

public struct SettingsRequest: Content {
    public var goal: String
    public var minutesPerDay: Int
    public var daysPerWeek: Int
    public init(goal: String, minutesPerDay: Int, daysPerWeek: Int) {
        self.goal = goal; self.minutesPerDay = minutesPerDay; self.daysPerWeek = daysPerWeek
    }
}

// ---------- Чат «Застрял» (F5) ----------

public enum ChatRole: String, Codable, Sendable {
    case user = "USER"
    case mentor = "MENTOR"
}

public struct ChatMessage: Content, Equatable {
    public var role: ChatRole
    public var text: String
    public init(role: ChatRole, text: String) { self.role = role; self.text = text }
}

public struct ChatRequest: Content {
    public var missionId: String
    public var messages: [ChatMessage]
    public init(missionId: String, messages: [ChatMessage]) {
        self.missionId = missionId; self.messages = messages
    }
}

public struct ChatReply: Content {
    public var reply: String
}

// ---------- Ошибки API ----------

// Ошибка с понятным человеку текстом: превращается в ответ { "error": "..." } с нужным статусом
public enum APIError: Error, Equatable {
    case badRequest(String)
    case unauthorized(String)
    case notFound(String)
    case conflict(String)
    case tooManyRequests(String)

    public var status: HTTPResponseStatus {
        switch self {
        case .badRequest: .badRequest
        case .unauthorized: .unauthorized
        case .notFound: .notFound
        case .conflict: .conflict
        case .tooManyRequests: .tooManyRequests
        }
    }

    public var message: String {
        switch self {
        case .badRequest(let m), .unauthorized(let m), .notFound(let m), .conflict(let m), .tooManyRequests(let m): m
        }
    }
}
