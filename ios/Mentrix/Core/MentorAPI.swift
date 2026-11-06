import Foundation

// Токен истёк или недействителен – нужно войти заново
struct SessionExpired: Error {}

// Ошибка, которую сервер объяснил (400/404): текст можно показать пользователю
struct ServerMessage: Error, LocalizedError {
    let message: String
    var status: Int = 400
    var errorDescription: String? { message }
}

// Любой другой неуспешный ответ сервера
struct HTTPError: Error {
    let status: Int
}

// Всё, что приложение умеет спрашивать у сервера. Протокол – чтобы в тестах подменять сеть.
protocol MentorBackend: AnyObject {
    func register(_ req: RegisterRequest) async throws -> AuthResponse
    func login(_ req: LoginRequest) async throws -> AuthResponse
    func loginGoogle(idToken: String) async throws -> AuthResponse
    func loginDev(deviceId: String) async throws -> AuthResponse
    func plan() async throws -> PlanDto? // nil – профиля ещё нет (нужен онбординг)
    func createProfile(_ req: ProfileRequest) async throws -> PlanDto
    func updateSettings(_ req: SettingsRequest) async throws -> PlanDto
    func today() async throws -> TodayDto
    func progress() async throws -> ProgressDto
    func answer(_ req: AnswerRequest) async throws -> EvaluationDto
    func chat(_ req: ChatRequest) async throws -> ChatReply
    func deleteAccount() async throws
}

final class MentorAPI: MentorBackend {
    private let baseURL: URL
    private let token: () -> String?
    private let urlSession: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL, token: @escaping () -> String?) {
        self.baseURL = baseURL
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        self.urlSession = URLSession(configuration: config)
    }

    private enum Method: String { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

    private struct Empty: Encodable {}

    // 401 превращаем в SessionExpired, понятные ошибки сервера – в ServerMessage.
    // При входе (signIn = true) 401 означает «неверный пароль», а не истёкшую сессию.
    private func send(_ method: Method, _ path: String, body: (some Encodable)? = Empty?.none, signIn: Bool = false) async throws -> (Data, Int) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return (data, status) }
        if status == 401 && !signIn { throw SessionExpired() }
        if (400..<500).contains(status), let dto = try? decoder.decode(ErrorDto.self, from: data) {
            throw ServerMessage(message: dto.error, status: status)
        }
        throw HTTPError(status: status)
    }

    private func call<T: Decodable>(_ method: Method, _ path: String, body: (some Encodable)? = Empty?.none, signIn: Bool = false) async throws -> T {
        let (data, _) = try await send(method, path, body: body, signIn: signIn)
        return try decoder.decode(T.self, from: data)
    }

    func register(_ req: RegisterRequest) async throws -> AuthResponse {
        try await call(.post, "api/auth/register", body: req, signIn: true)
    }

    func login(_ req: LoginRequest) async throws -> AuthResponse {
        try await call(.post, "api/auth/login", body: req, signIn: true)
    }

    func loginGoogle(idToken: String) async throws -> AuthResponse {
        try await call(.post, "api/auth/google", body: GoogleAuthRequest(idToken: idToken), signIn: true)
    }

    func loginDev(deviceId: String) async throws -> AuthResponse {
        try await call(.post, "api/auth/dev", body: DevAuthRequest(deviceId: deviceId))
    }

    func plan() async throws -> PlanDto? {
        do {
            let plan: PlanDto = try await call(.get, "api/plan")
            return plan
        } catch let error as HTTPError where error.status == 404 {
            return nil
        } catch let error as ServerMessage where error.status == 404 {
            // сервер отвечает 404 с текстом ошибки, если профиля ещё нет
            return nil
        }
    }

    func createProfile(_ req: ProfileRequest) async throws -> PlanDto {
        try await call(.post, "api/profile", body: req)
    }

    func updateSettings(_ req: SettingsRequest) async throws -> PlanDto {
        try await call(.put, "api/settings", body: req)
    }

    func today() async throws -> TodayDto { try await call(.get, "api/today") }

    func progress() async throws -> ProgressDto { try await call(.get, "api/progress") }

    func answer(_ req: AnswerRequest) async throws -> EvaluationDto {
        try await call(.post, "api/answer", body: req)
    }

    func chat(_ req: ChatRequest) async throws -> ChatReply {
        try await call(.post, "api/chat", body: req)
    }

    func deleteAccount() async throws {
        _ = try await send(.delete, "api/account")
    }
}
