package kg.aimentor.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
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
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.Dns
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FitnessCenter
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Lightbulb
import androidx.compose.material.icons.rounded.LocalCafe
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.PhoneAndroid
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material.icons.rounded.RocketLaunch
import androidx.compose.material.icons.rounded.School
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material.icons.rounded.TaskAlt
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material.icons.rounded.Work
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kg.aimentor.shared.ItArea
import kg.aimentor.shared.Level
import kg.aimentor.shared.MissionDto
import kg.aimentor.shared.MissionStatus
import kg.aimentor.shared.PlanDto
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
private fun AppTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    singleLine: Boolean = false,
    minLines: Int = 1,
    enabled: Boolean = true,
    code: Boolean = false,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder, color = Palette.InkSoft) },
        singleLine = singleLine,
        minLines = minLines,
        enabled = enabled,
        shape = RoundedCornerShape(18.dp),
        textStyle = if (code) LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace, fontSize = 15.sp) else LocalTextStyle.current,
        keyboardOptions = if (code) {
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

// ---------- Урок дня (F3, F4) ----------

// Шапка с градиентом: кольцо прогресса плана, серия и пройденные уроки
@Composable
private fun TodayHeader(state: UiState) {
    val p = state.progress
    val progress = if (p == null || p.totalMissions == 0) 0f else p.doneMissions.toFloat() / p.totalMissions
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(28.dp))
            .background(HeroGradient)
            .padding(20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        ProgressRing(progress) {
            Text("${(progress * 100).toInt()}%", color = Color.White, style = MaterialTheme.typography.titleMedium)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(state.plan?.area?.title ?: "Мой план", color = Color.White, style = MaterialTheme.typography.titleLarge)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                InfoPill(Icons.Rounded.LocalFireDepartment, "${p?.streak ?: 0} дн.", Color.White, Color.White.copy(alpha = 0.18f))
                InfoPill(Icons.Rounded.TaskAlt, "${p?.doneMissions ?: 0} из ${p?.totalMissions ?: 0}", Color.White, Color.White.copy(alpha = 0.18f))
            }
        }
    }
}

