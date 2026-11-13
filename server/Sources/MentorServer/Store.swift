import Foundation
import Logging
import NIOSSL
import PostgresNIO
import Synchronization

// Внутреннее представление миссии (в DTO превращается в MentorService)
public struct Mission: Codable, Sendable {
    public var id: String
    public var sourceId: String
    public var task: TaskDef
    public var week = 0
    public var day = 0
    public var minutes: Int
    public var status = MissionStatus.todo
    public var review = false
    public var attempts = 0
    public var taskGenerated = false
    public var pregenerating = false // задание сейчас генерируется в фоне
    public var notBefore: Day?        // повторение откроется не раньше этой даты (интервальное повторение)
    public var reviewStage = 0        // 0 – обычная миссия, 1..n – номер повторения
    public var reason: String?        // зачем эта тема в плане (пишет ИИ-методист)

    public init(id: String = newId(), sourceId: String, task: TaskDef, minutes: Int, review: Bool = false,
                taskGenerated: Bool = false, notBefore: Day? = nil, reviewStage: Int = 0) {
        self.id = id; self.sourceId = sourceId; self.task = task; self.minutes = minutes
        self.review = review; self.taskGenerated = taskGenerated; self.notBefore = notBefore; self.reviewStage = reviewStage
    }

    // Поля, которых нет в старых записях, получают значения по умолчанию
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sourceId = try c.decode(String.self, forKey: .sourceId)
        task = try c.decode(TaskDef.self, forKey: .task)
        week = try c.decodeIfPresent(Int.self, forKey: .week) ?? 0
        day = try c.decodeIfPresent(Int.self, forKey: .day) ?? 0
        minutes = try c.decode(Int.self, forKey: .minutes)
        status = try c.decodeIfPresent(MissionStatus.self, forKey: .status) ?? .todo
        review = try c.decodeIfPresent(Bool.self, forKey: .review) ?? false
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        taskGenerated = try c.decodeIfPresent(Bool.self, forKey: .taskGenerated) ?? false
        pregenerating = try c.decodeIfPresent(Bool.self, forKey: .pregenerating) ?? false
        notBefore = try c.decodeIfPresent(Day.self, forKey: .notBefore)
        reviewStage = try c.decodeIfPresent(Int.self, forKey: .reviewStage) ?? 0
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }

    // Миссию можно открыть сегодня: она не выполнена и срок повторения наступил
    func isAvailable(on day: Day) -> Bool {
        status == .todo && (notBefore.map { $0 <= day } ?? true)
    }
}

public struct UserState: Codable, Sendable {
    public var profile: ProfileRequest
    public var missions: [Mission]
    public var lastActive: Day
    public var version = 1
    public var streak = 0
    public var lastDone: Day?
    public var gaps: [String] = []      // темы с ошибками, без повторов, в порядке появления
    public var llmDay: Day?             // дневной лимит запросов к внешней модели
    public var llmCalls = 0
    public var doneDates: [String] = [] // дни (yyyy-MM-dd) с засчитанным уроком – для полоски недели
    public var known: [String]?         // id тем, которые человек знает по мини-тесту; nil – тест не проходил
    public var summary: String?         // объяснение плана от ИИ-методиста

    public init(profile: ProfileRequest, missions: [Mission], lastActive: Day) {
        self.profile = profile; self.missions = missions; self.lastActive = lastActive
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decode(ProfileRequest.self, forKey: .profile)
        missions = try c.decode([Mission].self, forKey: .missions)
        lastActive = try c.decode(Day.self, forKey: .lastActive)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        lastDone = try c.decodeIfPresent(Day.self, forKey: .lastDone)
        gaps = try c.decodeIfPresent([String].self, forKey: .gaps) ?? []
        llmDay = try c.decodeIfPresent(Day.self, forKey: .llmDay)
        llmCalls = try c.decodeIfPresent(Int.self, forKey: .llmCalls) ?? 0
        doneDates = try c.decodeIfPresent([String].self, forKey: .doneDates) ?? []
        known = try c.decodeIfPresent([String].self, forKey: .known)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
    }
}

public func newId() -> String { UUID().uuidString.lowercased() }

// Сводка для GET /admin/stats: сколько людей реально занимаются
public struct StatsDto: Codable, Sendable, Equatable {
    public var users: Int
    public var active1d: Int
    public var active7d: Int
    public var active30d: Int
    public var profiles7d: Int
    public var answers7d: Int
    public var passed7d: Int
    public var chats7d: Int
}

public enum EventType: String, Sendable, CaseIterable {
    case profile = "PROFILE"
    case answerPass = "ANSWER_PASS"
    case answerFail = "ANSWER_FAIL"
    case chat = "CHAT"
    case open = "OPEN"
}

// email хранится в нижнем регистре, пароль – только в виде хеша (см. Passwords)
public struct Account: Sendable, Equatable {
    public var userId: String
    public var email: String
    public var passwordHash: String
    public var name: String

