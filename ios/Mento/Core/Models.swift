import Foundation

// DTO сервера. Названия полей и значения enum совпадают с shared/Models.kt.

nonisolated enum ItArea: String, Codable, CaseIterable, Sendable, Identifiable {
    case frontend = "FRONTEND"
    case backend = "BACKEND"
    case mobile = "MOBILE"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frontend: "Веб-фронтенд"
        case .backend: "Бэкенд"
        case .mobile: "Мобильная разработка"
        }
    }
}

nonisolated enum Level: String, Codable, Sendable {
    case beginner = "BEGINNER"
    case continuing = "CONTINUING"
}

nonisolated enum MissionStatus: String, Codable, Sendable {
    case todo = "TODO"
    case done = "DONE"
}

nonisolated struct ProfileRequest: Codable, Equatable, Sendable {
    var area: ItArea
    var goal: String
    var level: Level
    var minutesPerDay: Int
    var daysPerWeek: Int
}

nonisolated struct SourceRef: Codable, Equatable, Sendable {
    var title: String
    var url: String
}

nonisolated struct MissionDto: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var week: Int
    var day: Int
    var title: String
    var topic: String
    var material: SourceRef
    var task: String
    var minutes: Int
    var status: MissionStatus
    var review: Bool = false
    var code: Bool = false            // в ответе нужно написать код
    var availableFrom: String? = nil  // для повторений: дата (yyyy-MM-dd), раньше которой миссия не откроется

    init(id: String, week: Int, day: Int, title: String, topic: String, material: SourceRef, task: String,
         minutes: Int, status: MissionStatus, review: Bool = false, code: Bool = false, availableFrom: String? = nil) {
        self.id = id; self.week = week; self.day = day; self.title = title; self.topic = topic
        self.material = material; self.task = task; self.minutes = minutes; self.status = status
        self.review = review; self.code = code; self.availableFrom = availableFrom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        week = try c.decode(Int.self, forKey: .week)
        day = try c.decode(Int.self, forKey: .day)
        title = try c.decode(String.self, forKey: .title)
        topic = try c.decode(String.self, forKey: .topic)
        material = try c.decode(SourceRef.self, forKey: .material)
        task = try c.decode(String.self, forKey: .task)
        minutes = try c.decode(Int.self, forKey: .minutes)
        status = try c.decode(MissionStatus.self, forKey: .status)
        review = try c.decodeIfPresent(Bool.self, forKey: .review) ?? false
        code = try c.decodeIfPresent(Bool.self, forKey: .code) ?? false
        availableFrom = try c.decodeIfPresent(String.self, forKey: .availableFrom)
    }
}

nonisolated struct WeekDto: Codable, Equatable, Sendable, Identifiable {
    var index: Int
    var title: String
    var missions: [MissionDto]

    var id: Int { index }

    // «Неделя 1: Основы HTML» → «Основы HTML»
    var shortTitle: String {
        guard let range = title.range(of: ": ") else { return title }
        return String(title[range.upperBound...])
    }
}

nonisolated struct PlanDto: Codable, Equatable, Sendable {
    var version: Int
    var area: ItArea
    var goal: String
    var weeks: [WeekDto]
    var level: Level = .beginner
    var minutesPerDay: Int = 30
    var daysPerWeek: Int = 5

    init(version: Int, area: ItArea, goal: String, weeks: [WeekDto],
         level: Level = .beginner, minutesPerDay: Int = 30, daysPerWeek: Int = 5) {
        self.version = version; self.area = area; self.goal = goal; self.weeks = weeks
        self.level = level; self.minutesPerDay = minutesPerDay; self.daysPerWeek = daysPerWeek
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        area = try c.decode(ItArea.self, forKey: .area)
        goal = try c.decode(String.self, forKey: .goal)
        weeks = try c.decode([WeekDto].self, forKey: .weeks)
        level = try c.decodeIfPresent(Level.self, forKey: .level) ?? .beginner
        minutesPerDay = try c.decodeIfPresent(Int.self, forKey: .minutesPerDay) ?? 30
        daysPerWeek = try c.decodeIfPresent(Int.self, forKey: .daysPerWeek) ?? 5
    }
}

