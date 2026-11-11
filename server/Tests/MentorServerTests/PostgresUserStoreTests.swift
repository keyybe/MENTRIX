import Foundation
import Logging
import PostgresNIO
import Testing
@testable import MentorServer

// Разбор DATABASE_URL проверяется всегда, без базы
@Suite struct PostgresConfigurationTests {
    @Test func parsesHostingUrl() throws {
        let config = try PostgresUserStore.configuration(url: "postgres://user%40x:p%40ss@db.example.com:6543/mentor?sslmode=require", user: nil, password: nil)
        #expect(config.host == "db.example.com")
        #expect(config.port == 6543)
        #expect(config.username == "user@x")
        #expect(config.password == "p@ss")
        #expect(config.database == "mentor")
    }

    @Test func explicitCredentialsAndJdbcPrefix() throws {
        let config = try PostgresUserStore.configuration(url: "jdbc:postgresql://localhost/mentor", user: "mentor", password: "secret")
        #expect(config.host == "localhost" && config.port == 5432)
        #expect(config.username == "mentor" && config.password == "secret")
    }

    @Test func rejectsWrongScheme() {
        #expect(throws: ConfigError.self) { try PostgresUserStore.configuration(url: "mysql://localhost/db", user: nil, password: nil) }
        #expect(throws: ConfigError.self) { try PostgresUserStore.configuration(url: "not a url", user: nil, password: nil) }
    }
}

// Настоящая PostgreSQL: TEST_DATABASE_URL=postgresql://mentor:пароль@localhost:5432/mentor_test swift test
// Тесты создают пользователей с уникальными id и удаляют их за собой.
let testDatabaseURL = ProcessInfo.processInfo.environment["TEST_DATABASE_URL"].flatMap { $0.isEmpty ? nil : $0 }

@Suite(.enabled(if: testDatabaseURL != nil, "задай TEST_DATABASE_URL, чтобы проверить PostgreSQL"), .serialized)
struct PostgresUserStoreTests {
    func withStore(_ test: (PostgresUserStore) async throws -> Void) async throws {
        let config = try PostgresUserStore.configuration(url: testDatabaseURL!, user: nil, password: nil)
        let store = PostgresUserStore(client: PostgresClient(configuration: config, backgroundLogger: Logger(label: "test")))
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await store.client.run() }
            defer { group.cancelAll() }
            try await store.migrate()
            try await store.migrate() // повторный запуск миграции безопасен
            try await test(store)
        }
    }

    func newUser() -> String { "test:" + newId() }

    @Test func stateRoundTripsThroughJsonb() async throws {
        try await withStore { store in
            let uid = newUser()
            #expect(try await store.load(uid) == nil)

            var state = UserState(profile: profile(), missions: [
                Mission(sourceId: "s1", task: TaskDef(title: "Т", prompt: "Вопрос с \"кавычками\" и 'апострофом'", keywords: ["a|b"], code: true), minutes: 20),
            ], lastActive: Day(2026, 1, 5))
            state.streak = 3
            state.lastDone = Day(2026, 1, 4)
            state.gaps = ["HTTP"]
            state.missions[0].notBefore = Day(2026, 1, 8)
            try await store.save(uid, state)

            state.version = 2 // повторное сохранение обновляет запись
            try await store.save(uid, state)

            let loaded = try #require(try await store.load(uid))
            #expect(loaded.version == 2 && loaded.streak == 3 && loaded.gaps == ["HTTP"])
            #expect(loaded.lastDone == Day(2026, 1, 4))
            #expect(loaded.missions.first?.task == state.missions[0].task)
            #expect(loaded.missions.first?.notBefore == Day(2026, 1, 8))

            try await store.delete(uid)
            #expect(try await store.load(uid) == nil)
        }
    }

    @Test func progressSurvivesServerRestart() async throws {
        let uid = newUser()
        try await withStore { store in
            let service = MentorService(sources: sources, llm: FakeLlm(), store: store)
            _ = try await service.createProfile(uid, profile())
            try await service.answerToday(uid, goodAnswer)
            await service.awaitBackground()
        }
        // новое подключение и новый сервис – как после перезапуска
        try await withStore { store in
            let service = MentorService(sources: sources, llm: FakeLlm(), store: store)
            #expect(try await service.progress(uid).doneMissions == 1)
            try await service.delete(uid)
        }
    }

    @Test func accountsAreUniqueByEmailAndDeletedWithUser() async throws {
        try await withStore { store in
            let email = "test-\(newId())@example.com"
            let account = Account(userId: newUser(), email: email, passwordHash: Passwords.hash("password123"), name: "Аня")
            #expect(try await store.createAccount(account))
            #expect(try await !store.createAccount(Account(userId: newUser(), email: email, passwordHash: "x", name: "Другая")))
            #expect(try await store.findAccount(email: email) == account)

            try await store.delete(account.userId)
            #expect(try await store.findAccount(email: email) == nil)
        }
    }

    @Test func eventsCountedAndDeletedWithAccount() async throws {
        try await withStore { store in
            let uid = newUser()
            // дата далеко в будущем, чтобы не пересекаться с реальными событиями в базе
            let today = Day(2400, 1, 10)
            let before = try await store.stats(today: today)

            try await store.save(uid, UserState(profile: profile(), missions: [], lastActive: today))
            try await store.event(uid, .profile, today)
            try await store.event(uid, .answerPass, today)
            try await store.event(uid, .answerFail, today.adding(days: -3))
            try await store.event(uid, .chat, today.adding(days: -20))

            let after = try await store.stats(today: today)
            #expect(after.users == before.users + 1)
            #expect(after.active1d == before.active1d + 1)
            #expect(after.active30d == before.active30d + 1)
            #expect(after.profiles7d == before.profiles7d + 1)
            #expect(after.answers7d == before.answers7d + 2)
            #expect(after.passed7d == before.passed7d + 1)
            #expect(after.chats7d == before.chats7d, "чат 20 дней назад не входит в неделю")

            try await store.delete(uid)
            #expect(try await store.stats(today: today) == before)
        }
    }
}
