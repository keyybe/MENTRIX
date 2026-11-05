package kg.aimentor.server

import kg.aimentor.shared.ItArea
import kotlinx.serialization.Serializable

// Задание внутри источника. keywords – ключевые понятия, по ним оценивает офлайн-проверка.
// Через "|" можно указать синонимы: "хеш|hash|хэш".
// code = true – практическое задание, в ответе нужно написать код.
@Serializable
data class TaskDef(val title: String, val prompt: String, val keywords: List<String>, val code: Boolean = false)

// Проверенный источник из базы. basic = true – для новичков, продолжающие такие пропускают.
@Serializable
data class Source(
    val id: String,
    val title: String,
    val url: String,
    val area: ItArea,
    val basic: Boolean,
    val minutes: Int,
    val tasks: List<TaskDef>,
)

object SourceBase {
    fun load(): List<Source> {
        val text = SourceBase::class.java.getResourceAsStream("/sources.json")!!
            .bufferedReader(Charsets.UTF_8).use { it.readText() }
        return storeJson.decodeFromString<List<Source>>(text)
    }
}