@Composable
fun TodayScreen(
    state: UiState,
    modifier: Modifier,
    onSubmit: (String) -> Unit,
    onNext: () -> Unit,
    onAskMentor: () -> Unit,
    onRetry: () -> Unit,
) {
    val today = state.today
    val mission = today?.mission
    val uri = LocalUriHandler.current
    var answer by rememberSaveable(mission?.id) { mutableStateOf("") }
    val ev = state.evaluation

    Column(
        modifier
            .fillMaxSize()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Привет! Готов учиться?", style = MaterialTheme.typography.headlineSmall)
        TodayHeader(state)

        if (state.offline) {
            SoftCard(color = Palette.CoralSoft, modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.WifiOff, contentDescription = null, tint = Palette.Coral, modifier = Modifier.size(18.dp))
                    Text("Нет связи – показаны сохранённые данные", style = MaterialTheme.typography.bodySmall, color = Palette.Coral, modifier = Modifier.weight(1f).padding(start = 8.dp))
                    TextButton(onClick = onRetry) { Text("Обновить", color = Palette.Coral) }
                }
            }
        }

        if (mission == null) {
            SoftCard(modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.fillMaxWidth().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    IconTile(Icons.Rounded.EmojiEvents, Palette.Amber, Palette.AmberSoft, size = 72.dp)
                    Text("На сегодня всё", style = MaterialTheme.typography.titleLarge)
                    Text(
                        today?.message ?: "Возвращайся завтра за новым уроком.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = Palette.InkSoft,
                        textAlign = TextAlign.Center,
                    )
                }
            }
            return@Column
        }

        // карточка урока
        SoftCard(modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (mission.review) {
                        InfoPill(Icons.Rounded.Replay, "Повторение", Palette.Amber, Palette.AmberSoft)
                    } else {
                        InfoPill(Icons.Rounded.AutoAwesome, "Новый урок", Palette.Indigo, Palette.IndigoSoft)
                    }
                    if (mission.code) InfoPill(Icons.Rounded.Code, "Код", Palette.Mint, Palette.MintSoft)
                    Spacer(Modifier.weight(1f))
                    Text("${mission.minutes} мин", style = MaterialTheme.typography.labelMedium, color = Palette.InkSoft)
                }
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(mission.topic, style = MaterialTheme.typography.labelMedium, color = Palette.InkSoft)
                    Text(mission.title, style = MaterialTheme.typography.titleLarge)
                }
                Box(Modifier.fillMaxWidth().height(1.dp).background(Palette.Line))
                Text(mission.task, style = MaterialTheme.typography.headlineSmall.copy(fontSize = 20.sp, lineHeight = 28.sp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TonalButton(
                        "Материал", { uri.openUri(mission.material.url) },
                        icon = Icons.AutoMirrored.Rounded.MenuBook,
                        color = Palette.Sky, background = Palette.SkySoft,
                        modifier = Modifier.weight(1f),
                    )
                    TonalButton(
                        "Подсказка", onAskMentor,
                        icon = Icons.Rounded.Lightbulb,
                        color = Palette.Amber, background = Palette.AmberSoft,
                        enabled = !state.offline,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        AppTextField(
            value = answer,
            onValueChange = { answer = it },
            placeholder = if (mission.code) "Напиши код здесь…" else "Твой ответ…",
            minLines = if (mission.code) 5 else 3,
            enabled = ev == null,
            code = mission.code,
        )

        if (ev == null) {
            state.error?.let { Text(it, color = Palette.Coral, style = MaterialTheme.typography.bodyMedium) }
            PrimaryButton(
                text = "Проверить",
                onClick = { onSubmit(answer) },
                enabled = answer.isNotBlank() && !state.offline,
                loading = state.submitting,
            )
        }

        AnimatedVisibility(visible = ev != null, enter = fadeIn() + expandVertically()) {
            ev?.let { ResultCard(it.passed, it.score, it.feedback, it.gaps, onNext) }
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun ResultCard(passed: Boolean, score: Int, feedback: String, gaps: List<String>, onNext: () -> Unit) {
    val accent = if (passed) Palette.Mint else Palette.Amber
    SoftCard(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconTile(
                    if (passed) Icons.Rounded.CheckCircle else Icons.Rounded.Lightbulb,
                    tint = accent,
                    background = if (passed) Palette.MintSoft else Palette.AmberSoft,
                    size = 48.dp,
                )
                Column(Modifier.weight(1f)) {
                    Text(if (passed) "Верно!" else "Почти получилось", style = MaterialTheme.typography.titleLarge)
                    Text(if (passed) "Урок пройден" else "Попробуй ещё раз или спроси подсказку", style = MaterialTheme.typography.bodySmall, color = Palette.InkSoft)
                }
                Text("$score%", style = MaterialTheme.typography.headlineSmall, color = accent)
            }
            Text(feedback, style = MaterialTheme.typography.bodyLarge)
            gaps.forEach { gap ->
                Row(verticalAlignment = Alignment.Top) {
                    Box(Modifier.padding(top = 8.dp).size(6.dp).clip(CircleShape).background(accent))
                    Text(gap, style = MaterialTheme.typography.bodyMedium, color = Palette.InkSoft, modifier = Modifier.padding(start = 10.dp))
                }
            }
            PrimaryButton(
                text = if (passed) "Дальше" else "Понятно",
                onClick = onNext,
                brush = if (passed) androidx.compose.ui.graphics.Brush.linearGradient(listOf(Palette.Mint, Color(0xFF0EA5A0))) else PrimaryGradient,
            )
        }
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

// ---------- Профиль (F8) ----------

@Composable
fun ProfileScreen(
    state: UiState,
    modifier: Modifier,
    onSaveSettings: (goal: String, minutesPerDay: Int, daysPerWeek: Int) -> Unit,
    onReminder: (hour: Int?) -> Unit,
    onChangeArea: () -> Unit,
    onSignOut: () -> Unit,
    onDelete: () -> Unit,
) {
    var confirm by rememberSaveable { mutableStateOf(false) }
    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // шапка с градиентом и статистикой
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp)).background(HeroGradient).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(Modifier.size(56.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
                    Icon(state.plan?.area?.icon ?: Icons.Rounded.School, contentDescription = null, tint = Color.White, modifier = Modifier.size(28.dp))
                }
                Column {
                    Text("Мой профиль", style = MaterialTheme.typography.titleLarge, color = Color.White)
                    state.plan?.let { Text(it.goal, style = MaterialTheme.typography.bodyMedium, color = Color.White.copy(alpha = 0.85f)) }
                }
            }
            state.progress?.let { p ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    HeroStat("${p.streak}", "дней подряд", Modifier.weight(1f))
                    HeroStat("${p.doneMissions}", "уроков", Modifier.weight(1f))
                    HeroStat("${if (p.totalMissions == 0) 0 else p.doneMissions * 100 / p.totalMissions}%", "плана", Modifier.weight(1f))
                }
            }
        }

        state.progress?.gaps?.takeIf { it.isNotEmpty() }?.let { gaps ->
            SoftCard(modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    IconTile(Icons.Rounded.Replay, Palette.Amber, Palette.AmberSoft)
                    Column {
                        Text("Темы на повторение", style = MaterialTheme.typography.titleMedium)
                        Text(gaps.joinToString(", "), style = MaterialTheme.typography.bodyMedium, color = Palette.InkSoft)
                    }
                }
            }
        }

        state.plan?.let { SettingsCard(it, state.submitting || state.offline, onSaveSettings) }
        ReminderCard(state.reminderHour, onReminder)

        SoftCard(modifier = Modifier.fillMaxWidth()) {
            ActionRow(Icons.Rounded.SwapHoriz, "Сменить направление", Palette.Indigo, enabled = !state.offline, onClick = onChangeArea)
            Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).height(1.dp).background(Palette.Line))
            ActionRow(Icons.AutoMirrored.Rounded.Logout, "Выйти", Palette.InkSoft, onClick = onSignOut)
            Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).height(1.dp).background(Palette.Line))
            ActionRow(Icons.Rounded.DeleteOutline, "Удалить аккаунт", Palette.Coral, enabled = !state.offline) { confirm = true }
        }
        Spacer(Modifier.height(8.dp))
    }

    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            containerColor = Palette.Surface,
            title = { Text("Удалить аккаунт?") },
            text = { Text("План, прогресс и серия будут удалены без возможности восстановления.") },
            confirmButton = { TextButton(onClick = { confirm = false; onDelete() }) { Text("Удалить", color = Palette.Coral) } },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text("Отмена", color = Palette.Ink) } },
        )
    }
}

