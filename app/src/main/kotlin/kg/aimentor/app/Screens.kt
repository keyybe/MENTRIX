package kg.aimentor.app

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Dns
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FitnessCenter
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.LocalCafe
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.PhoneAndroid
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material.icons.rounded.RocketLaunch
import androidx.compose.material.icons.rounded.School
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Work
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.aimentor.shared.ItArea
import kg.aimentor.shared.Level
import kg.aimentor.shared.MissionDto
import kg.aimentor.shared.MissionStatus
import kg.aimentor.shared.ProfileRequest

// ---------- Общие элементы ----------

val ItArea.icon: ImageVector get() = when (this) {
    ItArea.FRONTEND -> Icons.Rounded.Language
    ItArea.BACKEND -> Icons.Rounded.Dns
    ItArea.MOBILE -> Icons.Rounded.PhoneAndroid
}

private val ItArea.hint get() = when (this) {
    ItArea.FRONTEND -> "Сайты и интерфейсы"
    ItArea.BACKEND -> "Серверы и базы данных"
    ItArea.MOBILE -> "Приложения для телефона"
}

@Composable
fun AppTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    singleLine: Boolean = false,
    minLines: Int = 1,
    enabled: Boolean = true,
    code: Boolean = false,
    leadingIcon: @Composable (() -> Unit)? = null,
    trailingIcon: @Composable (() -> Unit)? = null,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions? = null,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder, color = Palette.InkSoft) },
        singleLine = singleLine,
        minLines = minLines,
        enabled = enabled,
        leadingIcon = leadingIcon,
        trailingIcon = trailingIcon,
        visualTransformation = visualTransformation,
        shape = RoundedCornerShape(18.dp),
        textStyle = if (code) LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace, fontSize = 15.sp) else LocalTextStyle.current,
        keyboardOptions = keyboardOptions ?: if (code) {
            KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false)
        } else {
            KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
        },
        colors = OutlinedTextFieldDefaults.colors(
            unfocusedBorderColor = Palette.Line,
            focusedBorderColor = Palette.Indigo,
            unfocusedContainerColor = Palette.Surface,
            focusedContainerColor = Palette.Surface,
            disabledContainerColor = Palette.Surface,
            disabledBorderColor = Palette.Line,
            disabledTextColor = Palette.Ink,
            cursorColor = Palette.Indigo,
        ),
        modifier = modifier.fillMaxWidth(),
    )
}

// Вариант ответа в онбординге: иконка, текст и отметка выбора справа
@Composable
private fun OptionCard(icon: ImageVector, tint: Color, title: String, subtitle: String?, selected: Boolean, onClick: () -> Unit) {
    SoftCard(onClick = onClick, selected = selected, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            IconTile(icon, tint = if (selected) Color.White else tint, background = if (selected) Palette.Indigo else tint.copy(alpha = 0.12f))
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleMedium, color = Palette.Ink)
                subtitle?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = Palette.InkSoft) }
            }
            Box(
                Modifier
                    .size(22.dp)
                    .clip(CircleShape)
                    .background(if (selected) Palette.Indigo else Color.Transparent)
                    .border(2.dp, if (selected) Palette.Indigo else Palette.Line, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                if (selected) Box(Modifier.size(8.dp).clip(CircleShape).background(Color.White))
            }
        }
    }
}

// ---------- Онбординг (F1): один вопрос на экран ----------

private class Choice(val icon: ImageVector, val tint: Color, val title: String, val subtitle: String? = null)

private val GoalChoices = listOf(
    Choice(Icons.Rounded.Work, Palette.Indigo, "Найти первую работу"),
    Choice(Icons.Rounded.SwapHoriz, Palette.Sky, "Сменить профессию"),
    Choice(Icons.Rounded.School, Palette.Mint, "Для учёбы"),
    Choice(Icons.Rounded.Favorite, Palette.Coral, "Для себя"),
)

private val MinuteChoices = listOf(
    15 to Choice(Icons.Rounded.LocalCafe, Palette.Mint, "15 минут", "Спокойный темп"),
    20 to Choice(Icons.Rounded.Timer, Palette.Sky, "20 минут", "Оптимально"),
    30 to Choice(Icons.Rounded.FitnessCenter, Palette.Indigo, "30 минут", "Серьёзно"),
    40 to Choice(Icons.Rounded.Bolt, Palette.Amber, "40 минут", "Интенсивно"),
)

