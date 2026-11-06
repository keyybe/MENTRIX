package kg.aimentor.app

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import kg.aimentor.shared.MissionStatus
import kg.aimentor.shared.WeekDto
import java.time.LocalDate
import java.time.LocalTime

private val DayLetters = listOf("Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс")

// Главный экран: что делать сейчас, как дела и что дальше. Сам урок открывается отдельным экраном.
@Composable
fun HomeScreen(
    state: UiState,
    modifier: Modifier,
    onStartLesson: () -> Unit,
    onOpenChat: () -> Unit,
    onOpenPlan: () -> Unit,
    onRetry: () -> Unit,
) {
    val p = state.progress
    val mission = state.today?.mission

    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // приветствие и серия
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(greeting(state.userName), style = MaterialTheme.typography.headlineSmall)
                Text(state.plan?.area?.title ?: "", style = MaterialTheme.typography.bodyMedium, color = Palette.InkSoft)
            }
            InfoPill(Icons.Rounded.LocalFireDepartment, "${p?.streak ?: 0}", Palette.Amber, Palette.AmberSoft)
        }

        if (state.offline) {
            SoftCard(color = Palette.CoralSoft, modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.WifiOff, contentDescription = null, tint = Palette.Coral, modifier = Modifier.size(18.dp))
                    Text("Нет связи – показаны сохранённые данные", style = MaterialTheme.typography.bodySmall, color = Palette.Coral, modifier = Modifier.weight(1f).padding(start = 8.dp))
                    TextButton(onClick = onRetry) { Text("Обновить", color = Palette.Coral) }
                }
            }
        }

        WeekStrip(p?.weekActivity.orEmpty(), p?.doneToday == true)

        LessonHero(state, onStartLesson)

        // быстрые действия
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            val reviews = p?.reviewsDue ?: 0
            QuickTile(
                icon = Icons.Rounded.Replay,
                tint = Palette.Amber,
                title = if (reviews > 0) "$reviews ${plural(reviews, "тема", "темы", "тем")}" else "Повторений нет",
                subtitle = if (reviews > 0) "пора повторить" else "всё закреплено",
                enabled = reviews > 0 && !state.offline,
                onClick = onStartLesson,
                modifier = Modifier.weight(1f),
            )
            QuickTile(
                icon = Icons.Rounded.AutoAwesome,
                tint = Palette.Indigo,
                title = "Ментор",
                subtitle = "спросить об уроке",
                enabled = mission != null && !state.offline,
                onClick = onOpenChat,
                modifier = Modifier.weight(1f),
            )
        }

        currentWeek(state)?.let { week -> WeekProgressCard(week, onOpenPlan) }
        Spacer(Modifier.height(4.dp))
    }
}

private fun greeting(name: String?): String {
    val hour = LocalTime.now().hour
    val hello = when (hour) {
        in 5..11 -> "Доброе утро"
        in 12..17 -> "Добрый день"
        in 18..22 -> "Добрый вечер"
        else -> "Доброй ночи"
    }
    return if (name.isNullOrBlank()) "$hello!" else "$hello, $name!"
}

private fun plural(n: Int, one: String, few: String, many: String): String {
    val mod10 = n % 10
    val mod100 = n % 100
    return when {
        mod10 == 1 && mod100 != 11 -> one
        mod10 in 2..4 && mod100 !in 12..14 -> few
        else -> many
    }
}

// Неделя текущего урока, а если план пройден – последняя
private fun currentWeek(state: UiState): WeekDto? {
    val weeks = state.plan?.weeks ?: return null
    val id = state.today?.mission?.id
    return weeks.firstOrNull { w -> w.missions.any { it.id == id } }
        ?: weeks.firstOrNull { w -> w.missions.any { it.status == MissionStatus.TODO } }
        ?: weeks.lastOrNull()
}

