package kg.aimentor.app

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import kg.aimentor.shared.AnswerRequest
import kg.aimentor.shared.ChatMessage
import kg.aimentor.shared.ChatRequest
import kg.aimentor.shared.ChatRole
import kg.aimentor.shared.EvaluationDto
import kg.aimentor.shared.PlanDto
import kg.aimentor.shared.ProfileRequest
import kg.aimentor.shared.ProgressDto
import kg.aimentor.shared.SettingsRequest
import kg.aimentor.shared.TodayDto
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate

data class UiState(
    val signedIn: Boolean = false,
    val loading: Boolean = true,
    val submitting: Boolean = false,
    val hasProfile: Boolean = false,
    val changingArea: Boolean = false, // человек выбирает новое направление – показываем онбординг с кнопкой «Отмена»
    val offline: Boolean = false,      // показаны сохранённые данные, сервер недоступен
    val plan: PlanDto? = null,
    val today: TodayDto? = null,
    val progress: ProgressDto? = null,
    val evaluation: EvaluationDto? = null,
    val reminderHour: Int? = null,
    val error: String? = null,
    val notice: String? = null, // короткое сообщение для Snackbar
)

class MentorViewModel(
    private val api: MentorBackend,
    private val session: Session,
    private val cache: Cache,
    private val reminders: ReminderScheduler,
    private val clock: () -> LocalDate = { LocalDate.now() },
) : ViewModel() {

    private val _state = MutableStateFlow(
        UiState(signedIn = session.token != null, loading = session.token != null, reminderHour = session.reminderHour)
    )
    val state: StateFlow<UiState> = _state.asStateFlow()

    init {
        if (session.token != null) load()
    }

    // Запуск с общей обработкой ошибок: истёкший вход, понятные ошибки сервера и нет сети
    private fun launchSafely(networkError: String, block: suspend () -> Unit) = viewModelScope.launch {
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: SessionExpired) {
            signOut(notice = "Сессия истекла, войди снова.")
        } catch (e: ServerMessage) {
            _state.update { it.copy(loading = false, submitting = false, error = e.message) }
        } catch (e: Exception) {
            _state.update { it.copy(loading = false, submitting = false, error = networkError) }
        }
    }

    // ---------- Вход ----------

    fun loginWithGoogle(idToken: String) = login { api.loginGoogle(idToken).token }

    fun loginDev() = login { api.loginDev(session.deviceId).token }

    private fun login(getToken: suspend () -> String) = launchSafely("Нет связи с сервером. Проверь, что он запущен.") {
        _state.update { it.copy(submitting = true, error = null) }
        session.token = getToken()
        _state.update { it.copy(signedIn = true, submitting = false, loading = true) }
        refresh()
    }

    fun loginFailed(message: String) = _state.update { it.copy(error = message) }

    fun signOut(notice: String? = null) {
        session.token = null
        cache.clear()
        _state.value = UiState(signedIn = false, loading = false, reminderHour = session.reminderHour, notice = notice)
    }

    // ---------- Данные ----------

    fun load() {
        // сначала показываем сохранённое, чтобы экран не был пустым, потом обновляем с сервера
        cache.plan?.takeIf { _state.value.plan == null }?.let { plan ->
            _state.update { it.copy(loading = false, hasProfile = true, plan = plan, today = cache.today, progress = cache.progress) }
        }
        viewModelScope.launch {
            _state.update { it.copy(loading = it.plan == null, error = null) }
            try {
                refresh()
            } catch (e: CancellationException) {
                throw e
            } catch (e: SessionExpired) {
                signOut(notice = "Сессия истекла, войди снова.")
            } catch (e: Exception) {
                _state.update {
                    if (it.plan != null) it.copy(loading = false, offline = true)
                    else it.copy(loading = false, error = "Нет связи с сервером. Проверь интернет и попробуй ещё раз.")
                }
            }
        }
    }

    private suspend fun refresh() {
        val plan = api.plan()
        if (plan == null) {
            cache.clear()
            _state.update {
                it.copy(loading = false, submitting = false, hasProfile = false, plan = null, today = null, progress = null, offline = false)
            }
            return
        }
        val (today, progress) = coroutineScope {
            // генерация миссии на сервере может занять время, прогресс грузим параллельно
            val today = async { api.today() }
            val progress = async { api.progress() }
            today.await() to progress.await()
        }
        // после перерыва сервер пересобирает план при запросе today – тогда план нужен свежий
        val fresh = if (today.planRebuilt) api.plan() ?: plan else plan
        cache.plan = fresh
        cache.today = today
        cache.progress = progress
        _state.update {
            it.copy(
                loading = false, submitting = false, hasProfile = true, offline = false, error = null,
                plan = fresh, today = today, progress = progress,
            )
        }
    }

    fun createProfile(req: ProfileRequest) = launchSafely("Не удалось составить план. Попробуй ещё раз.") {
        _state.update { it.copy(submitting = true, error = null) }
        api.createProfile(req)
        _state.update { it.copy(changingArea = false, evaluation = null) }
        refresh()
    }

    fun startChangeArea() = _state.update { it.copy(changingArea = true, error = null) }

    fun cancelChangeArea() = _state.update { it.copy(changingArea = false, error = null) }

    fun submitAnswer(text: String) {
        val mission = _state.value.today?.mission ?: return
        launchSafely("Не удалось проверить ответ. Попробуй ещё раз.") {
            _state.update { it.copy(submitting = true, error = null) }
            val ev = api.answer(AnswerRequest(mission.id, text))
            if (ev.passed) session.lastPassedDay = clock().toString()
            _state.update { it.copy(submitting = false, evaluation = ev) }
        }
    }

    // После разбора ответа: убрать оценку и подтянуть следующую миссию, план и прогресс
    fun next() = launchSafely("Нет связи с сервером.") {
        refresh()
        _state.update { it.copy(evaluation = null) }
    }

    // ---------- Настройки ----------

    fun saveSettings(goal: String, minutesPerDay: Int, daysPerWeek: Int) = launchSafely("Не удалось сохранить настройки.") {
        _state.update { it.copy(submitting = true, error = null) }
        api.updateSettings(SettingsRequest(goal.trim(), minutesPerDay, daysPerWeek))
        refresh()
        _state.update { it.copy(notice = "Настройки сохранены") }
    }

    // null – выключить напоминания
    fun setReminder(hour: Int?) {
        session.reminderHour = hour
        if (hour == null) reminders.cancel() else reminders.schedule(hour)
        _state.update { it.copy(reminderHour = hour) }
    }

    fun deleteAccount() = launchSafely("Не удалось удалить аккаунт.") {
        api.deleteAccount()
        cache.clear()
        setReminder(null)
        _state.value = UiState(signedIn = true, loading = false, hasProfile = false, notice = "Аккаунт и данные удалены")
    }

    fun consumeNotice() = _state.update { it.copy(notice = null) }

    companion object {
        val Factory = viewModelFactory {
            initializer {
                val c = (this[APPLICATION_KEY] as MentorApplication).container
                MentorViewModel(c.api, c.session, c.cache, c.reminders)
            }
        }
    }
}

