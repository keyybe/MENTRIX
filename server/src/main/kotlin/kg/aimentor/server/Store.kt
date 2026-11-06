package kg.aimentor.server

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.net.URI
import java.sql.Date
import java.time.LocalDate
import java.util.concurrent.ConcurrentHashMap

object LocalDateSerializer : KSerializer<LocalDate> {
    override val descriptor = PrimitiveSerialDescriptor("LocalDate", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: LocalDate) = encoder.encodeString(value.toString())
    override fun deserialize(decoder: Decoder): LocalDate = LocalDate.parse(decoder.decodeString())
}

// Сводка для GET /admin/stats: сколько людей реально занимаются
@Serializable
data class StatsDto(
    val users: Int,
    val active1d: Int,
    val active7d: Int,
    val active30d: Int,
    val profiles7d: Int,
    val answers7d: Int,
    val passed7d: Int,
    val chats7d: Int,
)

enum class EventType { PROFILE, ANSWER_PASS, ANSWER_FAIL, CHAT, OPEN }

// Состояние пользователя хранится одним JSON-документом: для MVP этого достаточно,
// а схема данных может меняться без миграций (новые поля получают значения по умолчанию).
interface UserStore {
    fun load(userId: String): UserState?
    fun save(userId: String, state: UserState)
    fun delete(userId: String) // удаляет и состояние, и события, и аккаунт с паролем
    fun event(userId: String, type: EventType, day: LocalDate)
    fun stats(today: LocalDate): StatsDto

    // Аккаунты с входом по email. false – такой email уже зарегистрирован.
    fun createAccount(account: Account): Boolean
    fun findAccount(email: String): Account?
}

// email хранится в нижнем регистре, пароль – только в виде хеша (см. Passwords)
data class Account(val userId: String, val email: String, val passwordHash: String, val name: String)

internal val storeJson = Json { ignoreUnknownKeys = true }

// Для тестов и локального запуска. Хранит JSON-строки, как и Postgres, поэтому ошибки сериализации видны сразу.
class InMemoryUserStore : UserStore {
    private val users = ConcurrentHashMap<String, String>()
    private val events = java.util.Collections.synchronizedList(mutableListOf<Triple<String, EventType, LocalDate>>())
    private val accounts = ConcurrentHashMap<String, Account>() // ключ – email

    override fun load(userId: String) = users[userId]?.let { storeJson.decodeFromString<UserState>(it) }
    override fun save(userId: String, state: UserState) {
        users[userId] = storeJson.encodeToString(UserState.serializer(), state)
    }

    override fun delete(userId: String) {
        users.remove(userId)
        events.removeIf { it.first == userId }
        accounts.values.removeIf { it.userId == userId }
    }

    override fun createAccount(account: Account) = accounts.putIfAbsent(account.email, account) == null
    override fun findAccount(email: String) = accounts[email]

    override fun event(userId: String, type: EventType, day: LocalDate) {
        events.add(Triple(userId, type, day))
    }

    override fun stats(today: LocalDate): StatsDto {
        val all = synchronized(events) { events.toList() }
        fun since(days: Long) = all.filter { !it.third.isBefore(today.minusDays(days - 1)) }
        fun active(days: Long) = since(days).map { it.first }.distinct().size
        val week = since(7).groupingBy { it.second }.eachCount()
        return StatsDto(
            users = users.size,
            active1d = active(1), active7d = active(7), active30d = active(30),
            profiles7d = week[EventType.PROFILE] ?: 0,
            answers7d = (week[EventType.ANSWER_PASS] ?: 0) + (week[EventType.ANSWER_FAIL] ?: 0),
            passed7d = week[EventType.ANSWER_PASS] ?: 0,
            chats7d = week[EventType.CHAT] ?: 0,
        )
    }
}

class PostgresUserStore(private val ds: HikariDataSource) : UserStore, AutoCloseable {
    override fun close() = ds.close()

    init {
        ds.connection.use { c ->
            c.createStatement().use { st ->
                st.execute(
                    """
                    CREATE TABLE IF NOT EXISTS users (
                        id TEXT PRIMARY KEY,
                        state JSONB NOT NULL,
                        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
                    )
                    """.trimIndent()
                )
                st.execute(
                    """
                    CREATE TABLE IF NOT EXISTS events (
                        id BIGSERIAL PRIMARY KEY,
                        user_id TEXT NOT NULL,
                        type TEXT NOT NULL,
                        day DATE NOT NULL
                    )
                    """.trimIndent()
                )
                st.execute(
                    """
                    CREATE TABLE IF NOT EXISTS accounts (
                        user_id TEXT PRIMARY KEY,
                        email TEXT NOT NULL UNIQUE,
                        password_hash TEXT NOT NULL,
                        name TEXT NOT NULL,
                        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
                    )
                    """.trimIndent()
                )
                st.execute("CREATE INDEX IF NOT EXISTS events_day ON events(day)")
                st.execute("CREATE INDEX IF NOT EXISTS events_user ON events(user_id)")
            }
        }
    }

