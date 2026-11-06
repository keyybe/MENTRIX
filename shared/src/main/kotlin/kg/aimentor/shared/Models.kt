package kg.aimentor.shared

import kotlinx.serialization.Serializable

// DTO, которые одинаково используют сервер и Android-приложение

@Serializable
enum class ItArea(val title: String) {
    FRONTEND("Веб-фронтенд"),
    BACKEND("Бэкенд"),
    MOBILE("Мобильная разработка"),
}

@Serializable
enum class Level { BEGINNER, CONTINUING }

@Serializable
enum class MissionStatus { TODO, DONE }

@Serializable
data class ProfileRequest(
    val area: ItArea,
    val goal: String,
    val level: Level,
    val minutesPerDay: Int,
    val daysPerWeek: Int,
)

@Serializable
data class SourceRef(val title: String, val url: String)

@Serializable
data class MissionDto(
    val id: String,
    val week: Int,
    val day: Int,
    val title: String,
    val topic: String,
    val material: SourceRef,
    val task: String,
    val minutes: Int,
    val status: MissionStatus,
    val review: Boolean = false,
    val code: Boolean = false, // в ответе нужно написать код
    val availableFrom: String? = null, // для повторений: дата (yyyy-MM-dd), раньше которой миссия не откроется
)

@Serializable
data class WeekDto(val index: Int, val title: String, val missions: List<MissionDto>)

@Serializable
data class PlanDto(
    val version: Int,
    val area: ItArea,
    val goal: String,
    val weeks: List<WeekDto>,
    val level: Level = Level.BEGINNER,
    val minutesPerDay: Int = 30,
    val daysPerWeek: Int = 5,
)

@Serializable
data class TodayDto(val mission: MissionDto?, val message: String, val planRebuilt: Boolean = false)

@Serializable
data class AnswerRequest(val missionId: String, val answer: String)

@Serializable
data class EvaluationDto(
    val score: Int,
    val passed: Boolean,
    val feedback: String,
    val gaps: List<String>,
    val streak: Int,
)

@Serializable
data class ProgressDto(
    val streak: Int,
    val doneMissions: Int,
    val totalMissions: Int,
    val planVersion: Int,
    val gaps: List<String>,
    val weekActivity: List<Boolean> = emptyList(), // пн…вс текущей недели: был ли засчитанный урок
    val doneToday: Boolean = false,
    val reviewsDue: Int = 0, // повторения, у которых уже наступил срок
)

@Serializable
data class ErrorDto(val error: String)

// ---------- Вход ----------

@Serializable
data class GoogleAuthRequest(val idToken: String)

// Вход без Google – только для разработки (на сервере включается AUTH_DEV=true)
@Serializable
data class DevAuthRequest(val deviceId: String)

@Serializable
data class AuthResponse(val token: String, val userId: String)

// ---------- Настройки ----------

@Serializable
data class SettingsRequest(val goal: String, val minutesPerDay: Int, val daysPerWeek: Int)

// ---------- Чат «Застрял» (F5) ----------

@Serializable
enum class ChatRole { USER, MENTOR }

@Serializable
data class ChatMessage(val role: ChatRole, val text: String)

@Serializable
data class ChatRequest(val missionId: String, val messages: List<ChatMessage>)

@Serializable
data class ChatReply(val reply: String)
