package kg.aimentor.app

import android.content.Context
import androidx.core.content.edit
import kg.aimentor.shared.PlanDto
import kg.aimentor.shared.ProgressDto
import kg.aimentor.shared.TodayDto
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import java.util.UUID

// Вход и личные настройки на устройстве
interface Session {
    var token: String?
    val deviceId: String
    var reminderHour: Int?   // null – напоминания выключены
    var lastPassedDay: String? // день (yyyy-MM-dd), когда миссия засчитана – в этот день не напоминаем
}

// Последние данные с сервера, чтобы приложение открывалось и без интернета
interface Cache {
    var plan: PlanDto?
    var today: TodayDto?
    var progress: ProgressDto?
    fun clear()
}

class PrefsSession(context: Context) : Session {
    private val prefs = context.getSharedPreferences("mentor", Context.MODE_PRIVATE)

    override var token: String?
        get() = prefs.getString("token", null)
        set(value) = prefs.edit { putString("token", value) }

    // раньше здесь хранился uid для заголовка X-User-Id – переиспользуем его как id устройства
    override val deviceId: String = prefs.getString("uid", null)
        ?: UUID.randomUUID().toString().also { id -> prefs.edit { putString("uid", id) } }

    override var reminderHour: Int?
        get() = prefs.getInt("reminderHour", -1).takeIf { it >= 0 }
        set(value) = prefs.edit { putInt("reminderHour", value ?: -1) }

    override var lastPassedDay: String?
        get() = prefs.getString("lastPassedDay", null)
        set(value) = prefs.edit { putString("lastPassedDay", value) }
}

class PrefsCache(context: Context) : Cache {
    private val prefs = context.getSharedPreferences("mentor-cache", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    private fun <T> read(key: String, serializer: KSerializer<T>): T? =
        prefs.getString(key, null)?.let { runCatching { json.decodeFromString(serializer, it) }.getOrNull() }

    private fun <T> write(key: String, serializer: KSerializer<T>, value: T?) = prefs.edit {
        if (value == null) remove(key) else putString(key, json.encodeToString(serializer, value))
    }

    override var plan: PlanDto?
        get() = read("plan", PlanDto.serializer())
        set(value) = write("plan", PlanDto.serializer(), value)

    override var today: TodayDto?
        get() = read("today", TodayDto.serializer())
        set(value) = write("today", TodayDto.serializer(), value)

    override var progress: ProgressDto?
        get() = read("progress", ProgressDto.serializer())
        set(value) = write("progress", ProgressDto.serializer(), value)

    override fun clear() = prefs.edit { clear() }
}
