package kg.aimentor.server

import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.call
import io.ktor.server.application.install
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.authenticate
import io.ktor.server.auth.jwt.JWTPrincipal
import io.ktor.server.auth.jwt.jwt
import io.ktor.server.auth.principal
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.plugins.BadRequestException
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.response.respondText
import io.ktor.server.routing.delete
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.put
import io.ktor.server.routing.route
import io.ktor.server.routing.routing
import kg.aimentor.shared.AnswerRequest
import kg.aimentor.shared.AuthResponse
import kg.aimentor.shared.ChatRequest
import kg.aimentor.shared.DevAuthRequest
import kg.aimentor.shared.ErrorDto
import kg.aimentor.shared.GoogleAuthRequest
import kg.aimentor.shared.ProfileRequest
import kg.aimentor.shared.SettingsRequest
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

private val log = LoggerFactory.getLogger("kg.aimentor.server.Application")

private fun config(name: String): String? =
    (System.getenv(name) ?: System.getProperty(name))?.takeIf { it.isNotBlank() }

fun main() {
    val port = config("PORT")?.toIntOrNull() ?: 8080
    val service = defaultService()
    val auth = defaultAuth()
    embeddedServer(Netty, port = port, host = "0.0.0.0") { module(service, auth) }.start(wait = true)
}

// Если заданы LLM_API_KEY и LLM_MODEL – проверяет внешняя модель, а офлайн-проверка остаётся резервом.
// Если задан DATABASE_URL – данные хранятся в PostgreSQL, иначе в памяти (пропадают при перезапуске).
// Ключи и пароли храним только в переменных окружения, в коде их быть не должно.
fun defaultService(): MentorService {
    val rules = RuleBasedLlm()
    val baseUrl = config("LLM_BASE_URL") ?: "https://generativelanguage.googleapis.com/v1beta/openai/"
    val key = config("LLM_API_KEY")
    val model = config("LLM_MODEL")

    val llm: LlmClient = if (key != null && model != null) {
        val reasoning = config("LLM_REASONING") // low / medium / high; для скорости – low
        log.info("Внешняя модель: {} ({}), reasoning_effort={}", model, baseUrl, reasoning ?: "по умолчанию")
        FallbackLlm(HttpLlm(baseUrl, key, model, reasoning), rules)
    } else {
        log.info("LLM_API_KEY или LLM_MODEL не заданы – работает офлайн-проверка")
        rules
    }

    val store: UserStore = config("DATABASE_URL")?.let { url ->
        log.info("Хранилище: PostgreSQL")
        PostgresUserStore.connect(url, config("DATABASE_USER"), config("DATABASE_PASSWORD"))
    } ?: run {
        log.warn("DATABASE_URL не задан – данные хранятся в памяти и пропадут при перезапуске")
        InMemoryUserStore()
    }
    return MentorService(SourceBase.load(), llm, store, rules)
}

fun defaultAuth(): AuthConfig {
    val secret = config("JWT_SECRET") ?: run {
        log.warn("JWT_SECRET не задан – сгенерирован временный, после перезапуска всем придётся войти заново")
        Base64.getEncoder().encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) })
    }
    val clientIds = config("GOOGLE_CLIENT_ID")?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }.orEmpty()
    val dev = config("AUTH_DEV") == "true"
    if (clientIds.isEmpty()) log.warn("GOOGLE_CLIENT_ID не задан – вход через Google выключен")
    if (dev) log.warn("AUTH_DEV=true – разрешён вход без Google. Не включай это на боевом сервере!")
    return AuthConfig(secret, clientIds, dev, config("ADMIN_TOKEN"))
}

private fun ApplicationCall.userId(): String =
    principal<JWTPrincipal>()?.payload?.subject ?: throw Unauthorized("Нужно войти")

// Сравнение за постоянное время, чтобы токен нельзя было подобрать по времени ответа
private fun sameToken(a: String, b: String) = MessageDigest.isEqual(a.toByteArray(), b.toByteArray())

