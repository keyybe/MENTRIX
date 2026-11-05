package kg.aimentor.app

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.android.Android
import io.ktor.client.plugins.ClientRequestException
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.put
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kg.aimentor.shared.AnswerRequest
import kg.aimentor.shared.AuthResponse
import kg.aimentor.shared.ChatReply
import kg.aimentor.shared.ChatRequest
import kg.aimentor.shared.DevAuthRequest
import kg.aimentor.shared.ErrorDto
import kg.aimentor.shared.EvaluationDto
import kg.aimentor.shared.GoogleAuthRequest
import kg.aimentor.shared.PlanDto
import kg.aimentor.shared.ProfileRequest
import kg.aimentor.shared.ProgressDto
import kg.aimentor.shared.SettingsRequest
import kg.aimentor.shared.TodayDto
import kotlinx.serialization.json.Json

// Токен истёк или недействителен – нужно войти заново
class SessionExpired : Exception()

// Ошибка, которую сервер объяснил (400/404): текст можно показать пользователю
class ServerMessage(message: String) : Exception(message)

// Всё, что приложение умеет спрашивать у сервера. Интерфейс – чтобы в тестах подменять сеть.
interface MentorBackend {
    suspend fun loginGoogle(idToken: String): AuthResponse
    suspend fun loginDev(deviceId: String): AuthResponse
    suspend fun plan(): PlanDto? // null – профиля ещё нет (нужен онбординг)
    suspend fun createProfile(req: ProfileRequest): PlanDto
    suspend fun updateSettings(req: SettingsRequest): PlanDto
    suspend fun today(): TodayDto
    suspend fun progress(): ProgressDto
    suspend fun answer(req: AnswerRequest): EvaluationDto
    suspend fun chat(req: ChatRequest): ChatReply
    suspend fun deleteAccount()
}

class MentorApi(baseUrl: String, private val token: () -> String?) : MentorBackend {
    private val json = Json { ignoreUnknownKeys = true }
    private val client = HttpClient(Android) {
        expectSuccess = true
        install(ContentNegotiation) { json(json) }
        install(HttpTimeout) { requestTimeoutMillis = 30_000 }
        defaultRequest {
            url(baseUrl)
            token()?.let { header(HttpHeaders.Authorization, "Bearer $it") }
        }
    }

    // 401 превращаем в SessionExpired, понятные ошибки сервера – в ServerMessage
    private suspend fun <T> call(block: suspend () -> T): T = try {
        block()
    } catch (e: ClientRequestException) {
        when (e.response.status) {
            HttpStatusCode.Unauthorized -> throw SessionExpired()
            else -> {
                val text = runCatching { e.response.body<ErrorDto>().error }.getOrNull()
                throw if (text != null) ServerMessage(text) else e
            }
        }
    }

    override suspend fun loginGoogle(idToken: String): AuthResponse = call {
        client.post("api/auth/google") {
            contentType(ContentType.Application.Json)
            setBody(GoogleAuthRequest(idToken))
        }.body()
    }

    override suspend fun loginDev(deviceId: String): AuthResponse = call {
        client.post("api/auth/dev") {
            contentType(ContentType.Application.Json)
            setBody(DevAuthRequest(deviceId))
        }.body()
    }

    override suspend fun plan(): PlanDto? = call {
        try {
            client.get("api/plan").body<PlanDto>()
        } catch (e: ClientRequestException) {
            if (e.response.status == HttpStatusCode.NotFound) null else throw e
        }
    }

    override suspend fun createProfile(req: ProfileRequest): PlanDto = call {
        client.post("api/profile") {
            contentType(ContentType.Application.Json)
            setBody(req)
        }.body()
    }

    override suspend fun updateSettings(req: SettingsRequest): PlanDto = call {
        client.put("api/settings") {
            contentType(ContentType.Application.Json)
            setBody(req)
        }.body()
    }

    override suspend fun today(): TodayDto = call { client.get("api/today").body() }

    override suspend fun progress(): ProgressDto = call { client.get("api/progress").body() }

    override suspend fun answer(req: AnswerRequest): EvaluationDto = call {
        client.post("api/answer") {
            contentType(ContentType.Application.Json)
            setBody(req)
        }.body()
    }

    override suspend fun chat(req: ChatRequest): ChatReply = call {
        client.post("api/chat") {
            contentType(ContentType.Application.Json)
            setBody(req)
        }.body()
    }

    override suspend fun deleteAccount() {
        call { client.delete("api/account") }
    }

    fun close() = client.close()
}
