package kg.aimentor.server

import kg.aimentor.shared.AnswerRequest
import kg.aimentor.shared.ChatReply
import kg.aimentor.shared.ChatRequest
import kg.aimentor.shared.ChatRole
import kg.aimentor.shared.EvaluationDto
import kg.aimentor.shared.Level
import kg.aimentor.shared.MissionDto
import kg.aimentor.shared.MissionStatus
import kg.aimentor.shared.PlanDto
import kg.aimentor.shared.ProfileRequest
import kg.aimentor.shared.ProgressDto
import kg.aimentor.shared.SettingsRequest
import kg.aimentor.shared.SourceRef
import kg.aimentor.shared.TodayDto
import kg.aimentor.shared.WeekDto
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class BadRequest(message: String) : RuntimeException(message)
class NotFound(message: String) : RuntimeException(message)

// Внутреннее представление миссии (в DTO превращается через toDto)
@Serializable
class Mission(
    val id: String,
    val sourceId: String,
    var task: TaskDef,
    var week: Int = 0,
    var day: Int = 0,
    var minutes: Int,
    var status: MissionStatus = MissionStatus.TODO,
    val review: Boolean = false,
    var attempts: Int = 0,
    var taskGenerated: Boolean = false,
    var pregenerating: Boolean = false, // задание сейчас генерируется в фоне
    // повторение откроется не раньше этой даты (интервальное повторение)
    @Serializable(LocalDateSerializer::class) val notBefore: LocalDate? = null,
    val reviewStage: Int = 0, // 0 – обычная миссия, 1..n – номер повторения
)

@Serializable
class UserState(
    var profile: ProfileRequest,
    val missions: MutableList<Mission>,
    @Serializable(LocalDateSerializer::class) var lastActive: LocalDate,
    var version: Int = 1,
    var streak: Int = 0,
    @Serializable(LocalDateSerializer::class) var lastDone: LocalDate? = null,
    val gaps: MutableSet<String> = linkedSetOf(),
    // дневной лимит запросов к внешней модели
    @Serializable(LocalDateSerializer::class) var llmDay: LocalDate? = null,
    var llmCalls: Int = 0,
)

// Планировщик: работает по правилам и не зависит от ИИ.
object Planner {
    private fun pool(sources: List<Source>, p: ProfileRequest) =
        sources.filter { it.area == p.area && !(p.level == Level.CONTINUING && it.basic) }
            .flatMap { s -> s.tasks.map { t -> s to t } }

    fun build(sources: List<Source>, p: ProfileRequest): MutableList<Mission> =
        pool(sources, p)
            .take(MentorService.WEEKS * p.daysPerWeek)
            .map { (s, t) -> Mission(UUID.randomUUID().toString(), s.id, t, minutes = p.minutesPerDay) }
            .toMutableList()

    // Больше занятий в неделю – добираем в план ещё не использованные задания из базы
    fun extend(sources: List<Source>, st: UserState) {
        val target = MentorService.WEEKS * st.profile.daysPerWeek
        val used = st.missions.filter { !it.review }.map { it.sourceId to it.task.title }.toSet()
        val lessons = st.missions.count { !it.review }
        pool(sources, st.profile)
            .filter { (s, t) -> (s.id to t.title) !in used }
            .take((target - lessons).coerceAtLeast(0))
            .forEach { (s, t) -> st.missions.add(Mission(UUID.randomUUID().toString(), s.id, t, minutes = st.profile.minutesPerDay)) }
    }

    fun reflow(missions: List<Mission>, daysPerWeek: Int) {
        missions.forEachIndexed { i, m ->
            m.week = i / daysPerWeek + 1
            m.day = i % daysPerWeek + 1
        }
    }
}