@Composable
private fun HeroStat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(
        modifier.clip(RoundedCornerShape(18.dp)).background(Color.White.copy(alpha = 0.16f)).padding(vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(value, style = MaterialTheme.typography.titleLarge, color = Color.White)
        Text(label, style = MaterialTheme.typography.bodySmall, color = Color.White.copy(alpha = 0.85f))
    }
}

@Composable
private fun ActionRow(icon: ImageVector, text: String, tint: Color, enabled: Boolean = true, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().pressable(enabled = enabled, onClick = onClick).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        IconTile(icon, if (enabled) tint else Palette.InkSoft, (if (enabled) tint else Palette.InkSoft).copy(alpha = 0.1f), size = 38.dp)
        Text(text, style = MaterialTheme.typography.titleSmall, color = if (enabled) Palette.Ink else Palette.InkSoft, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = Palette.InkSoft)
    }
}

@Composable
private fun CardHeader(icon: ImageVector, tint: Color, title: String, subtitle: String? = null, trailing: @Composable () -> Unit = {}) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        IconTile(icon, tint, tint.copy(alpha = 0.12f), size = 38.dp)
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            subtitle?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = Palette.InkSoft) }
        }
        trailing()
    }
}

@Composable
private fun SettingsCard(plan: PlanDto, busy: Boolean, onSave: (String, Int, Int) -> Unit) {
    // ключ – текущие значения с сервера: после сохранения поля принимают новые значения
    var goal by rememberSaveable(plan.goal) { mutableStateOf(plan.goal) }
    var minutes by rememberSaveable(plan.minutesPerDay) { mutableFloatStateOf(plan.minutesPerDay.toFloat()) }
    var days by rememberSaveable(plan.daysPerWeek) { mutableFloatStateOf(plan.daysPerWeek.toFloat()) }
    val changed = goal.trim() != plan.goal || minutes.toInt() != plan.minutesPerDay || days.toInt() != plan.daysPerWeek

    SoftCard(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            CardHeader(Icons.Rounded.Tune, Palette.Indigo, "Настройки плана")
            AppTextField(value = goal, onValueChange = { goal = it }, placeholder = "Цель", singleLine = true)
            LabeledSlider("Минут в день", "${minutes.toInt()}", minutes, { minutes = it }, 15f..40f, 4)
            LabeledSlider("Дней в неделю", "${days.toInt()}", days, { days = it }, 3f..7f, 3)
            AnimatedVisibility(changed) {
                PrimaryButton(text = "Сохранить", onClick = { onSave(goal, minutes.toInt(), days.toInt()) }, enabled = goal.isNotBlank() && !busy)
            }
        }
    }
}

