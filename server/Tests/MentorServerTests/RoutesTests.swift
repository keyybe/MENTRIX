import Foundation
import Testing
import VaporTesting
@testable import MentorServer

// Проверки HTTP API целиком: маршруты, токены, коды ответов и формат ошибок
@Suite struct RoutesTests {
    struct FakeGoogle: GoogleVerifier {
        func verify(_ idToken: String) async throws -> String {
            guard idToken == "valid-google-token" else { throw APIError.unauthorized("Не удалось проверить вход через Google") }
            return "google-sub-1"
        }
    }

    let secret = "routes-test-secret-0123456789abcdef0123"

    func withServer(
        devLogin: Bool = false,
        adminToken: String? = nil,
        google: (any GoogleVerifier)? = nil,
        _ test: (Application) async throws -> Void
    ) async throws {
        let store = InMemoryUserStore()
        let service = MentorService(sources: sources, llm: FakeLlm(), store: store)
        try await withApp(configure: { app in
            try await configure(
                app, service: service,
                auth: AuthConfig(jwtSecret: secret, devLogin: devLogin, adminToken: adminToken),
                google: google, accounts: AccountService(store: store)
            )
        }) { app in
            try await test(app)
            await service.awaitBackground()
        }
    }

    func bearer(_ token: String) -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token)
        return headers
    }

    @Test func health() async throws {
        try await withServer { app in
            try await app.testing().test(.GET, "health") { res async throws in
                #expect(res.status == .ok)
                #expect(res.body.string == "ok")
            }
        }
    }

    @Test func fullFlowOverHttp() async throws {
        try await withServer { app in
            var token = ""
            try await app.testing().test(.POST, "api/auth/register", beforeRequest: { req in
                try req.content.encode(RegisterRequest(name: "Аня", email: "anya@example.com", password: "password123"))
            }) { res async throws in
                #expect(res.status == .created)
                let auth = try res.content.decode(AuthResponse.self)
                #expect(auth.name == "Аня" && auth.userId.hasPrefix("e:"))
                token = auth.token
            }
            try await app.testing().test(.POST, "api/auth/login", beforeRequest: { req in
                try req.content.encode(LoginRequest(email: "ANYA@example.com", password: "password123"))
            }) { res async throws in
                #expect(res.status == .ok)
                #expect(try !res.content.decode(AuthResponse.self).token.isEmpty)
            }

            let auth = bearer(token)
            // профиля ещё нет
            try await app.testing().test(.GET, "api/today", headers: auth) { res async throws in
                #expect(res.status == .notFound)
            }
            try await app.testing().test(.POST, "api/profile", headers: auth, beforeRequest: { req in
                try req.content.encode(profile())
            }) { res async throws in
                #expect(res.status == .created)
                #expect(try res.content.decode(PlanDto.self).area == .backend)
            }

            var missionId = ""
            try await app.testing().test(.GET, "api/today", headers: auth) { res async throws in
                #expect(res.status == .ok)
                missionId = try #require(try res.content.decode(TodayDto.self).mission).id
            }
            try await app.testing().test(.POST, "api/chat", headers: auth, beforeRequest: { req in
                try req.content.encode(ChatRequest(missionId: missionId, messages: [ChatMessage(role: .user, text: "Помоги")]))
            }) { res async throws in
                #expect(try res.content.decode(ChatReply.self).reply == "fake hint")
            }
            try await app.testing().test(.POST, "api/answer", headers: auth, beforeRequest: { req in
                try req.content.encode(AnswerRequest(missionId: missionId, answer: goodAnswer))
            }) { res async throws in
                #expect(res.status == .ok)
                #expect(try res.content.decode(EvaluationDto.self).passed)
            }
            try await app.testing().test(.PUT, "api/settings", headers: auth, beforeRequest: { req in
                try req.content.encode(SettingsRequest(goal: "Новая цель", minutesPerDay: 25, daysPerWeek: 4))
            }) { res async throws in
                #expect(try res.content.decode(PlanDto.self).daysPerWeek == 4)
            }
            try await app.testing().test(.GET, "api/progress", headers: auth) { res async throws in
                let progress = try res.content.decode(ProgressDto.self)
                #expect(progress.doneMissions == 1 && progress.streak == 1 && progress.weekActivity.count == 7)
            }
            try await app.testing().test(.GET, "api/plan", headers: auth) { res async throws in
                #expect(try res.content.decode(PlanDto.self).goal == "Новая цель")
            }

            try await app.testing().test(.DELETE, "api/account", headers: auth) { res async throws in
                #expect(res.status == .noContent)
            }
            try await app.testing().test(.GET, "api/plan", headers: auth) { res async throws in
                #expect(res.status == .notFound)
            }
            // после удаления аккаунта email свободен, а старый пароль не подходит
            try await app.testing().test(.POST, "api/auth/login", beforeRequest: { req in
                try req.content.encode(LoginRequest(email: "anya@example.com", password: "password123"))
            }) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func apiRequiresValidToken() async throws {
        try await withServer { app in
            for headers in [HTTPHeaders(), bearer("garbage")] {
                try await app.testing().test(.GET, "api/plan", headers: headers) { res async throws in
                    #expect(res.status == .unauthorized)
                    #expect(try res.content.decode(ErrorDto.self).error == "Нужно войти заново")
                }
            }
            // токен, подписанный другим секретом
            let foreign = try await TokenIssuer(secret: "other-secret-0987654321-fedcba9876543210").issue("e:1")
            try await app.testing().test(.GET, "api/plan", headers: bearer(foreign)) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func malformedBodyGivesReadableError() async throws {
        try await withServer { app in
            try await app.testing().test(.POST, "api/auth/register", headers: ["Content-Type": "application/json"],
                                         body: ByteBuffer(string: "{\"name\": 1}")) { res async throws in
                #expect(res.status == .badRequest)
                #expect(try res.content.decode(ErrorDto.self).error == "Неверный формат данных")
            }
            try await app.testing().test(.GET, "api/nothing-here") { res async throws in
                #expect(res.status == .notFound)
                #expect(try res.content.decode(ErrorDto.self).error == "Не найдено")
            }
        }
    }

    @Test func devLoginDisabledByDefault() async throws {
        try await withServer { app in
            try await app.testing().test(.POST, "api/auth/dev", beforeRequest: { req in
                try req.content.encode(DevAuthRequest(deviceId: "device-123456"))
            }) { res async throws in
                #expect(res.status == .notFound)
            }
        }
        try await withServer(devLogin: true) { app in
            try await app.testing().test(.POST, "api/auth/dev", beforeRequest: { req in
                try req.content.encode(DevAuthRequest(deviceId: "device-123456"))
            }) { res async throws in
                #expect(try res.content.decode(AuthResponse.self).userId == "dev:device-123456")
            }
            try await app.testing().test(.POST, "api/auth/dev", beforeRequest: { req in
                try req.content.encode(DevAuthRequest(deviceId: "short"))
            }) { res async throws in
                #expect(res.status == .badRequest)
            }
        }
    }

    @Test func googleLoginIssuesToken() async throws {
        try await withServer { app in
            try await app.testing().test(.POST, "api/auth/google", beforeRequest: { req in
                try req.content.encode(GoogleAuthRequest(idToken: "valid-google-token"))
            }) { res async throws in
                #expect(res.status == .notFound, "без GOOGLE_CLIENT_ID вход через Google выключен")
            }
        }
        try await withServer(google: FakeGoogle()) { app in
            var token = ""
            try await app.testing().test(.POST, "api/auth/google", beforeRequest: { req in
                try req.content.encode(GoogleAuthRequest(idToken: "valid-google-token"))
            }) { res async throws in
                let auth = try res.content.decode(AuthResponse.self)
                #expect(auth.userId == "g:google-sub-1")
                token = auth.token
            }
            try await app.testing().test(.POST, "api/profile", headers: bearer(token), beforeRequest: { req in
                try req.content.encode(profile())
            }) { res async throws in
                #expect(res.status == .created)
            }
            try await app.testing().test(.POST, "api/auth/google", beforeRequest: { req in
                try req.content.encode(GoogleAuthRequest(idToken: "forged"))
            }) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test func adminStatsNeedToken() async throws {
        try await withServer { app in
            try await app.testing().test(.GET, "admin/stats", headers: ["X-Admin-Token": "anything"]) { res async throws in
                #expect(res.status == .notFound, "без ADMIN_TOKEN статистика выключена")
            }
        }
        try await withServer(adminToken: "admin-secret") { app in
            for given in ["", "wrong", "admin-secre"] {
                try await app.testing().test(.GET, "admin/stats", headers: ["X-Admin-Token": given]) { res async throws in
                    #expect(res.status == .unauthorized)
                }
            }
            try await app.testing().test(.GET, "admin/stats", headers: ["X-Admin-Token": "admin-secret"]) { res async throws in
                #expect(res.status == .ok)
                #expect(try res.content.decode(StatsDto.self).users == 0)
            }
        }
    }
}