    public init(userId: String, email: String, passwordHash: String, name: String) {
        self.userId = userId; self.email = email; self.passwordHash = passwordHash; self.name = name
    }
}

// Состояние пользователя хранится одним JSON-документом: для MVP этого достаточно,
// а схема данных может меняться без миграций (новые поля получают значения по умолчанию).
public protocol UserStore: Sendable {
    func load(_ userId: String) async throws -> UserState?
    func save(_ userId: String, _ state: UserState) async throws
    func delete(_ userId: String) async throws // удаляет и состояние, и события, и аккаунт с паролем
    func event(_ userId: String, _ type: EventType, _ day: Day) async throws
    func stats(today: Day) async throws -> StatsDto

    // Аккаунты с входом по email. false – такой email уже зарегистрирован.
    func createAccount(_ account: Account) async throws -> Bool
    func findAccount(email: String) async throws -> Account?
}

let storeEncoder = JSONEncoder()
let storeDecoder = JSONDecoder()

// Для тестов и локального запуска. Хранит JSON, как и Postgres, поэтому ошибки сериализации видны сразу.
public final class InMemoryUserStore: UserStore {
    private struct Contents {
        var users: [String: Data] = [:]
        var events: [(userId: String, type: EventType, day: Day)] = []
        var accounts: [String: Account] = [:] // ключ – email
    }

    private let data = Mutex(Contents())

    public init() {}

    public func load(_ userId: String) async throws -> UserState? {
        try data.withLock { $0.users[userId] }.map { try storeDecoder.decode(UserState.self, from: $0) }
    }

    public func save(_ userId: String, _ state: UserState) async throws {
        let json = try storeEncoder.encode(state)
        data.withLock { $0.users[userId] = json }
    }

    public func delete(_ userId: String) async throws {
        data.withLock { d in
            d.users[userId] = nil
            d.events.removeAll { $0.userId == userId }
            d.accounts = d.accounts.filter { $0.value.userId != userId }
        }
    }

    public func createAccount(_ account: Account) async throws -> Bool {
        data.withLock { d in
            guard d.accounts[account.email] == nil else { return false }
            d.accounts[account.email] = account
            return true
        }
    }

    public func findAccount(email: String) async throws -> Account? {
        data.withLock { $0.accounts[email] }
    }

    public func event(_ userId: String, _ type: EventType, _ day: Day) async throws {
        data.withLock { $0.events.append((userId, type, day)) }
    }

    public func stats(today: Day) async throws -> StatsDto {
        let (users, all) = data.withLock { ($0.users.count, $0.events) }
        func since(_ days: Int) -> [(userId: String, type: EventType, day: Day)] {
            all.filter { $0.day >= today.adding(days: -(days - 1)) }
        }
        func active(_ days: Int) -> Int { Set(since(days).map(\.userId)).count }
        let week = Dictionary(grouping: since(7), by: \.type).mapValues(\.count)
        return StatsDto(
            users: users,
            active1d: active(1), active7d: active(7), active30d: active(30),
            profiles7d: week[.profile] ?? 0,
            answers7d: (week[.answerPass] ?? 0) + (week[.answerFail] ?? 0),
            passed7d: week[.answerPass] ?? 0,
            chats7d: week[.chat] ?? 0
        )
    }
}

// Хранилище в PostgreSQL. Состояние пользователя – JSON-документ, новые поля получают значения по умолчанию.
// Клиенту нужен запущенный run() – его запускает точка входа сервера (или тест).
public final class PostgresUserStore: UserStore {
    public let client: PostgresClient
    private let logger: Logger

    public init(client: PostgresClient, logger: Logger = Logger(label: "PostgresUserStore")) {
        self.client = client
        self.logger = logger
    }

    // Создаёт таблицы, если их ещё нет
    public func migrate() async throws {
        try await client.query("""
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                state JSONB NOT NULL,
                updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """, logger: logger)
        try await client.query("""
            CREATE TABLE IF NOT EXISTS events (
                id BIGSERIAL PRIMARY KEY,
                user_id TEXT NOT NULL,
                type TEXT NOT NULL,
                day DATE NOT NULL
            )
            """, logger: logger)
        try await client.query("""
            CREATE TABLE IF NOT EXISTS accounts (
                user_id TEXT PRIMARY KEY,
                email TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                name TEXT NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """, logger: logger)
        try await client.query("CREATE INDEX IF NOT EXISTS events_day ON events(day)", logger: logger)
        try await client.query("CREATE INDEX IF NOT EXISTS events_user ON events(user_id)", logger: logger)
    }

    public func load(_ userId: String) async throws -> UserState? {
        let rows = try await client.query("SELECT state::text FROM users WHERE id = \(userId)", logger: logger)
        for try await json in rows.decode(String.self) {
            return try storeDecoder.decode(UserState.self, from: Data(json.utf8))
        }
        return nil
    }