@Composable
private fun LabeledSlider(label: String, value: String, current: Float, onChange: (Float) -> Unit, range: ClosedFloatingPointRange<Float>, steps: Int) {
    Column {
        Row {
            Text(label, style = MaterialTheme.typography.bodyMedium, color = Palette.InkSoft, modifier = Modifier.weight(1f))
            Text(value, style = MaterialTheme.typography.titleSmall, color = Palette.Indigo)
        }
        Slider(
            value = current, onValueChange = onChange, valueRange = range, steps = steps,
            colors = SliderDefaults.colors(
                thumbColor = Palette.Indigo,
                activeTrackColor = Palette.Indigo,
                inactiveTrackColor = Palette.IndigoSoft,
                activeTickColor = Color.White.copy(alpha = 0.6f),
                inactiveTickColor = Palette.Indigo.copy(alpha = 0.3f),
            ),
        )
    }
}

@Composable
private fun ReminderCard(hour: Int?, onReminder: (Int?) -> Unit) {
    val context = LocalContext.current
    var selectedHour by rememberSaveable { mutableIntStateOf(hour ?: 19) }
    var denied by rememberSaveable { mutableStateOf(false) }
    // с Android 13 на уведомления нужно разрешение
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        denied = !granted
        if (granted) onReminder(selectedHour)
    }
    fun enable() {
        val needsPermission = Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        if (needsPermission) permission.launch(Manifest.permission.POST_NOTIFICATIONS) else onReminder(selectedHour)
    }

    SoftCard(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            CardHeader(
                Icons.Rounded.Notifications, Palette.Amber, "Напоминание",
                if (hour != null) "Каждый день в $hour:00" else "Выключено",
            ) {
                Switch(
                    checked = hour != null,
                    onCheckedChange = { on -> if (on) enable() else onReminder(null) },
                    colors = SwitchDefaults.colors(checkedTrackColor = Palette.Indigo, uncheckedBorderColor = Palette.Line, uncheckedTrackColor = Palette.Background),
                )
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(8, 12, 18, 20, 22).forEach { h ->
                    val selected = selectedHour == h
                    Text(
                        "$h:00",
                        style = MaterialTheme.typography.labelLarge,
                        color = if (selected) Color.White else Palette.Ink,
                        modifier = Modifier
                            .clip(RoundedCornerShape(12.dp))
                            .background(if (selected) Palette.Indigo else Palette.Background)
                            .pressable {
                                selectedHour = h
                                if (hour != null) onReminder(h)
                            }
                            .padding(horizontal = 14.dp, vertical = 8.dp),
                    )
                }
            }
            if (denied) {
                Text(
                    "Без разрешения на уведомления напоминания не придут. Разреши их в настройках телефона.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Palette.Coral,
                )
            }
        }
    }
}