    override fun load(userId: String): UserState? = ds.connection.use { c ->
        c.prepareStatement("SELECT state::text FROM users WHERE id = ?").use { ps ->
            ps.setString(1, userId)
            ps.executeQuery().use { rs -> if (rs.next()) storeJson.decodeFromString<UserState>(rs.getString(1)) else null }
        }
    }

    override fun save(userId: String, state: UserState) {
        ds.connection.use { c ->
            c.prepareStatement(
                "INSERT INTO users(id, state) VALUES (?, CAST(? AS jsonb)) " +
                    "ON CONFLICT (id) DO UPDATE SET state = EXCLUDED.state, updated_at = now()"
            ).use { ps ->
                ps.setString(1, userId)
                ps.setString(2, storeJson.encodeToString(UserState.serializer(), state))
                ps.executeUpdate()
            }
        }
    }

    // Удаление аккаунта стирает и события: после него о человеке не остаётся данных
    override fun delete(userId: String) {
        ds.connection.use { c ->
            c.autoCommit = false
            try {
                c.prepareStatement("DELETE FROM users WHERE id = ?").use { it.setString(1, userId); it.executeUpdate() }
                c.prepareStatement("DELETE FROM events WHERE user_id = ?").use { it.setString(1, userId); it.executeUpdate() }
                c.prepareStatement("DELETE FROM accounts WHERE user_id = ?").use { it.setString(1, userId); it.executeUpdate() }
                c.commit()
            } catch (e: Exception) {
                c.rollback()
                throw e
            } finally {
                c.autoCommit = true
            }
        }
    }

    override fun createAccount(account: Account): Boolean = ds.connection.use { c ->
        c.prepareStatement(
            "INSERT INTO accounts(user_id, email, password_hash, name) VALUES (?, ?, ?, ?) ON CONFLICT (email) DO NOTHING"
        ).use { ps ->
            ps.setString(1, account.userId)
            ps.setString(2, account.email)
            ps.setString(3, account.passwordHash)
            ps.setString(4, account.name)
            ps.executeUpdate() == 1
        }
    }

    override fun findAccount(email: String): Account? = ds.connection.use { c ->
        c.prepareStatement("SELECT user_id, email, password_hash, name FROM accounts WHERE email = ?").use { ps ->
            ps.setString(1, email)
            ps.executeQuery().use { rs ->
                if (rs.next()) Account(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4)) else null
            }
        }
    }

    override fun event(userId: String, type: EventType, day: LocalDate) {
        ds.connection.use { c ->
            c.prepareStatement("INSERT INTO events(user_id, type, day) VALUES (?, ?, ?)").use { ps ->
                ps.setString(1, userId)
                ps.setString(2, type.name)
                ps.setDate(3, Date.valueOf(day))
                ps.executeUpdate()
            }
        }
    }

    override fun stats(today: LocalDate): StatsDto = ds.connection.use { c ->
        fun count(sql: String, vararg days: Long): Int = c.prepareStatement(sql).use { ps ->
            days.forEachIndexed { i, d -> ps.setDate(i + 1, Date.valueOf(today.minusDays(d - 1))) }
            ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) }
        }
        val active = "SELECT count(DISTINCT user_id) FROM events WHERE day >= ?"
        val week = mutableMapOf<String, Int>()
        c.prepareStatement("SELECT type, count(*) FROM events WHERE day >= ? GROUP BY type").use { ps ->
            ps.setDate(1, Date.valueOf(today.minusDays(6)))
            ps.executeQuery().use { rs -> while (rs.next()) week[rs.getString(1)] = rs.getInt(2) }
        }
        StatsDto(
            users = count("SELECT count(*) FROM users"),
            active1d = count(active, 1), active7d = count(active, 7), active30d = count(active, 30),
            profiles7d = week[EventType.PROFILE.name] ?: 0,
            answers7d = (week[EventType.ANSWER_PASS.name] ?: 0) + (week[EventType.ANSWER_FAIL.name] ?: 0),
            passed7d = week[EventType.ANSWER_PASS.name] ?: 0,
            chats7d = week[EventType.CHAT.name] ?: 0,
        )
    }

    companion object {
        // Хостинги (Railway, Render, Supabase) часто дают адрес вида postgres://user:pass@host:5432/db,
        // а JDBC ждёт jdbc:postgresql://host:5432/db – поддерживаем оба.
        fun connect(url: String, user: String?, password: String?): PostgresUserStore {
            val cfg = HikariConfig()
            if (url.startsWith("postgres://") || url.startsWith("postgresql://")) {
                val uri = URI(url)
                val port = if (uri.port > 0) uri.port else 5432
                cfg.jdbcUrl = "jdbc:postgresql://${uri.host}:$port${uri.path}" + (uri.query?.let { "?$it" } ?: "")
                uri.userInfo?.split(":", limit = 2)?.let { parts ->
                    cfg.username = parts[0]
                    if (parts.size > 1) cfg.password = parts[1]
                }
            } else {
                cfg.jdbcUrl = url
            }
            user?.let { cfg.username = it }
            password?.let { cfg.password = it }
            cfg.maximumPoolSize = 5
            return PostgresUserStore(HikariDataSource(cfg))
        }
    }
}