    public func save(_ userId: String, _ state: UserState) async throws {
        let json = String(decoding: try storeEncoder.encode(state), as: UTF8.self)
        try await client.query("""
            INSERT INTO users(id, state) VALUES (\(userId), CAST(\(json) AS jsonb))
            ON CONFLICT (id) DO UPDATE SET state = EXCLUDED.state, updated_at = now()
            """, logger: logger)
    }

    // Удаление аккаунта стирает и события: после него о человеке не остаётся данных
    public func delete(_ userId: String) async throws {
        let logger = logger
        try await client.withTransaction(logger: logger) { conn in
            try await conn.query("DELETE FROM users WHERE id = \(userId)", logger: logger)
            try await conn.query("DELETE FROM events WHERE user_id = \(userId)", logger: logger)
            try await conn.query("DELETE FROM accounts WHERE user_id = \(userId)", logger: logger)
        }
    }

    public func createAccount(_ account: Account) async throws -> Bool {
        let rows = try await client.query("""
            INSERT INTO accounts(user_id, email, password_hash, name)
            VALUES (\(account.userId), \(account.email), \(account.passwordHash), \(account.name))
            ON CONFLICT (email) DO NOTHING
            RETURNING user_id
            """, logger: logger)
        for try await _ in rows.decode(String.self) { return true }
        return false
    }

    public func findAccount(email: String) async throws -> Account? {
        let rows = try await client.query(
            "SELECT user_id, email, password_hash, name FROM accounts WHERE email = \(email)", logger: logger)
        for try await (userId, email, hash, name) in rows.decode((String, String, String, String).self) {
            return Account(userId: userId, email: email, passwordHash: hash, name: name)
        }
        return nil
    }

    public func event(_ userId: String, _ type: EventType, _ day: Day) async throws {
        try await client.query(
            "INSERT INTO events(user_id, type, day) VALUES (\(userId), \(type.rawValue), CAST(\(day.description) AS date))",
            logger: logger)
    }

    public func stats(today: Day) async throws -> StatsDto {
        func count(_ query: PostgresQuery) async throws -> Int {
            for try await n in try await client.query(query, logger: logger).decode(Int.self) { return n }
            return 0
        }
        func active(_ days: Int) async throws -> Int {
            let from = today.adding(days: -(days - 1)).description
            return try await count("SELECT count(DISTINCT user_id) FROM events WHERE day >= CAST(\(from) AS date)")
        }
        let weekStart = today.adding(days: -6).description
        var week: [String: Int] = [:]
        let rows = try await client.query(
            "SELECT type, count(*) FROM events WHERE day >= CAST(\(weekStart) AS date) GROUP BY type", logger: logger)
        for try await (type, n) in rows.decode((String, Int).self) { week[type] = n }
        func w(_ type: EventType) -> Int { week[type.rawValue] ?? 0 }

        return StatsDto(
            users: try await count("SELECT count(*) FROM users"),
            active1d: try await active(1), active7d: try await active(7), active30d: try await active(30),
            profiles7d: w(.profile),
            answers7d: w(.answerPass) + w(.answerFail),
            passed7d: w(.answerPass),
            chats7d: w(.chat)
        )
    }

    // Хостинги (Railway, Render, Supabase) дают адрес вида postgres://user:pass@host:5432/db?sslmode=require.
    // Старый формат jdbc:postgresql://host:5432/db тоже поддерживается.
    // sslmode как у libpq: disable – без TLS, require – TLS без проверки сертификата,
    // verify-ca / verify-full – TLS с проверкой; по умолчанию (prefer) TLS, если сервер его поддерживает.
    public static func configuration(url: String, user: String?, password: String?) throws -> PostgresClient.Configuration {
        var text = url
        if text.hasPrefix("jdbc:") { text.removeFirst(5) }
        guard let comps = URLComponents(string: text), let host = comps.host,
              ["postgres", "postgresql"].contains(comps.scheme ?? "") else {
            throw ConfigError(message: "Неверный DATABASE_URL: ожидается postgres://user:pass@host:5432/db")
        }
        let query = Dictionary((comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        let database = comps.path.hasPrefix("/") ? String(comps.path.dropFirst()) : comps.path

        var insecure = TLSConfiguration.makeClientConfiguration()
        insecure.certificateVerification = .none
        let tls: PostgresClient.Configuration.TLS = switch query["sslmode"] ?? "prefer" {
        case "disable": .disable
        case "require": .require(insecure)
        case "verify-ca", "verify-full": .require(.makeClientConfiguration())
        default: .prefer(insecure)
        }

        var config = PostgresClient.Configuration(
            host: host,
            port: comps.port ?? 5432,
            username: user ?? comps.user?.removingPercentEncoding ?? query["user"] ?? "postgres",
            password: password ?? comps.password?.removingPercentEncoding ?? query["password"],
            database: database.isEmpty ? nil : database,
            tls: tls
        )
        config.options.maximumConnections = 5
        return config
    }
}

public struct ConfigError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}