fun Application.module(
    service: MentorService = defaultService(),
    auth: AuthConfig = defaultAuth(),
    google: GoogleVerifier? = auth.googleClientIds.takeIf { it.isNotEmpty() }?.let { GoogleJwksVerifier(it) },
) {
    val tokens = TokenIssuer(auth.jwtSecret)

    install(ContentNegotiation) {
        json(Json { encodeDefaults = true; ignoreUnknownKeys = true })
    }
    install(Authentication) {
        jwt("user") {
            verifier(tokens.verifier)
            validate { cred -> cred.payload.subject?.let { JWTPrincipal(cred.payload) } }
            challenge { _, _ -> call.respond(HttpStatusCode.Unauthorized, ErrorDto("Нужно войти заново")) }
        }
    }
    install(StatusPages) {
        exception<BadRequest> { call, e -> call.respond(HttpStatusCode.BadRequest, ErrorDto(e.message ?: "Неверный запрос")) }
        exception<NotFound> { call, e -> call.respond(HttpStatusCode.NotFound, ErrorDto(e.message ?: "Не найдено")) }
        exception<Unauthorized> { call, e -> call.respond(HttpStatusCode.Unauthorized, ErrorDto(e.message ?: "Нужно войти")) }
        exception<BadRequestException> { call, _ -> call.respond(HttpStatusCode.BadRequest, ErrorDto("Неверный формат данных")) }
        exception<SerializationException> { call, _ -> call.respond(HttpStatusCode.BadRequest, ErrorDto("Неверный формат данных")) }
        exception<Throwable> { call, e ->
            log.error("Необработанная ошибка", e)
            call.respond(HttpStatusCode.InternalServerError, ErrorDto("Ошибка сервера"))
        }
    }
    routing {
        get("/health") { call.respondText("ok") }

        // Сводка по активности. Включается переменной ADMIN_TOKEN, запрос с заголовком X-Admin-Token.
        get("/admin/stats") {
            val expected = auth.adminToken ?: throw NotFound("Не найдено")
            val given = call.request.headers["X-Admin-Token"] ?: ""
            if (!sameToken(given, expected)) throw Unauthorized("Неверный токен")
            call.respond(service.stats())
        }

        route("/api") {
            route("/auth") {
                post("/google") {
                    val verifier = google ?: throw NotFound("Вход через Google не настроен на сервере")
                    val req = call.receive<GoogleAuthRequest>()
                    val userId = "g:" + verifier.verify(req.idToken)
                    call.respond(AuthResponse(tokens.issue(userId), userId))
                }
                post("/dev") {
                    if (!auth.devLogin) throw NotFound("Вход для разработки выключен")
                    val req = call.receive<DevAuthRequest>()
                    if (req.deviceId.length !in 8..64) throw BadRequest("Неверный id устройства")
                    val userId = "dev:" + req.deviceId
                    call.respond(AuthResponse(tokens.issue(userId), userId))
                }
            }

            authenticate("user") {
                post("/profile") {
                    val req = call.receive<ProfileRequest>()
                    call.respond(HttpStatusCode.Created, service.createProfile(call.userId(), req))
                }
                put("/settings") {
                    val req = call.receive<SettingsRequest>()
                    call.respond(service.updateSettings(call.userId(), req))
                }
                get("/plan") { call.respond(service.plan(call.userId())) }
                get("/today") { call.respond(service.today(call.userId())) }
                post("/answer") {
                    val req = call.receive<AnswerRequest>()
                    call.respond(service.answer(call.userId(), req))
                }
                post("/chat") {
                    val req = call.receive<ChatRequest>()
                    call.respond(service.chat(call.userId(), req))
                }
                get("/progress") { call.respond(service.progress(call.userId())) }
                delete("/account") {
                    service.delete(call.userId())
                    call.respond(HttpStatusCode.NoContent)
                }
            }
        }
    }
}