// Пн…Вс: закрашены дни с пройденным уроком, сегодняшний обведён
@Composable
private fun WeekStrip(activity: List<Boolean>, doneToday: Boolean) {
    val todayIndex = LocalDate.now().dayOfWeek.value - 1
    SoftCard(modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 14.dp), horizontalArrangement = Arrangement.SpaceAround) {
            DayLetters.forEachIndexed { i, letter ->
                val done = activity.getOrElse(i) { false } || (i == todayIndex && doneToday)
                val isToday = i == todayIndex
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        letter,
                        style = MaterialTheme.typography.labelMedium,
                        color = if (isToday) Palette.Indigo else Palette.InkSoft,
                    )
                    Box(
                        Modifier
                            .size(34.dp)
                            .clip(CircleShape)
                            .then(
                                when {
                                    done -> Modifier.background(PrimaryGradient)
                                    isToday -> Modifier.border(2.dp, Palette.Indigo, CircleShape)
                                    i < todayIndex -> Modifier.background(Palette.Line)
                                    else -> Modifier.background(Palette.Background)
                                }
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (done) Icon(Icons.Rounded.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
                    }
                }
            }
        }
    }
}

// Главная карточка: урок дня и одна кнопка
@Composable
private fun LessonHero(state: UiState, onStart: () -> Unit) {
    val mission = state.today?.mission
    val doneToday = state.progress?.doneToday == true
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp)).background(HeroGradient).padding(22.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        when {
            mission == null -> {
                Icon(Icons.Rounded.EmojiEvents, contentDescription = null, tint = Color.White, modifier = Modifier.size(36.dp))
                Text("На сегодня всё", style = MaterialTheme.typography.headlineSmall, color = Color.White)
                Text(
                    state.today?.message ?: "Возвращайся завтра за новым уроком.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.White.copy(alpha = 0.85f),
                )
            }
            doneToday -> {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Rounded.CheckCircle, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
                    Text("Урок дня пройден", style = MaterialTheme.typography.titleMedium, color = Color.White)
                }
                Text("Дальше: ${mission.title}", style = MaterialTheme.typography.headlineSmall, color = Color.White)
                Text("Можно остановиться или пройти ещё один урок", style = MaterialTheme.typography.bodyMedium, color = Color.White.copy(alpha = 0.85f))
                Spacer(Modifier.height(4.dp))
                HeroButton("Ещё урок", onStart)
            }
            else -> {
                Text(
                    (if (mission.review) "ПОВТОРЕНИЕ" else "УРОК ДНЯ") + " · ${mission.minutes} МИН",
                    style = MaterialTheme.typography.labelMedium,
                    color = Color.White.copy(alpha = 0.8f),
                )
                Text(mission.title, style = MaterialTheme.typography.headlineMedium, color = Color.White)
                Text(mission.topic, style = MaterialTheme.typography.bodyMedium, color = Color.White.copy(alpha = 0.85f))
                Spacer(Modifier.height(4.dp))
                HeroButton("Начать урок", onStart)
            }
        }
    }
}

// Белая кнопка на градиенте
@Composable
private fun HeroButton(text: String, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(52.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White)
            .pressable(onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text, style = MaterialTheme.typography.titleMedium, color = Palette.Indigo)
        Icon(Icons.AutoMirrored.Rounded.ArrowForward, contentDescription = null, tint = Palette.Indigo, modifier = Modifier.padding(start = 8.dp).size(20.dp))
    }
}

@Composable
private fun QuickTile(
    icon: ImageVector,
    tint: Color,
    title: String,
    subtitle: String,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    SoftCard(onClick = if (enabled) onClick else null, modifier = modifier) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            IconTile(icon, if (enabled) tint else Palette.InkSoft, (if (enabled) tint else Palette.InkSoft).copy(alpha = 0.12f), size = 40.dp)
            Column {
                Text(title, style = MaterialTheme.typography.titleMedium, color = if (enabled) Palette.Ink else Palette.InkSoft)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = Palette.InkSoft)
            }
        }
    }
}

// Прогресс текущей недели плана – достижимая цель вместо процентов всего плана
@Composable
private fun WeekProgressCard(week: WeekDto, onOpenPlan: () -> Unit) {
    val done = week.missions.count { it.status == MissionStatus.DONE }
    val total = week.missions.size
    SoftCard(onClick = onOpenPlan, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Неделя ${week.index}", style = MaterialTheme.typography.labelMedium, color = Palette.InkSoft)
                    Text(week.title.substringAfter(": "), style = MaterialTheme.typography.titleMedium)
                }
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = "Открыть план", tint = Palette.InkSoft)
            }
            SlimProgress(if (total == 0) 0f else done.toFloat() / total)
            Text("$done из $total ${plural(total, "урока", "уроков", "уроков")} на этой неделе", style = MaterialTheme.typography.bodySmall, color = Palette.InkSoft)
        }
    }
}
