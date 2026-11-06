package kg.aimentor.server

import kg.aimentor.shared.LoginRequest
import kg.aimentor.shared.RegisterRequest
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

class Conflict(message: String) : RuntimeException(message)
class TooManyRequests(message: String) : RuntimeException(message)

// Пароли храним только как PBKDF2-SHA256 с солью: даже при утечке базы их нельзя прочитать.
// Формат строки: pbkdf2_sha256$итерации$соль$хеш (соль и хеш в Base64).
object Passwords {
    private const val ITERATIONS = 210_000
    private const val KEY_BITS = 256
    private val random = SecureRandom()

    fun hash(password: String): String {
        val salt = ByteArray(16).also { random.nextBytes(it) }
        val hash = derive(password, salt, ITERATIONS)
        val b64 = Base64.getEncoder()
        return "pbkdf2_sha256\$$ITERATIONS\$${b64.encodeToString(salt)}\$${b64.encodeToString(hash)}"
    }

    fun verify(password: String, stored: String): Boolean {
        val parts = stored.split("$")
        if (parts.size != 4 || parts[0] != "pbkdf2_sha256") return false
        val b64 = Base64.getDecoder()
        val expected = b64.decode(parts[3])
        val actual = derive(password, b64.decode(parts[2]), parts[1].toInt())
        // сравнение за постоянное время, чтобы по скорости ответа нельзя было подобрать хеш
        return MessageDigest.isEqual(expected, actual)
    }

    private fun derive(password: String, salt: ByteArray, iterations: Int): ByteArray =
        SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            .generateSecret(PBEKeySpec(password.toCharArray(), salt, iterations, KEY_BITS))
            .encoded
}

// Регистрация и вход по email. now – для тестов ограничения попыток.
class AccountService(private val store: UserStore, private val now: () -> Long = System::currentTimeMillis) {
    companion object {
        const val MIN_PASSWORD = 8
        const val MAX_PASSWORD = 128
        const val MAX_NAME = 40
        const val MAX_FAILURES = 5                // столько неудачных входов подряд…
        const val LOCK_MS = 15 * 60 * 1000L       // …блокируют вход на 15 минут
        private val EMAIL = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]{2,}$")
    }

    private class Failures(val count: Int, val since: Long)
    private val failures = ConcurrentHashMap<String, Failures>()

    // Хеш-пустышка: если email не найден, всё равно считаем хеш, чтобы по времени ответа
    // нельзя было узнать, зарегистрирован ли email
    private val dummyHash by lazy { Passwords.hash(UUID.randomUUID().toString()) }

    private fun normalize(email: String) = email.trim().lowercase()

    fun register(req: RegisterRequest): Account {
        val email = normalize(req.email)
        val name = req.name.trim()
        if (name.isEmpty() || name.length > MAX_NAME) throw BadRequest("Укажи имя (до $MAX_NAME символов)")
        if (!EMAIL.matches(email) || email.length > 254) throw BadRequest("Проверь email – похоже, в нём ошибка")
        if (req.password.length < MIN_PASSWORD) throw BadRequest("Пароль должен быть не короче $MIN_PASSWORD символов")
        if (req.password.length > MAX_PASSWORD) throw BadRequest("Слишком длинный пароль")
        if (req.password.isBlank()) throw BadRequest("Пароль не может состоять из пробелов")

        val account = Account("e:" + UUID.randomUUID(), email, Passwords.hash(req.password), name)
        if (!store.createAccount(account)) throw Conflict("Этот email уже зарегистрирован. Войди в аккаунт.")
        return account
    }

    fun login(req: LoginRequest): Account {
        val email = normalize(req.email)
        val f = failures[email]
        if (f != null && f.count >= MAX_FAILURES && now() - f.since < LOCK_MS) {
            throw TooManyRequests("Слишком много попыток входа. Попробуй через 15 минут.")
        }
        val account = store.findAccount(email)
        val passwordOk = Passwords.verify(req.password, account?.passwordHash ?: dummyHash)
        if (account == null || !passwordOk) {
            failures.compute(email) { _, old ->
                if (old == null || now() - old.since >= LOCK_MS) Failures(1, now()) else Failures(old.count + 1, old.since)
            }
            throw Unauthorized("Неверный email или пароль")
        }
        failures.remove(email)
        return account
    }
}
