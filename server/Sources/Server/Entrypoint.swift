import MentorServer
import Vapor

// swift run mentor-server – запускает сервер на порту PORT (по умолчанию 8080)
@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Application.make(env)

        do {
            let config = try ServerConfig.fromEnvironment(logger: app.logger)
            app.http.server.configuration.hostname = "0.0.0.0"
            app.http.server.configuration.port = config.port
            try await configure(app, service: config.service, auth: config.auth, google: config.google, accounts: config.accounts)

            try await withThrowingDiscardingTaskGroup { group in
                if let pg = config.postgres {
                    // пул соединений с базой работает, пока работает сервер
                    group.addTask { await pg.client.run() }
                    try await pg.migrate()
                }
                try await app.execute()
                group.cancelAll()
            }
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