class MentorService(
    sources: List<Source>,
    private val llm: LlmClient,
    private val store: UserStore = InMemoryUserStore(),
    private val offline: LlmClient = RuleBasedLlm(),
    // фоновая генерация следующих заданий: человек не ждёт ИИ, когда открывает миссию
    private val background: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
    private val today: () -> LocalDate = { LocalDate.now() },
) {
    companion object {
        const val WEEKS = 8        // длина плана
        const val PASS = 60        // порог зачёта, %
        const val PAUSE_DAYS = 3   // после стольких дней паузы план пересобирается
        const val MAX_ATTEMPTS = 2 // после двух неудач идём дальше, тема вернётся повторением
        const val MIN_MINUTES = 15 // диапазон времени в день (такой же у ползунка в приложении)
        const val MAX_MINUTES = 40
        const val MAX_ANSWER = 4000 // символов в ответе
        const val MIN_WORDS = 3    // короче – не засчитываем, что бы ни сказала модель
        const val LLM_DAILY_LIMIT = 40 // запросов к внешней модели на человека в день, дальше – офлайн-режим
        const val CHAT_HISTORY = 12    // сколько последних сообщений чата отправляем модели
        const val MAX_CHAT_MESSAGE = 2000
        const val PREGENERATE = 2      // сколько следующих заданий держать готовыми
        val REVIEW_DAYS = listOf(1, 3, 7) // интервалы повторения ошибочной темы, дней
    }

    private val sources = sources.associateBy { it.id }
    private val allSources = sources
    private val locks = ConcurrentHashMap<String, Mutex>()
    private val pending: MutableSet<Job> = ConcurrentHashMap.newKeySet()

    // Для тестов: дождаться фоновой генерации
    internal suspend fun awaitBackground() {
        while (pending.isNotEmpty()) pending.toList().joinAll()
    }

    // Заранее генерирует задания для следующих уроков. Запрос к модели идёт без блокировки пользователя,
    // а результат сохраняется, только если задание ещё не показывали человеку.
    private fun pregenerate(userId: String) {
        val job = background.launch {
            repeat(PREGENERATE) {
                val target = runCatching {
                    withUser(userId) { st ->
                        val m = st.missions.firstOrNull { it.status == MissionStatus.TODO && !it.taskGenerated && !it.review }
                            ?: return@withUser null
                        val previous = st.missions
                            .filter { it.sourceId == m.sourceId && it.taskGenerated && it.id != m.id }
                            .map { it.task.prompt }
                        // резервируем миссию, чтобы параллельная генерация её не взяла
                        m.taskGenerated = true
                        m.pregenerating = true
                        PregenTarget(m.id, m.task, source(m).title, st.profile, llmFor(st), previous)
                    }
                }.getOrNull() ?: return@launch

                val generated = runCatching {
                    target.client.generateTask(target.base, target.topic, target.profile.level, target.profile.area, target.previous)
                }.getOrDefault(target.base)

                runCatching {
                    withUser(userId) { st ->
                        val m = st.missions.firstOrNull { it.id == target.missionId } ?: return@withUser
                        // человек уже увидел базовое задание – не подменяем его
                        if (m.pregenerating) m.task = generated
                        m.pregenerating = false
                    }
                }
            }
        }
        pending += job
        job.invokeOnCompletion { pending -= job }
    }

    private class PregenTarget(
        val missionId: String,
        val base: TaskDef,
        val topic: String,
        val profile: ProfileRequest,
        val client: LlmClient,
        val previous: List<String>,
    )

    private suspend fun <T> io(block: () -> T): T = withContext(Dispatchers.IO) { block() }

    // Все операции одного пользователя выполняются по очереди: прочитали состояние, изменили, сохранили.
    // Блокировка в памяти процесса – сервер рассчитан на один экземпляр.
    private suspend fun <T> withUser(userId: String, save: Boolean = true, block: suspend (UserState) -> T): T =
        locks.computeIfAbsent(userId) { Mutex() }.withLock {
            val st = io { store.load(userId) } ?: throw NotFound("Профиль не найден")
            val result = block(st)
            if (save) io { store.save(userId, st) }
            result
        }

    private fun source(m: Mission): Source = sources[m.sourceId] ?: error("Нет источника ${m.sourceId}")

    private fun Mission.toDto(): MissionDto {
        val s = source(this)
        return MissionDto(
            id = id, week = week, day = day, title = task.title, topic = s.title,
            material = SourceRef(s.title, s.url), task = task.prompt,
            minutes = minutes, status = status, review = review, code = task.code,
            availableFrom = notBefore?.toString(),
        )
    }

    // Внешняя модель, пока не исчерпан дневной лимит, затем – офлайн-проверка
    private fun llmFor(st: UserState): LlmClient {
        val now = today()
        if (st.llmDay != now) {
            st.llmDay = now
            st.llmCalls = 0
        }
        if (st.llmCalls >= LLM_DAILY_LIMIT) return offline
        st.llmCalls++
        return llm
    }

    private suspend fun event(userId: String, type: EventType) = io { store.event(userId, type, today()) }

    suspend fun createProfile(userId: String, req: ProfileRequest): PlanDto {
        if (req.goal.isBlank()) throw BadRequest("Цель не указана")
        val profile = req.copy(
            goal = req.goal.trim().take(200),
            daysPerWeek = req.daysPerWeek.coerceIn(1, 7),
            minutesPerDay = req.minutesPerDay.coerceIn(MIN_MINUTES, MAX_MINUTES),
        )
        val missions = Planner.build(allSources, profile)
        if (missions.isEmpty()) throw BadRequest("Для выбранной области пока нет материалов")
        Planner.reflow(missions, profile.daysPerWeek)
        val st = UserState(profile, missions, lastActive = today())
        locks.computeIfAbsent(userId) { Mutex() }.withLock { io { store.save(userId, st) } }
        event(userId, EventType.PROFILE)
        pregenerate(userId)
        return planDto(st)
    }

    suspend fun plan(userId: String): PlanDto = withUser(userId, save = false) { planDto(it) }

    suspend fun updateSettings(userId: String, req: SettingsRequest): PlanDto = withUser(userId) { st ->
        if (req.goal.isBlank()) throw BadRequest("Цель не указана")
        st.profile = st.profile.copy(
            goal = req.goal.trim().take(200),
            minutesPerDay = req.minutesPerDay.coerceIn(MIN_MINUTES, MAX_MINUTES),
            daysPerWeek = req.daysPerWeek.coerceIn(1, 7),
        )
        st.missions.filter { it.status == MissionStatus.TODO }.forEach { it.minutes = st.profile.minutesPerDay }
        Planner.extend(allSources, st)
        Planner.reflow(st.missions, st.profile.daysPerWeek)
        planDto(st)
    }

    suspend fun today(userId: String): TodayDto {
        val dto = withUser(userId) { st ->
            val now = today()
            val paused = ChronoUnit.DAYS.between(st.lastActive, now)
            val rebuilt = paused >= PAUSE_DAYS && rebuildAfterPause(st, now)
            // повторение, у которого наступил срок, идёт раньше нового урока
            val available = st.missions.filter { it.status == MissionStatus.TODO && (it.notBefore == null || !it.notBefore.isAfter(now)) }
            val mission = available.firstOrNull { it.review } ?: available.firstOrNull()

            if (mission == null) {
                val next = st.missions.filter { it.status == MissionStatus.TODO }.mapNotNull { it.notBefore }.minOrNull()
                val message = if (next != null) "На сегодня всё! Следующее повторение откроется $next." else "План пройден! Скоро появятся новые темы."
                return@withUser TodayDto(null, message, rebuilt)
            }

            // Миссию отдаём сразу, без ожидания ИИ: если фоновая генерация не успела – берём базовое задание.
            // Показанное задание больше не меняется, иначе ответ проверялся бы по другому вопросу.
            mission.taskGenerated = true
            mission.pregenerating = false

            val message = when {
                rebuilt -> "План пересобран с учётом перерыва."
                mission.review -> "Повторение: закрепим тему, в которой были ошибки."
                else -> "Миссия на сегодня готова."
            }
            TodayDto(mission.toDto(), message, rebuilt)
        }
        event(userId, EventType.OPEN)
        pregenerate(userId)
        return dto
    }

    suspend fun answer(userId: String, req: AnswerRequest): EvaluationDto {
        if (req.answer.isBlank()) throw BadRequest("Пустой ответ")
        if (req.answer.length > MAX_ANSWER) throw BadRequest("Ответ слишком длинный (до $MAX_ANSWER символов)")
        var passed = false
        val result = withUser(userId) { st ->
            val m = st.missions.firstOrNull { it.id == req.missionId } ?: throw NotFound("Миссия не найдена")
            if (m.status == MissionStatus.DONE) throw BadRequest("Миссия уже выполнена")

            val ev = llmFor(st).evaluate(m.task, req.answer, st.profile.level)
            val words = req.answer.trim().split("\\s+".toRegex()).size
            val score = if (words < MIN_WORDS) minOf(ev.score, PASS - 1) else ev.score

            val now = today()
            st.lastActive = now
            m.attempts++
            passed = score >= PASS
            var feedback = ev.feedback
            val topic = source(m).title
            if (passed) {
                m.status = MissionStatus.DONE
                st.gaps.remove(topic)
                bumpStreak(st, now)
                // успешное повторение – следующее через больший интервал, пока интервалы не кончатся
                if (m.review && m.reviewStage in 1 until REVIEW_DAYS.size) {
                    scheduleReview(st, m, m.reviewStage + 1, now)
                }
            } else {
                st.gaps.add(topic)
                if (m.attempts >= MAX_ATTEMPTS) {
                    m.status = MissionStatus.DONE
                    scheduleReview(st, m, stage = 1, now)
                    feedback += " Идём дальше, к этой теме вернёмся в повторении через ${REVIEW_DAYS[0]} дн."
                }
            }
            EvaluationDto(score, passed, feedback, ev.gaps, st.streak)
        }
        event(userId, if (passed) EventType.ANSWER_PASS else EventType.ANSWER_FAIL)
        pregenerate(userId)
        return result
    }

    // Чат «Застрял»: наводящие подсказки по текущему заданию, без готового ответа
    suspend fun chat(userId: String, req: ChatRequest): ChatReply {
        val history = req.messages.takeLast(CHAT_HISTORY)
        if (history.isEmpty() || history.last().role != ChatRole.USER) throw BadRequest("Нет вопроса")
        if (history.any { it.text.isBlank() || it.text.length > MAX_CHAT_MESSAGE }) {
            throw BadRequest("Сообщение пустое или длиннее $MAX_CHAT_MESSAGE символов")
        }
        val reply = withUser(userId) { st ->
            val m = st.missions.firstOrNull { it.id == req.missionId } ?: throw NotFound("Миссия не найдена")
            llmFor(st).hint(m.task, source(m).title, history, st.profile.level)
        }
        event(userId, EventType.CHAT)
        return ChatReply(reply)
    }

    suspend fun progress(userId: String): ProgressDto = withUser(userId, save = false) { st ->
        ProgressDto(
            streak = st.streak,
            doneMissions = st.missions.count { it.status == MissionStatus.DONE },
            totalMissions = st.missions.size,
            planVersion = st.version,
            gaps = st.gaps.toList(),
        )
    }

    suspend fun delete(userId: String) {
        locks.computeIfAbsent(userId) { Mutex() }.withLock { io { store.delete(userId) } }
        locks.remove(userId)
    }

    suspend fun stats(): StatsDto = io { store.stats(today()) }

    private fun bumpStreak(st: UserState, now: LocalDate) {
        val last = st.lastDone
        st.streak = when {
            last == now -> st.streak
            last == now.minusDays(1) -> st.streak + 1
            else -> 1
        }
        st.lastDone = now
    }

    // Повторение ставим в план через REVIEW_DAYS[stage-1] дней. В списке оно стоит примерно там же,
    // где окажутся занятия этого дня, а notBefore не даёт открыть его раньше срока.
    private fun scheduleReview(st: UserState, m: Mission, stage: Int, now: LocalDate) {
        val days = REVIEW_DAYS[stage - 1]
        val firstTodo = st.missions.indexOfFirst { it.status == MissionStatus.TODO }.let { if (it < 0) st.missions.size else it }
        val pos = minOf(firstTodo + days, st.missions.size)
        st.missions.add(pos, reviewOf(m, stage, now.plusDays(days.toLong())))
        Planner.reflow(st.missions, st.profile.daysPerWeek)
    }

    private fun reviewOf(m: Mission, stage: Int, notBefore: LocalDate?) = Mission(
        id = UUID.randomUUID().toString(),
        sourceId = m.sourceId,
        task = m.task.copy(title = m.task.title.removePrefix("Повторение: ")),
        minutes = m.minutes, review = true,
        taskGenerated = true,
        notBefore = notBefore,
        reviewStage = stage,
    )

    private fun rebuildAfterPause(st: UserState, now: LocalDate): Boolean {
        st.lastActive = now
        st.version++
        val lastDone = st.missions.lastOrNull { it.status == MissionStatus.DONE && !it.review }
        val firstTodo = st.missions.indexOfFirst { it.status == MissionStatus.TODO }
        // если повторение уже ждёт по интервалу, второе не добавляем
        val reviewDue = st.missions.any { it.review && it.status == MissionStatus.TODO && (it.notBefore == null || !it.notBefore.isAfter(now)) }
        if (lastDone != null && firstTodo >= 0 && !reviewDue) {
            // одно повторение после перерыва, без цепочки интервалов
            st.missions.add(firstTodo, reviewOf(lastDone, REVIEW_DAYS.size, notBefore = null))
        }
        Planner.reflow(st.missions, st.profile.daysPerWeek)
        return true
    }

    private fun planDto(st: UserState): PlanDto {
        val weeks = st.missions.groupBy { it.week }.map { (w, ms) ->
            WeekDto(w, "Неделя $w: ${source(ms.first()).title}", ms.map { it.toDto() })
        }.sortedBy { it.index }
        val p = st.profile
        return PlanDto(st.version, p.area, p.goal, weeks, p.level, p.minutesPerDay, p.daysPerWeek)
    }
}
