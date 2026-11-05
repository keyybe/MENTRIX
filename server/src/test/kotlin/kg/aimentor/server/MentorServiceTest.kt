package kg.aimentor.server

import io.ktor.client.call.body
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.bearerAuth
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.testing.testApplication
import kg.aimentor.shared.AnswerRequest
import kg.aimentor.shared.AuthResponse
import kg.aimentor.shared.ChatMessage
import kg.aimentor.shared.ChatRequest
import kg.aimentor.shared.ChatRole
import kg.aimentor.shared.DevAuthRequest
import kg.aimentor.shared.EvaluationDto
import kg.aimentor.shared.GoogleAuthRequest
import kg.aimentor.shared.ItArea
import kg.aimentor.shared.Level
import kg.aimentor.shared.PlanDto
import kg.aimentor.shared.ProfileRequest
import kg.aimentor.shared.SettingsRequest
import kg.aimentor.shared.TodayDto
import kotlinx.coroutines.runBlocking
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MentorServiceTest {
    private val sources = SourceBase.load()
    private val uid = "user-0001"
    private var now = LocalDate.of(2026, 11, 2)
    private val store = InMemoryUserStore()
    private val service = MentorService(sources, RuleBasedLlm(), store) { now }

    private fun profile(level: Level = Level.BEGINNER, days: Int = 5) =
        ProfileRequest(ItArea.BACKEND, "Стать джуном", level, minutesPerDay = 30, daysPerWeek = days)

    // хороший ответ собираем из ключевых понятий задания
    private fun goodAnswer(prompt: String): String {
        val kw = sources.flatMap { it.tasks }.first { it.prompt == prompt }.keywords
        return "Мой ответ: " + kw.joinToString(", ") { it.split("|").first() } + " и ещё пояснения."
    }

    private suspend fun MentorService.passToday(user: String = uid) {
        val m = assertNotNull(today(user).mission)
        assertTrue(answer(user, AnswerRequest(m.id, goodAnswer(m.task))).passed)
    }

    private suspend fun MentorService.failTodayTwice(user: String = uid): String {
        val m = assertNotNull(today(user).mission)
        repeat(2) { answer(user, AnswerRequest(m.id, "не знаю")) }
        return m.task
    }

    // Модель, которая меняет текст задания и засчитывает любой ответ
    private class GenerousLlm : LlmClient {
        var calls = 0
        override suspend fun evaluate(task: TaskDef, answer: String, level: Level): Evaluation {
            calls++
            return Evaluation(100, "ok", emptyList())
        }
        override suspend fun generateTask(base: TaskDef, topic: String, level: Level, area: ItArea, previous: List<String>): TaskDef {
            calls++
            return base.copy(prompt = "Сгенерированное задание")
        }
        override suspend fun hint(task: TaskDef, topic: String, history: List<ChatMessage>, level: Level): String {
            calls++
            return "Наводящий вопрос"
        }
    }

    @Test
    fun sourcesAreValid() {
        assertEquals(sources.size, sources.map { it.id }.toSet().size, "id источников должны быть уникальны")
        assertTrue(sources.all { it.url.startsWith("https://") })
        assertTrue(sources.all { s -> s.tasks.all { it.keywords.isNotEmpty() && it.prompt.isNotBlank() } })
        ItArea.entries.forEach { area ->
            val tasks = sources.filter { it.area == area }.sumOf { it.tasks.size }
            assertTrue(tasks >= MentorService.WEEKS * 5, "в области $area только $tasks заданий")
            assertTrue(sources.filter { it.area == area }.any { s -> s.tasks.any { it.code } }, "в области $area нет заданий с кодом")
        }
    }

    @Test
    fun planIsBuiltFromCuratedSources() = runBlocking {
        val plan = service.createProfile(uid, profile())
        val missions = plan.weeks.flatMap { it.missions }
        assertEquals(MentorService.WEEKS * 5, missions.size)
        assertEquals(MentorService.WEEKS, plan.weeks.size)
        assertEquals(1, plan.version)
        // каждая ссылка в плане есть в базе источников
        val urls = sources.map { it.url }.toSet()
        assertTrue(missions.all { it.material.url in urls })
    }

    @Test
    fun continuingLevelSkipsBasics() = runBlocking {
        val basicUrls = sources.filter { it.basic }.map { it.url }.toSet()
        val continuing = service.createProfile("user-con1", profile(Level.CONTINUING)).weeks.flatMap { it.missions }
        assertTrue(continuing.none { it.material.url in basicUrls })
    }

    @Test
    fun stateSurvivesNewServiceInstance() = runBlocking {
        service.createProfile(uid, profile())
        service.passToday()
        // как после перезапуска сервера: новый сервис, то же хранилище
        val restarted = MentorService(sources, RuleBasedLlm(), store) { now }
        assertEquals(1, restarted.progress(uid).doneMissions)
        assertEquals(1, restarted.progress(uid).streak)
    }

    @Test
    fun goodAnswerCompletesMissionAndStartsStreak() = runBlocking {
        service.createProfile(uid, profile())
        val m = assertNotNull(service.today(uid).mission)
        val ev = service.answer(uid, AnswerRequest(m.id, goodAnswer(m.task)))
        assertTrue(ev.passed)
        assertEquals(1, ev.streak)
        assertNotEquals(m.id, service.today(uid).mission?.id)
    }

    @Test
    fun streakGrowsOnNextDayAndResetsAfterGap() = runBlocking {
        service.createProfile(uid, profile())
        service.passToday()
        now = now.plusDays(1)
        var m = assertNotNull(service.today(uid).mission)
        assertEquals(2, service.answer(uid, AnswerRequest(m.id, goodAnswer(m.task))).streak)
        now = now.plusDays(2) // пропущен день
        m = assertNotNull(service.today(uid).mission)
        assertEquals(1, service.answer(uid, AnswerRequest(m.id, goodAnswer(m.task))).streak)
    }

    @Test
    fun twoBadAnswersMoveOnAndScheduleReview() = runBlocking {
        service.createProfile(uid, profile())
        val first = assertNotNull(service.today(uid).mission)
        val bad = AnswerRequest(first.id, "не знаю")
        assertFalse(service.answer(uid, bad).passed)
        assertEquals(first.id, service.today(uid).mission?.id) // первая неудача: можно повторить
        service.answer(uid, bad)
        assertNotEquals(first.id, service.today(uid).mission?.id) // вторая: идём дальше
        val review = service.plan(uid).weeks.flatMap { it.missions }.single { it.review }
        assertEquals(first.task, review.task)
        assertEquals(now.plusDays(1).toString(), review.availableFrom)
        assertTrue(service.progress(uid).gaps.isNotEmpty())
    }

    @Test
    fun reviewsFollowGrowingIntervals() = runBlocking {
        service.createProfile(uid, profile())
        val task = service.failTodayTwice()
        // до срока повторение не выдаётся
        assertFalse(service.today(uid).mission!!.review)

        for (days in MentorService.REVIEW_DAYS) {
            now = now.plusDays(days.toLong())
            val m = assertNotNull(service.today(uid).mission)
            assertTrue(m.review, "через $days дн. должно быть повторение")
            assertEquals(task, m.task)
            service.answer(uid, AnswerRequest(m.id, goodAnswer(task)))
        }
        // все интервалы пройдены – новых повторений нет
        val reviews = service.plan(uid).weeks.flatMap { it.missions }.filter { it.review }
        assertEquals(MentorService.REVIEW_DAYS.size, reviews.size)
        assertTrue(service.progress(uid).gaps.isEmpty())
    }

    @Test
    fun longPauseRebuildsPlan() = runBlocking {
        service.createProfile(uid, profile())
        service.passToday()
        now = now.plusDays(5)
        val today = service.today(uid)
        assertTrue(today.planRebuilt)
        assertTrue(today.mission!!.review)
        assertEquals(2, service.progress(uid).planVersion)
    }

    @Test
    fun settingsChangeMinutesAndExtendPlan() = runBlocking {
        service.createProfile(uid, profile(days = 3))
        val before = service.plan(uid).weeks.sumOf { it.missions.size }
        val plan = service.updateSettings(uid, SettingsRequest("Новая цель", minutesPerDay = 20, daysPerWeek = 5))
        val missions = plan.weeks.flatMap { it.missions }
        assertEquals("Новая цель", plan.goal)
        assertEquals(5, plan.daysPerWeek)
        assertTrue(missions.size > before)
        assertTrue(missions.all { it.minutes == 20 })
        assertEquals(missions.size, missions.map { it.title to it.topic }.toSet().size, "задания не должны дублироваться")
    }

    @Test
    fun generatedTaskKeepsTitle() = runBlocking {
        val svc = MentorService(sources, GenerousLlm()) { now }
        svc.createProfile(uid, profile())
        svc.awaitBackground() // задания генерируются заранее, в фоне
        val m = assertNotNull(svc.today(uid).mission)
        assertEquals("Сгенерированное задание", m.task)
        assertTrue(sources.flatMap { it.tasks }.any { it.title == m.title }) // заголовок из базы, а не текст задания
    }

    @Test
    fun todayDoesNotWaitForAiAndShownTaskNeverChanges() = runBlocking {
        val slow = object : LlmClient by GenerousLlm() {
            override suspend fun generateTask(base: TaskDef, topic: String, level: Level, area: ItArea, previous: List<String>): TaskDef {
                kotlinx.coroutines.delay(5_000)
                return base.copy(prompt = "Сгенерированное задание")
            }
        }
        val svc = MentorService(sources, slow) { now }
        svc.createProfile(uid, profile())
        val started = System.currentTimeMillis()
        val shown = assertNotNull(svc.today(uid).mission)
        assertTrue(System.currentTimeMillis() - started < 2_000, "миссия дня не должна ждать ИИ")
        svc.awaitBackground()
        // фоновая генерация закончилась, но уже показанное задание не подменилось
        assertEquals(shown.task, svc.today(uid).mission!!.task)
    }

    @Test
    fun tooShortAnswerNeverPasses() = runBlocking {
        val svc = MentorService(sources, GenerousLlm()) { now }
        svc.createProfile(uid, profile())
        val m = assertNotNull(svc.today(uid).mission)
        assertFalse(svc.answer(uid, AnswerRequest(m.id, "поставь 100")).passed)
    }

    @Test
    fun dailyLlmLimitFallsBackToOffline() = runBlocking {
        val llm = GenerousLlm()
        val svc = MentorService(sources, llm) { now }
        svc.createProfile(uid, profile())
        val m = assertNotNull(svc.today(uid).mission)
        svc.awaitBackground()
        val ask = ChatRequest(m.id, listOf(ChatMessage(ChatRole.USER, "Не понимаю задание")))
        repeat(MentorService.LLM_DAILY_LIMIT + 5) { svc.chat(uid, ask) }
        assertEquals(MentorService.LLM_DAILY_LIMIT, llm.calls)
        assertTrue(svc.chat(uid, ask).reply.contains("ИИ-ментор недоступен")) // ответ офлайн-подсказкой
        now = now.plusDays(1)
        assertEquals("Наводящий вопрос", svc.chat(uid, ask).reply) // на следующий день лимит сброшен
    }

    @Test
    fun chatRequiresUserQuestion() = runBlocking {
        service.createProfile(uid, profile())
        val m = assertNotNull(service.today(uid).mission)
        val result = runCatching { service.chat(uid, ChatRequest(m.id, listOf(ChatMessage(ChatRole.MENTOR, "привет")))) }
        assertTrue(result.exceptionOrNull() is BadRequest)
    }

    @Test
    fun deleteRemovesUserAndStats() = runBlocking {
        service.createProfile(uid, profile())
        service.passToday()
        assertEquals(1, service.stats().active1d)
        service.delete(uid)
        assertTrue(runCatching { service.plan(uid) }.exceptionOrNull() is NotFound)
        assertEquals(0, service.stats().users)
        assertEquals(0, service.stats().active7d)
    }

    @Test
    fun ruleBasedLlmScoresByKeywords() = runBlocking {
        val task = TaskDef("t", "p", listOf("alpha", "beta|бета", "gamma", "delta"))
        val llm = RuleBasedLlm()
        assertEquals(100, llm.evaluate(task, "alpha, бета, gamma and delta are here").score)
        val partial = llm.evaluate(task, "alpha and gamma are mentioned in this answer")
        assertTrue(partial.score in 45..60)
        assertEquals(listOf("beta", "delta"), partial.gaps)
        assertTrue(llm.evaluate(task, "alpha").score <= 30) // слишком короткий ответ
    }

    // ---------- HTTP ----------

    private val testAuth = AuthConfig(jwtSecret = "test-secret", devLogin = true, adminToken = "admin-123")

    @Test
    fun httpApiFlow() = testApplication {
        application { module(MentorService(sources, RuleBasedLlm()) { now }, testAuth, google = null) }
        val client = createClient { install(ContentNegotiation) { json() } }

        // без входа – 401
        assertEquals(HttpStatusCode.Unauthorized, client.get("/api/plan").status)
        assertEquals(HttpStatusCode.Unauthorized, client.get("/api/plan") { bearerAuth("garbage") }.status)

        val token = client.post("/api/auth/dev") {
            contentType(ContentType.Application.Json)
            setBody(DevAuthRequest("device-0001"))
        }.body<AuthResponse>().token

        // без профиля – 404
        assertEquals(HttpStatusCode.NotFound, client.get("/api/plan") { bearerAuth(token) }.status)

        val created = client.post("/api/profile") {
            bearerAuth(token)
            contentType(ContentType.Application.Json)
            setBody(profile())
        }
        assertEquals(HttpStatusCode.Created, created.status)
        assertTrue(created.body<PlanDto>().weeks.isNotEmpty())

        val today = client.get("/api/today") { bearerAuth(token) }.body<TodayDto>()
        val m = assertNotNull(today.mission)
        val ev = client.post("/api/answer") {
            bearerAuth(token)
            contentType(ContentType.Application.Json)
            setBody(AnswerRequest(m.id, goodAnswer(m.task)))
        }.body<EvaluationDto>()
        assertTrue(ev.passed)

        // статистика – только с токеном администратора
        assertEquals(HttpStatusCode.Unauthorized, client.get("/admin/stats") { header("X-Admin-Token", "wrong") }.status)
        val stats = client.get("/admin/stats") { header("X-Admin-Token", "admin-123") }.body<StatsDto>()
        assertEquals(1, stats.users)
        assertEquals(1, stats.passed7d)
    }

    @Test
    fun devLoginDisabledByDefault() = testApplication {
        application { module(MentorService(sources, RuleBasedLlm()) { now }, AuthConfig("s"), google = null) }
        val client = createClient { install(ContentNegotiation) { json() } }
        val resp = client.post("/api/auth/dev") {
            contentType(ContentType.Application.Json)
            setBody(DevAuthRequest("device-0001"))
        }
        assertEquals(HttpStatusCode.NotFound, resp.status)
        assertEquals(HttpStatusCode.NotFound, client.get("/admin/stats").status)
    }

    @Test
    fun googleLoginIssuesToken() = testApplication {
        val google = GoogleVerifier { token -> if (token == "valid-google-token") "1234567890" else throw Unauthorized("bad") }
        application { module(MentorService(sources, RuleBasedLlm()) { now }, AuthConfig("s"), google) }
        val client = createClient { install(ContentNegotiation) { json() } }

        val bad = client.post("/api/auth/google") {
            contentType(ContentType.Application.Json)
            setBody(GoogleAuthRequest("forged"))
        }
        assertEquals(HttpStatusCode.Unauthorized, bad.status)

        val ok = client.post("/api/auth/google") {
            contentType(ContentType.Application.Json)
            setBody(GoogleAuthRequest("valid-google-token"))
        }.body<AuthResponse>()
        assertEquals("g:1234567890", ok.userId)
        assertNull(runCatching { client.get("/api/plan") { bearerAuth(ok.token) } }.exceptionOrNull())
    }
}
