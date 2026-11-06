package kg.aimentor.app

import kg.aimentor.shared.AnswerRequest
import kg.aimentor.shared.AuthResponse
import kg.aimentor.shared.ChatReply
import kg.aimentor.shared.ChatRequest
import kg.aimentor.shared.EvaluationDto
import kg.aimentor.shared.ItArea
import kg.aimentor.shared.LoginRequest
import kg.aimentor.shared.MissionDto
import kg.aimentor.shared.MissionStatus
import kg.aimentor.shared.PlanDto
import kg.aimentor.shared.ProfileRequest
import kg.aimentor.shared.ProgressDto
import kg.aimentor.shared.RegisterRequest
import kg.aimentor.shared.SettingsRequest
import kg.aimentor.shared.SourceRef
import kg.aimentor.shared.TodayDto
import kg.aimentor.shared.WeekDto
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.IOException
import java.time.LocalDate

@OptIn(ExperimentalCoroutinesApi::class)
class MentorViewModelTest {

    private val mission = MissionDto(
        id = "m1", week = 1, day = 1, title = "Теги", topic = "HTML",
        material = SourceRef("HTML", "https://example.com"), task = "Объясни теги",
        minutes = 30, status = MissionStatus.TODO,
    )
    private val plan = PlanDto(1, ItArea.FRONTEND, "Работа", listOf(WeekDto(1, "Неделя 1", listOf(mission))))
    private val today = TodayDto(mission, "Миссия готова")
    private val progress = ProgressDto(streak = 0, doneMissions = 0, totalMissions = 1, planVersion = 1, gaps = emptyList())

    private class FakeSession(override var token: String? = null) : Session {
        override val deviceId = "device-0001"
        override var reminderMinutes: Int? = null
        override var lastPassedDay: String? = null
        override var name: String? = null
        override var avatarPath: String? = null
    }

    private class FakeCache : Cache {
        override var plan: PlanDto? = null
        override var today: TodayDto? = null
        override var progress: ProgressDto? = null
        override fun clear() {
            plan = null; today = null; progress = null
        }
    }

    private class FakeReminders : ReminderScheduler {
        var time: Pair<Int, Int>? = null
        override fun schedule(hour: Int, minute: Int) { time = hour to minute }
        override fun cancel() { time = null }
    }

    // Сервер, поведение которого задаёт тест
    private inner class FakeBackend : MentorBackend {
        var hasProfile = true
        var failWith: Exception? = null
        var evaluation = EvaluationDto(80, true, "ok", emptyList(), 1)
        var calls = 0

        private fun check() {
            calls++
            failWith?.let { throw it }
        }

        override suspend fun register(req: RegisterRequest) = AuthResponse("reg-token", "e:1", req.name).also { check() }
        override suspend fun login(req: LoginRequest) = AuthResponse("login-token", "e:1", "Аня").also { check() }
        override suspend fun loginGoogle(idToken: String) = AuthResponse("google-token", "g:1").also { check() }
        override suspend fun loginDev(deviceId: String) = AuthResponse("dev-token", "dev:$deviceId").also { check() }
        override suspend fun plan(): PlanDto? { check(); return if (hasProfile) plan else null }
        override suspend fun createProfile(req: ProfileRequest): PlanDto { check(); hasProfile = true; return plan }
        override suspend fun updateSettings(req: SettingsRequest): PlanDto { check(); return plan.copy(goal = req.goal) }
        override suspend fun today(): TodayDto { check(); return today }
        override suspend fun progress(): ProgressDto { check(); return progress }
        override suspend fun answer(req: AnswerRequest): EvaluationDto { check(); return evaluation }
        override suspend fun chat(req: ChatRequest): ChatReply { check(); return ChatReply("Подумай о тегах") }
        override suspend fun deleteAccount() = check()
    }

    private val backend = FakeBackend()
    private val cache = FakeCache()
    private val reminders = FakeReminders()
    private val day = LocalDate.of(2026, 11, 6)

    private fun vm(session: Session) = MentorViewModel(backend, session, cache, reminders) { day }

    @Before
    fun setUp() = Dispatchers.setMain(UnconfinedTestDispatcher())

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun withoutTokenShowsLoginAndDoesNotCallServer() {
        val state = vm(FakeSession()).state.value
        assertFalse(state.signedIn)
        assertFalse(state.loading)
        assertEquals(0, backend.calls)
    }

    @Test
    fun registerSavesTokenAndNameAndOpensOnboarding() {
        backend.hasProfile = false
        val session = FakeSession()
        val vm = vm(session)
        vm.register("Аня", "anya@mail.ru", "password1")
        assertEquals("reg-token", session.token)
        assertEquals("Аня", session.name)
        val state = vm.state.value
        assertTrue(state.signedIn)
        assertFalse(state.hasProfile)
    }