nonisolated struct TodayDto: Codable, Equatable, Sendable {
    var mission: MissionDto?
    var message: String
    var planRebuilt: Bool = false

    init(mission: MissionDto?, message: String, planRebuilt: Bool = false) {
        self.mission = mission; self.message = message; self.planRebuilt = planRebuilt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mission = try c.decodeIfPresent(MissionDto.self, forKey: .mission)
        message = try c.decode(String.self, forKey: .message)
        planRebuilt = try c.decodeIfPresent(Bool.self, forKey: .planRebuilt) ?? false
    }
}

nonisolated struct AnswerRequest: Codable, Sendable {
    var missionId: String
    var answer: String
}

nonisolated struct EvaluationDto: Codable, Equatable, Sendable {
    var score: Int
    var passed: Bool
    var feedback: String
    var gaps: [String]
    var streak: Int
}

nonisolated struct ProgressDto: Codable, Equatable, Sendable {
    var streak: Int
    var doneMissions: Int
    var totalMissions: Int
    var planVersion: Int
    var gaps: [String]
    var weekActivity: [Bool] = []  // пн…вс текущей недели: был ли засчитанный урок
    var doneToday: Bool = false
    var reviewsDue: Int = 0         // повторения, у которых уже наступил срок

    init(streak: Int, doneMissions: Int, totalMissions: Int, planVersion: Int, gaps: [String],
         weekActivity: [Bool] = [], doneToday: Bool = false, reviewsDue: Int = 0) {
        self.streak = streak; self.doneMissions = doneMissions; self.totalMissions = totalMissions
        self.planVersion = planVersion; self.gaps = gaps; self.weekActivity = weekActivity
        self.doneToday = doneToday; self.reviewsDue = reviewsDue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streak = try c.decode(Int.self, forKey: .streak)
        doneMissions = try c.decode(Int.self, forKey: .doneMissions)
        totalMissions = try c.decode(Int.self, forKey: .totalMissions)
        planVersion = try c.decode(Int.self, forKey: .planVersion)
        gaps = try c.decode([String].self, forKey: .gaps)
        weekActivity = try c.decodeIfPresent([Bool].self, forKey: .weekActivity) ?? []
        doneToday = try c.decodeIfPresent(Bool.self, forKey: .doneToday) ?? false
        reviewsDue = try c.decodeIfPresent(Int.self, forKey: .reviewsDue) ?? 0
    }
}

nonisolated struct ErrorDto: Codable, Sendable {
    var error: String
}

// ---------- Вход ----------

nonisolated struct GoogleAuthRequest: Codable, Sendable { var idToken: String }

// Вход без Google – только для разработки (на сервере включается AUTH_DEV=true)
nonisolated struct DevAuthRequest: Codable, Sendable { var deviceId: String }

nonisolated struct RegisterRequest: Codable, Sendable {
    var name: String
    var email: String
    var password: String
}

nonisolated struct LoginRequest: Codable, Sendable {
    var email: String
    var password: String
}

nonisolated struct AuthResponse: Codable, Sendable {
    var token: String
    var userId: String
    var name: String? = nil
}

// ---------- Настройки ----------

nonisolated struct SettingsRequest: Codable, Sendable {
    var goal: String
    var minutesPerDay: Int
    var daysPerWeek: Int
}

// ---------- Чат «Застрял» (F5) ----------

nonisolated enum ChatRole: String, Codable, Sendable {
    case user = "USER"
    case mentor = "MENTOR"
}

nonisolated struct ChatMessage: Codable, Equatable, Sendable {
    var role: ChatRole
    var text: String
}

nonisolated struct ChatRequest: Codable, Sendable {
    var missionId: String
    var messages: [ChatMessage]
}

nonisolated struct ChatReply: Codable, Sendable {
    var reply: String
}