// ---------- Чат «Застрял» ----------

data class ChatUi(
    val missionId: String? = null,
    val messages: List<ChatMessage> = emptyList(),
    val sending: Boolean = false,
    val draft: String = "", // текст, который вернуть в поле ввода, если отправка не удалась
    val error: String? = null,
)

class ChatViewModel(private val api: MentorBackend) : ViewModel() {
    private val _state = MutableStateFlow(ChatUi())
    val state: StateFlow<ChatUi> = _state.asStateFlow()

    // Для каждой миссии – свой разговор
    fun open(missionId: String) {
        if (_state.value.missionId != missionId) _state.value = ChatUi(missionId)
    }

    fun send(text: String) {
        val current = _state.value
        val missionId = current.missionId ?: return
        val question = text.trim()
        if (question.isEmpty() || current.sending) return
        val messages = current.messages + ChatMessage(ChatRole.USER, question)
        _state.update { it.copy(messages = messages, sending = true, draft = "", error = null) }
        viewModelScope.launch {
            try {
                val reply = api.chat(ChatRequest(missionId, messages)).reply
                _state.update { it.copy(messages = it.messages + ChatMessage(ChatRole.MENTOR, reply), sending = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = when (e) {
                    is SessionExpired -> "Сессия истекла, войди снова."
                    is ServerMessage -> e.message
                    else -> "Не удалось получить ответ. Проверь интернет."
                }
                // убираем неотправленный вопрос и возвращаем его в поле ввода
                _state.update { it.copy(messages = it.messages.dropLast(1), sending = false, draft = question, error = error) }
            }
        }
    }

    companion object {
        val Factory = viewModelFactory {
            initializer { ChatViewModel((this[APPLICATION_KEY] as MentorApplication).container.api) }
        }
    }
}
