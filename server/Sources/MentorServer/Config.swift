import Foundation
import Logging
import PostgresNIO

// Настройки сервера из переменных окружения. Ключи и пароли храним только там, в коде их быть не должно.
public struct ServerConfig: Sendable {
    public let port: Int
    public let store: any UserStore
    public let postgres: PostgresUserStore? // если задан DATABASE_URL; ему нужен запущенный client.run()
    public let service: MentorService
    public let auth: AuthConfig
    public let google: (any GoogleVerifier)?
    public let accounts: AccountService

    static func env(_ name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name]?.trimmed, !value.isEmpty else { return nil }
        return value
    }

    public static func fromEnvironment(logger: Logger) throws -> ServerConfig {
        let store: any UserStore
        var postgres: PostgresUserStore?
        if let url = env("DATABASE_URL") {
            logger.info("Хранилище: PostgreSQL")
            let config = try PostgresUserStore.configuration(url: url, user: env("DATABASE_USER"), password: env("DATABASE_PASSWORD"))
            let pg = PostgresUserStore(client: PostgresClient(configuration: config, backgroundLogger: logger))
            postgres = pg
            store = pg
        } else {
            logger.warning("DATABASE_URL не задан – данные хранятся в памяти и пропадут при перезапуске")
            store = InMemoryUserStore()
        }

        // Если заданы LLM_API_KEY и LLM_MODEL – проверяет внешняя модель, а офлайн-проверка остаётся резервом
        let rules = RuleBasedLlm()
        let llm: any LlmClient
        if let key = env("LLM_API_KEY"), let model = env("LLM_MODEL") {
            let baseURL = env("LLM_BASE_URL") ?? "https://generativelanguage.googleapis.com/v1beta/openai/"
            let reasoning = env("LLM_REASONING") // low / medium / high; для скорости – low
            logger.info("Внешняя модель: \(model) (\(baseURL)), reasoning_effort=\(reasoning ?? "по умолчанию")")
            llm = FallbackLlm(primary: HttpLlm(baseURL: baseURL, apiKey: key, model: model, reasoningEffort: reasoning), fallback: rules)
        } else {
            logger.info("LLM_API_KEY или LLM_MODEL не заданы – работает офлайн-проверка")
            llm = rules
        }

        let secret = env("JWT_SECRET") ?? {
            logger.warning("JWT_SECRET не задан – сгенерирован временный, после перезапуска всем придётся войти заново")
            var rng = SystemRandomNumberGenerator()
            return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &rng) }).base64EncodedString()
        }()
        let clientIds = (env("GOOGLE_CLIENT_ID") ?? "").split(separator: ",").map(\.trimmed).filter { !$0.isEmpty }
        let dev = env("AUTH_DEV") == "true"
        if clientIds.isEmpty { logger.warning("GOOGLE_CLIENT_ID не задан – вход через Google выключен") }
        if dev { logger.warning("AUTH_DEV=true – разрешён вход без Google. Не включай это на боевом сервере!") }

        return ServerConfig(
            port: env("PORT").flatMap(Int.init) ?? 8080,
            store: store,
            postgres: postgres,
            service: MentorService(sources: try SourceBase.load(), llm: llm, store: store, offline: rules),
            auth: AuthConfig(jwtSecret: secret, googleClientIds: clientIds, devLogin: dev, adminToken: env("ADMIN_TOKEN")),
            google: clientIds.isEmpty ? nil : GoogleJwksVerifier(clientIds: clientIds),
            accounts: AccountService(store: store)
        )
    }
}
