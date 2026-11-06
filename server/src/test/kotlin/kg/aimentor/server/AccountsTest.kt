package kg.aimentor.server

import io.ktor.client.call.body
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.bearerAuth
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.testing.testApplication
import kg.aimentor.shared.AuthResponse
import kg.aimentor.shared.ErrorDto
import kg.aimentor.shared.LoginRequest
import kg.aimentor.shared.RegisterRequest
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AccountsTest {
    private val store = InMemoryUserStore()
    private var clock = 1_000_000L
    private val accounts = AccountService(store) { clock }

    @Test
    fun passwordHashIsSaltedAndVerifiable() {
        val a = Passwords.hash("секрет-123")
        val b = Passwords.hash("секрет-123")
        assertNotEquals(a, b, "у одинаковых паролей разная соль")
        assertFalse(a.contains("секрет"))
        assertTrue(Passwords.verify("секрет-123", a))
        assertFalse(Passwords.verify("секрет-124", a))
    }

    @Test
    fun registerThenLoginWithAnyEmailCase() {
        val acc = accounts.register(RegisterRequest(" Аня ", "Anya@Mail.ru ", "password1"))
        assertEquals("anya@mail.ru", acc.email)
        assertEquals("Аня", acc.name)
        assertEquals(acc.userId, accounts.login(LoginRequest("ANYA@mail.ru", "password1")).userId)
    }

    @Test
    fun duplicateEmailAndBadInputAreRejected() {
        accounts.register(RegisterRequest("Аня", "anya@mail.ru", "password1"))
        assertFailsWith<Conflict> { accounts.register(RegisterRequest("Другая", "ANYA@mail.ru", "password2")) }
        assertFailsWith<BadRequest> { accounts.register(RegisterRequest("Аня", "не-почта", "password1")) }
        assertFailsWith<BadRequest> { accounts.register(RegisterRequest("Аня", "a@b.ru", "short")) }
        assertFailsWith<BadRequest> { accounts.register(RegisterRequest(" ", "a@b.ru", "password1")) }
    }

    @Test
    fun wrongPasswordAndUnknownEmailGiveSameError() {
        accounts.register(RegisterRequest("Аня", "anya@mail.ru", "password1"))
        val wrong = assertFailsWith<Unauthorized> { accounts.login(LoginRequest("anya@mail.ru", "password2")) }
        val unknown = assertFailsWith<Unauthorized> { accounts.login(LoginRequest("nobody@mail.ru", "password1")) }
        assertEquals(wrong.message, unknown.message) // по ответу нельзя узнать, есть ли такой email
    }

    @Test
    fun tooManyFailuresLockLoginForAWhile() {
        accounts.register(RegisterRequest("Аня", "anya@mail.ru", "password1"))
        repeat(AccountService.MAX_FAILURES) {
            assertFailsWith<Unauthorized> { accounts.login(LoginRequest("anya@mail.ru", "wrong-pass")) }
        }
        // даже верный пароль не пускает, пока действует блокировка
        assertFailsWith<TooManyRequests> { accounts.login(LoginRequest("anya@mail.ru", "password1")) }
        clock += AccountService.LOCK_MS
        accounts.login(LoginRequest("anya@mail.ru", "password1"))
    }

    @Test
    fun deletingUserRemovesAccountSoEmailIsFreeAgain() {
        val acc = accounts.register(RegisterRequest("Аня", "anya@mail.ru", "password1"))
        store.delete(acc.userId)
        assertNull(store.findAccount("anya@mail.ru"))
        accounts.register(RegisterRequest("Аня", "anya@mail.ru", "password2"))
    }

    @Test
    fun registerLoginAndDeleteOverHttp() = testApplication {
        val service = MentorService(SourceBase.load(), RuleBasedLlm(), store) { LocalDate.of(2026, 11, 2) }
        application { module(service, AuthConfig("test-secret"), google = null, accounts = accounts) }
        val client = createClient { install(ContentNegotiation) { json() } }

        val registered = client.post("/api/auth/register") {
            contentType(ContentType.Application.Json)
            setBody(RegisterRequest("Аня", "anya@mail.ru", "password1"))
        }
        assertEquals(HttpStatusCode.Created, registered.status)
        val auth = registered.body<AuthResponse>()
        assertEquals("Аня", auth.name)
        // зарегистрированный пользователь сразу может работать с API (профиля пока нет – 404)
        assertEquals(HttpStatusCode.NotFound, client.get("/api/plan") { bearerAuth(auth.token) }.status)

        val again = client.post("/api/auth/register") {
            contentType(ContentType.Application.Json)
            setBody(RegisterRequest("Аня", "anya@mail.ru", "password1"))
        }
        assertEquals(HttpStatusCode.Conflict, again.status)
        assertTrue(again.body<ErrorDto>().error.contains("уже зарегистрирован"))

        val badLogin = client.post("/api/auth/login") {
            contentType(ContentType.Application.Json)
            setBody(LoginRequest("anya@mail.ru", "nope-nope"))
        }
        assertEquals(HttpStatusCode.Unauthorized, badLogin.status)

        val login = client.post("/api/auth/login") {
            contentType(ContentType.Application.Json)
            setBody(LoginRequest("anya@mail.ru", "password1"))
        }.body<AuthResponse>()
        assertEquals(auth.userId, login.userId)

        assertEquals(HttpStatusCode.NoContent, client.delete("/api/account") { bearerAuth(login.token) }.status)
        val afterDelete = client.post("/api/auth/login") {
            contentType(ContentType.Application.Json)
            setBody(LoginRequest("anya@mail.ru", "password1"))
        }
        assertEquals(HttpStatusCode.Unauthorized, afterDelete.status)
    }
}