    @Test
    fun emailLoginSavesTokenAndLoadsData() {
        val session = FakeSession()
        val vm = vm(session)
        vm.login("anya@mail.ru", "password1")
        assertEquals("login-token", session.token)
        assertEquals("Аня", session.name)
        val state = vm.state.value
        assertTrue(state.signedIn)
        assertTrue(state.hasProfile)
    }

    @Test
    fun devLoginSavesTokenAndOpensOnboarding() {
        backend.hasProfile = false
        val session = FakeSession()
        val vm = vm(session)
        vm.loginDev()
        assertEquals("dev-token", session.token)
        val state = vm.state.value
        assertTrue(state.signedIn)
        assertFalse(state.hasProfile)
    }

    @Test
    fun loadsPlanAndCachesIt() {
        val state = vm(FakeSession("t")).state.value
        assertTrue(state.hasProfile)
        assertEquals(mission.id, state.today?.mission?.id)
        assertEquals(plan, cache.plan)
    }

    @Test
    fun withoutNetworkShowsCachedDataOffline() {
        cache.plan = plan
        cache.today = today
        backend.failWith = IOException("нет сети")
        val state = vm(FakeSession("t")).state.value
        assertTrue(state.offline)
        assertTrue(state.hasProfile)
        assertEquals(plan, state.plan)
        assertNull(state.error)
    }

    @Test
    fun expiredSessionSignsOut() {
        val session = FakeSession("old")
        backend.failWith = SessionExpired()
        val state = vm(session).state.value
        assertFalse(state.signedIn)
        assertNull(session.token)
        assertTrue(state.notice!!.contains("Сессия"))
    }

    @Test
    fun passedAnswerMarksDaySoReminderIsSkipped() {
        val session = FakeSession("t")
        val vm = vm(session)
        vm.submitAnswer("ответ из нескольких слов")
        assertEquals(day.toString(), session.lastPassedDay)
        assertTrue(vm.state.value.evaluation!!.passed)
    }

    @Test
    fun serverMessageIsShownAsIs() {
        val vm = vm(FakeSession("t"))
        backend.failWith = ServerMessage("Миссия уже выполнена")
        vm.submitAnswer("ответ")
        assertEquals("Миссия уже выполнена", vm.state.value.error)
        assertFalse(vm.state.value.submitting)
    }

    @Test
    fun reminderIsScheduledAndCancelled() {
        val session = FakeSession("t")
        val vm = vm(session)
        vm.setReminder(20 * 60 + 30)
        assertEquals(20 to 30, reminders.time)
        assertEquals(20 * 60 + 30, session.reminderMinutes)
        assertEquals(20 * 60 + 30, vm.state.value.reminderMinutes)
        vm.setReminder(null)
        assertNull(reminders.time)
    }

    @Test
    fun nameIsEditedAndKeptOnGoogleLogin() {
        val session = FakeSession()
        val vm = vm(session)
        vm.updateName("  Аня  ")
        assertEquals("Аня", vm.state.value.userName)
        vm.loginWithGoogle("id-token", "Anna Google")
        assertEquals("Аня", session.name) // введённое вручную имя не затирается
        vm.updateName("   ")
        assertNull(vm.state.value.userName)
    }

    @Test
    fun signOutForgetsNameAndAvatar() {
        val session = FakeSession("t").apply { name = "Аня"; avatarPath = "/no/such/file.jpg" }
        val vm = vm(session)
        assertEquals("/no/such/file.jpg", vm.state.value.avatarPath)
        vm.signOut()
        assertNull(session.name)
        assertNull(session.avatarPath)
        assertNull(vm.state.value.avatarPath)
    }

    @Test
    fun deleteAccountClearsEverything() {
        val vm = vm(FakeSession("t"))
        vm.setReminder(9 * 60)
        vm.deleteAccount()
        assertFalse(vm.state.value.hasProfile)
        assertNull(cache.plan)
        assertNull(reminders.time)
    }

    @Test
    fun chatFailureReturnsQuestionToInput() {
        val chat = ChatViewModel(backend)
        chat.open(mission.id)
        backend.failWith = IOException("нет сети")
        chat.send("Что такое тег?")
        val state = chat.state.value
        assertTrue(state.messages.isEmpty())
        assertEquals("Что такое тег?", state.draft)

        backend.failWith = null
        chat.send("Что такое тег?")
        assertEquals(2, chat.state.value.messages.size)
    }
}
