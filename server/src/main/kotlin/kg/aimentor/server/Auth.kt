package kg.aimentor.server

import com.auth0.jwk.JwkProviderBuilder
import com.auth0.jwt.JWT
import com.auth0.jwt.JWTVerifier
import com.auth0.jwt.algorithms.Algorithm
import java.net.URI
import java.security.interfaces.RSAPublicKey
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.concurrent.TimeUnit

class Unauthorized(message: String) : RuntimeException(message)

// googleClientIds – Web Client ID из Google Cloud Console (через запятую, если их несколько).
// devLogin – вход без Google по id устройства, только для разработки.
class AuthConfig(
    val jwtSecret: String,
    val googleClientIds: List<String> = emptyList(),
    val devLogin: Boolean = false,
    val adminToken: String? = null,
)

// Собственные токены сервера: приложение получает их после входа и шлёт в Authorization: Bearer
class TokenIssuer(secret: String) {
    private val algorithm = Algorithm.HMAC256(secret)

    val verifier: JWTVerifier = JWT.require(algorithm).withIssuer(ISSUER).withAudience(AUDIENCE).build()

    fun issue(userId: String): String = JWT.create()
        .withIssuer(ISSUER)
        .withAudience(AUDIENCE)
        .withSubject(userId)
        .withExpiresAt(Instant.now().plus(TTL_DAYS, ChronoUnit.DAYS))
        .sign(algorithm)

    companion object {
        const val ISSUER = "ai-mentor"
        const val AUDIENCE = "ai-mentor-app"
        const val TTL_DAYS = 30L
    }
}

fun interface GoogleVerifier {
    // возвращает стабильный id пользователя Google (sub) или бросает Unauthorized
    fun verify(idToken: String): String
}

// Проверяет подпись ID-токена ключами Google, издателя и что токен выдан нашему приложению
class GoogleJwksVerifier(private val clientIds: List<String>) : GoogleVerifier {
    private val jwks = JwkProviderBuilder(URI("https://www.googleapis.com/oauth2/v3/certs").toURL())
        .cached(10, 24, TimeUnit.HOURS)
        .rateLimited(10, 1, TimeUnit.MINUTES)
        .build()

    override fun verify(idToken: String): String = try {
        val decoded = JWT.decode(idToken)
        val key = jwks.get(decoded.keyId).publicKey as RSAPublicKey
        JWT.require(Algorithm.RSA256(key, null))
            .withIssuer("https://accounts.google.com", "accounts.google.com")
            .withAnyOfAudience(*clientIds.toTypedArray())
            .build()
            .verify(idToken)
            .subject
    } catch (e: Exception) {
        throw Unauthorized("Не удалось проверить вход через Google")
    }
}
