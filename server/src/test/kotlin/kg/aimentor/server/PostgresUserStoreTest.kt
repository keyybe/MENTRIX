package kg.aimentor.server

import kg.aimentor.shared.AnswerRequest
import kg.aimentor.shared.ItArea
import kg.aimentor.shared.Level
import kg.aimentor.shared.ProfileRequest
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeEach
import java.time.LocalDate
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Проверка на настоящей PostgreSQL. Запускается, только если задан TEST_DATABASE_URL, например:
//   TEST_DATABASE_URL=postgresql://mentor:пароль@localhost:5432/mentor_test ./gradlew :server:test
// Иначе тест пропускается – сборки без базы не ломаются.
class PostgresUserStoreTest {
    private val url = System.getenv("TEST_DATABASE_URL")
    private lateinit var store: PostgresUserStore
    private val sources = SourceBase.load()
    private var now = LocalDate.of(2026, 11, 2)
    private val created = mutableListOf<String>()

    private fun newUser() = "test:" + UUID.randomUUID().toString().also { created += "test:$it" }

    @BeforeEach
    fun connect() {
        assumeTrue(!url.isNullOrBlank(), "TEST_DATABASE_URL не задан – пропускаем тест с PostgreSQL")
        store = PostgresUserStore.connect(url!!, null, null)
    }

    @AfterEach
    fun cleanUp() {
        if (::store.isInitialized) {
            created.forEach { store.delete(it) }
            store.close()
        }
    }

    @Test
    fun stateRoundTripsThroughJsonb() = runBlocking {
        val uid = newUser()
        val service = MentorService(sources, RuleBasedLlm(), store) { now }
        service.createProfile(uid, ProfileRequest(ItArea.MOBILE, "Работа", Level.BEGINNER, 20, 5))
        val m = assertNotNull(service.today(uid).mission)
        val task = sources.flatMap { it.tasks }.first { it.prompt == m.task }
        val good = "Ответ: " + task.keywords.joinToString(", ") { it.split("|").first() } + " и пояснения"
        assertTrue(service.answer(uid, AnswerRequest(m.id, good)).passed)
        service.awaitBackground()

        val saved = assertNotNull(store.load(uid))
        assertEquals(1, saved.streak)
        assertEquals(now, saved.lastDone)
        assertEquals(listOf(now.toString()), saved.doneDates)
        assertEquals(ItArea.MOBILE, saved.profile.area)
        assertEquals(m.id, saved.missions.first().id)
    }

    @Test
    fun progressSurvivesServerRestart() = runBlocking {
        val uid = newUser()
        MentorService(sources, RuleBasedLlm(), store) { now }.run {
            createProfile(uid, ProfileRequest(ItArea.BACKEND, "Работа", Level.BEGINNER, 20, 5))
            val m = assertNotNull(today(uid).mission)
            repeat(2) { answer(uid, AnswerRequest(m.id, "не знаю")) } // тема уйдёт в повторение
            awaitBackground()
        }
        // «перезапуск»: новый сервис и новое подключение к той же базе
        store.close()
        store = PostgresUserStore.connect(url!!, null, null)
        val restarted = MentorService(sources, RuleBasedLlm(), store) { now }
        val progress = restarted.progress(uid)
        assertEquals(1, progress.doneMissions)
        assertTrue(progress.gaps.isNotEmpty())
        assertTrue(restarted.plan(uid).weeks.flatMap { it.missions }.any { it.review })
    }

    @Test
    fun accountsAreUniqueByEmailAndDeletedWithUser() {
        val uid = newUser()
        val email = "$uid@test.local".lowercase()
        assertTrue(store.createAccount(Account(uid, email, Passwords.hash("password1"), "Аня")))
        assertTrue(!store.createAccount(Account(newUser(), email, "x", "Другая")), "email должен быть уникальным")
        val found = assertNotNull(store.findAccount(email))
        assertEquals(uid, found.userId)
        assertTrue(Passwords.verify("password1", found.passwordHash))
        store.delete(uid)
        assertNull(store.findAccount(email))
    }

    @Test
    fun eventsCountedAndDeletedWithAccount() {
        val uid = newUser()
        val before = store.stats(now)
        store.save(uid, UserState(ProfileRequest(ItArea.FRONTEND, "Цель", Level.BEGINNER, 20, 5), mutableListOf(), now))
        store.event(uid, EventType.PROFILE, now)
        store.event(uid, EventType.ANSWER_PASS, now)
        val after = store.stats(now)
        assertEquals(before.users + 1, after.users)
        assertEquals(before.passed7d + 1, after.passed7d)
        assertEquals(before.profiles7d + 1, after.profiles7d)

        store.delete(uid)
        assertNull(store.load(uid))
        val cleaned = store.stats(now)
        assertEquals(before.users, cleaned.users)
        assertEquals(before.passed7d, cleaned.passed7d)
    }
}