private val AreaTints = mapOf(ItArea.FRONTEND to Palette.Sky, ItArea.BACKEND to Palette.Indigo, ItArea.MOBILE to Palette.Mint)

@Composable
fun OnboardingScreen(
    state: UiState,
    onCreate: (ProfileRequest) -> Unit,
    onRetry: () -> Unit,
    onCancel: (() -> Unit)? = null, // есть, когда человек меняет направление уже существующего плана
) {
    // при смене направления подставляем текущие настройки
    val plan = state.plan
    var step by rememberSaveable { mutableIntStateOf(0) }
    var area by rememberSaveable { mutableStateOf(plan?.area ?: ItArea.FRONTEND) }
    var level by rememberSaveable { mutableStateOf(plan?.level ?: Level.BEGINNER) }
    var goal by rememberSaveable { mutableStateOf(plan?.goal ?: "") }
    var minutes by rememberSaveable { mutableIntStateOf(plan?.minutesPerDay ?: 20) }
    var days by rememberSaveable { mutableIntStateOf(plan?.daysPerWeek ?: 5) }
    val steps = 4
    val back: () -> Unit = { if (step > 0) step-- else onCancel?.invoke() }

    BackHandler(enabled = step > 0 || onCancel != null) { back() }

    Column(
        Modifier
            .fillMaxSize()
            .background(Palette.Background)
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .padding(horizontal = 20.dp, vertical = 8.dp),
    ) {
        Row(Modifier.height(48.dp), verticalAlignment = Alignment.CenterVertically) {
            if (step > 0 || onCancel != null) {
                IconButton(onClick = back) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Назад", tint = Palette.Ink) }
            }
            Spacer(Modifier.weight(1f))
            Text("Шаг ${step + 1} из $steps", style = MaterialTheme.typography.labelMedium, color = Palette.InkSoft)
        }
        SlimProgress((step + 1f) / steps, height = 6.dp)
        Spacer(Modifier.height(28.dp))

        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            when (step) {
                0 -> {
                    Question("Что хочешь изучать?", "Можно поменять в любой момент")
                    ItArea.entries.forEach { a -> OptionCard(a.icon, AreaTints.getValue(a), a.title, a.hint, area == a) { area = a } }
                }
                1 -> {
                    Question("Твой уровень", "Подберём темы под тебя")
                    OptionCard(Icons.Rounded.Explore, Palette.Mint, "Я новичок", "Начнём с самых основ", level == Level.BEGINNER) { level = Level.BEGINNER }
                    OptionCard(Icons.Rounded.RocketLaunch, Palette.Indigo, "Знаю основы", "Пропустим базовые темы", level == Level.CONTINUING) { level = Level.CONTINUING }
                }
                2 -> {
                    Question("Какая у тебя цель?", "Это поможет держать мотивацию")
                    GoalChoices.forEach { c -> OptionCard(c.icon, c.tint, c.title, null, goal == c.title) { goal = c.title } }
                    AppTextField(
                        value = if (GoalChoices.any { it.title == goal }) "" else goal,
                        onValueChange = { goal = it },
                        placeholder = "Или напиши свою",
                        singleLine = true,
                    )
                }
                else -> {
                    Question("Сколько времени в день?", "Лучше понемногу, но каждый день")
                    MinuteChoices.forEach { (m, c) -> OptionCard(c.icon, c.tint, c.title, c.subtitle, minutes == m) { minutes = m } }
                    Text("Дней в неделю", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        (3..7).forEach { d ->
                            val selected = days == d
                            Box(
                                Modifier
                                    .weight(1f)
                                    .height(52.dp)
                                    .clip(RoundedCornerShape(16.dp))
                                    .background(if (selected) Palette.Indigo else Palette.Surface)
                                    .border(1.dp, if (selected) Palette.Indigo else Palette.Line, RoundedCornerShape(16.dp))
                                    .pressable { days = d },
                                contentAlignment = Alignment.Center,
                            ) {
                                Text("$d", style = MaterialTheme.typography.titleLarge, color = if (selected) Color.White else Palette.Ink)
                            }
                        }
                    }
                }
            }
            state.error?.let {
                Text(it, color = Palette.Coral, style = MaterialTheme.typography.bodyMedium)
                TextButton(onClick = onRetry) { Text("Повторить", color = Palette.Indigo) }
            }
            if (onCancel != null && step == steps - 1) {
                Text("Новый план заменит текущий: прогресс начнётся заново.", style = MaterialTheme.typography.bodySmall, color = Palette.InkSoft)
            }
            Spacer(Modifier.height(8.dp))
        }

        PrimaryButton(
            text = if (step < steps - 1) "Продолжить" else "Составить план",
            onClick = { if (step < steps - 1) step++ else onCreate(ProfileRequest(area, goal.trim(), level, minutes, days)) },
            enabled = step != 2 || goal.isNotBlank(),
            loading = state.submitting,
            modifier = Modifier.padding(vertical = 12.dp),
        )
    }
}

