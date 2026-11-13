import Crypto
import Vapor

// Подключает к приложению все маршруты API.
// accounts должен работать с тем же хранилищем, что и service: иначе удаление аккаунта не сотрёт пароль.
public func configure(
    _ app: Application,
    service: MentorService,
    auth: AuthConfig,
    google: (any GoogleVerifier)?,
    accounts: AccountService
) async throws {
    let tokens = await TokenIssuer(secret: auth.jwtSecret)

    app.middleware = Middlewares()
    app.middleware.use(APIErrorMiddleware())
    // история чата (до 12 сообщений по 2000 символов) не влезает в стандартные 16 КБ
    app.routes.defaultMaxBodySize = "256kb"

    // id пользователя из заголовка Authorization: Bearer <токен>
    @Sendable func userId(_ req: Request) async throws -> String {
        guard let token = req.headers.bearerAuthorization?.token, let id = await tokens.userId(from: token) else {
            throw APIError.unauthorized("Нужно войти заново")
        }
        return id
    }

    @Sendable func body<T: Decodable>(_ req: Request, _ type: T.Type) throws -> T {
        do {
            return try req.content.decode(T.self)
        } catch {
            throw APIError.badRequest("Неверный формат данных")
        }
    }

    app.get("health") { _ in "ok" }

    // Сводка по активности. Включается переменной ADMIN_TOKEN, запрос с заголовком X-Admin-Token.
    app.get("admin", "stats") { req async throws -> StatsDto in
        guard let expected = auth.adminToken else { throw APIError.notFound("Не найдено") }
        let given = req.headers.first(name: "X-Admin-Token") ?? ""
        // сравнение за постоянное время, чтобы токен нельзя было подобрать по времени ответа
        guard constantTimeEquals(Array(SHA256.hash(data: Data(given.utf8))), Array(SHA256.hash(data: Data(expected.utf8)))) else {
            throw APIError.unauthorized("Неверный токен")
        }
        return try await service.stats()
    }

    let api = app.grouped("api")

    let authRoutes = api.grouped("auth")
    authRoutes.post("register") { req async throws -> Response in
        let account = try await accounts.register(try body(req, RegisterRequest.self))
        let response = AuthResponse(token: try await tokens.issue(account.userId), userId: account.userId, name: account.name)
        return try await response.encodeResponse(status: .created, for: req)
    }
    authRoutes.post("login") { req async throws -> AuthResponse in
        let account = try await accounts.login(try body(req, LoginRequest.self))
        return AuthResponse(token: try await tokens.issue(account.userId), userId: account.userId, name: account.name)
    }
    authRoutes.post("google") { req async throws -> AuthResponse in
        guard let google else { throw APIError.notFound("Вход через Google не настроен на сервере") }
        let request = try body(req, GoogleAuthRequest.self)
        let userId = "g:" + (try await google.verify(request.idToken))
        return AuthResponse(token: try await tokens.issue(userId), userId: userId, name: nil)
    }
    authRoutes.post("dev") { req async throws -> AuthResponse in
        guard auth.devLogin else { throw APIError.notFound("Вход для разработки выключен") }
        let request = try body(req, DevAuthRequest.self)
        guard (8...64).contains(request.deviceId.count) else { throw APIError.badRequest("Неверный id устройства") }
        let userId = "dev:" + request.deviceId
        return AuthResponse(token: try await tokens.issue(userId), userId: userId, name: nil)
    }

    api.post("profile") { req async throws -> Response in
        let plan = try await service.createProfile(try await userId(req), try body(req, ProfileRequest.self))
        return try await plan.encodeResponse(status: .created, for: req)
    }
    api.put("settings") { req async throws -> PlanDto in
        try await service.updateSettings(try await userId(req), try body(req, SettingsRequest.self))
    }
    // GET /api/quiz?area=FRONTEND – вопросы мини-теста по направлению
    api.get("quiz") { req async throws -> [QuizQuestionDto] in
        _ = try await userId(req)
        guard let raw = req.query[String.self, at: "area"], let area = ItArea(rawValue: raw) else {
            throw APIError.badRequest("Неизвестное направление")
        }
        return service.quiz(area)
    }
    api.get("plan") { req async throws -> PlanDto in
        try await service.plan(try await userId(req))
    }
    api.get("today") { req async throws -> TodayDto in
        try await service.today(try await userId(req))
    }
    api.post("answer") { req async throws -> EvaluationDto in
        try await service.answer(try await userId(req), try body(req, AnswerRequest.self))
    }
    api.post("chat") { req async throws -> ChatReply in
        try await service.chat(try await userId(req), try body(req, ChatRequest.self))
    }
    api.get("progress") { req async throws -> ProgressDto in
        try await service.progress(try await userId(req))
    }
    api.delete("account") { req async throws -> HTTPStatus in
        try await service.delete(try await userId(req))
        return .noContent
    }
}

extension StatsDto: Content {}

// Любая ошибка превращается в ответ { "error": "текст" }: приложение показывает этот текст человеку
struct APIErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch let error as APIError {
            return try Self.response(error.status, error.message)
        } catch is DecodingError {
            return try Self.response(.badRequest, "Неверный формат данных")
        } catch let abort as any AbortError {
            let message = switch abort.status {
            case .notFound: "Не найдено"
            case .badRequest, .unsupportedMediaType, .unprocessableEntity: "Неверный формат данных"
            case .payloadTooLarge: "Слишком большой запрос"
            default: abort.reason
            }
            return try Self.response(abort.status, message)
        } catch {
            request.logger.error("Необработанная ошибка: \(String(reflecting: error))")
            return try Self.response(.internalServerError, "Ошибка сервера")
        }
    }

    private static func response(_ status: HTTPResponseStatus, _ message: String) throws -> Response {
        let response = Response(status: status)
        try response.content.encode(ErrorDto(error: message))
        return response
    }
}