@Composable
private fun Question(title: String, subtitle: String) {
    Column(Modifier.padding(bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.headlineMedium)
        Text(subtitle, style = MaterialTheme.typography.bodyLarge, color = Palette.InkSoft)
    }
}

// ---------- План: недели и уроки ----------

@Composable
fun PlanScreen(state: UiState, modifier: Modifier, onStart: () -> Unit = {}) {
    val plan = state.plan ?: return
    val currentId = state.today?.mission?.id
    LazyColumn(
        modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Мой план", style = MaterialTheme.typography.headlineSmall)
                Text("${plan.area.title} · ${plan.weeks.size} нед. · цель: ${plan.goal}", style = MaterialTheme.typography.bodyMedium, color = Palette.InkSoft)
            }
        }
        items(plan.weeks, key = { it.index }) { week ->
            val done = week.missions.count { it.status == MissionStatus.DONE }
            val hasCurrent = week.missions.any { it.id == currentId }
            SoftCard(modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(vertical = 8.dp)) {
                    Row(Modifier.padding(horizontal = 18.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            Modifier
                                .size(36.dp)
                                .clip(RoundedCornerShape(12.dp))
                                .background(if (hasCurrent || done == week.missions.size) PrimaryGradient else androidx.compose.ui.graphics.SolidColor(Palette.Background)),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                "${week.index}",
                                style = MaterialTheme.typography.titleMedium,
                                color = if (hasCurrent || done == week.missions.size) Color.White else Palette.InkSoft,
                            )
                        }
                        Column(Modifier.weight(1f).padding(start = 12.dp)) {
                            Text("Неделя ${week.index}", style = MaterialTheme.typography.labelMedium, color = Palette.InkSoft)
                            Text(week.title.substringAfter(": "), style = MaterialTheme.typography.titleMedium)
                        }
                        Text("$done/${week.missions.size}", style = MaterialTheme.typography.labelLarge, color = Palette.InkSoft)
                    }
                    SlimProgress(
                        if (week.missions.isEmpty()) 0f else done.toFloat() / week.missions.size,
                        Modifier.padding(horizontal = 18.dp),
                        height = 4.dp,
                    )
                    Spacer(Modifier.height(6.dp))
                    week.missions.forEach { m -> MissionRow(m, current = m.id == currentId, onClick = onStart) }
                }
            }
        }
    }
}

@Composable
private fun MissionRow(m: MissionDto, current: Boolean, onClick: () -> Unit) {
    val done = m.status == MissionStatus.DONE
    val (icon, tint, bg) = when {
        done -> Triple(Icons.Rounded.CheckCircle, Palette.Mint, Palette.MintSoft)
        current -> Triple(Icons.Rounded.PlayArrow, Color.White, Palette.Indigo)
        m.review -> Triple(Icons.Rounded.Replay, Palette.Amber, Palette.AmberSoft)
        else -> Triple(Icons.Rounded.Lock, Palette.InkSoft, Palette.Background)
    }
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(if (current) Palette.IndigoSoft else Color.Transparent)
            .then(if (current) Modifier.pressable(onClick = onClick) else Modifier)
            .padding(horizontal = 10.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconTile(icon, tint, bg, size = 36.dp)
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(
                m.title,
                style = MaterialTheme.typography.titleSmall,
                color = if (done || current) Palette.Ink else Palette.InkSoft,
            )
            val sub = when {
                current -> "Сейчас · ${m.minutes} мин"
                m.status == MissionStatus.TODO && m.availableFrom != null -> "Повторение с ${m.availableFrom}"
                m.review -> "Повторение"
                done -> "Пройдено"
                else -> "${m.minutes} мин"
            }
            Text(sub, style = MaterialTheme.typography.bodySmall, color = if (current) Palette.Indigo else Palette.InkSoft)
        }
        if (current) Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = Palette.Indigo)
    }
}
