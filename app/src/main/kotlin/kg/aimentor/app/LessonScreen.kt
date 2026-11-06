package kg.aimentor.app

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Lightbulb
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.aimentor.shared.EvaluationDto
import kg.aimentor.shared.MissionDto

private val SuccessGradient = Brush.linearGradient(listOf(Palette.Mint, Color(0xFF0EA5A0)))

// Урок дня (F3, F4): отдельный полноэкранный режим, чтобы ничего не отвлекало.
// onNext – обновить данные и перейти к следующему уроку, onFinish – то же, но вернуться на главную.
@Composable
fun LessonScreen(
    state: UiState,
    onSubmit: (String) -> Unit,
    onNext: () -> Unit,
    onFinish: () -> Unit,
    onClose: () -> Unit,
    onAskMentor: () -> Unit,
) {
    val mission = state.today?.mission
    val ev = state.evaluation
    var answer by rememberSaveable(mission?.id) { mutableStateOf("") }
    // шаги урока: вопрос → ответ → результат
    val step = when {
        ev != null -> 3f
        answer.isNotBlank() -> 2f
        else -> 1f
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(Palette.Background)
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .imePadding(),
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose) { Icon(Icons.Rounded.Close, contentDescription = "Закрыть урок", tint = Palette.InkSoft) }
            SlimProgress(step / 3f, Modifier.weight(1f).padding(end = 16.dp), height = 6.dp)
        }

        AnimatedContent(
            targetState = when {
                mission == null -> LessonPhase.Empty
                ev?.passed == true -> LessonPhase.Reward
                else -> LessonPhase.Question
            },
            transitionSpec = { (fadeIn() + scaleIn(initialScale = 0.96f)) togetherWith fadeOut() },
            modifier = Modifier.weight(1f),
            label = "lesson",
        ) { phase ->
            when (phase) {
                LessonPhase.Empty -> EmptyLesson(state.today?.message, onFinish)
                LessonPhase.Reward -> ev?.let { RewardView(it, onNext = onNext, onFinish = onFinish) }
                LessonPhase.Question -> mission?.let {
                    QuestionView(state, it, answer, { answer = it }, ev, onSubmit, onNext, onAskMentor)
                }
            }
        }
    }
}

private enum class LessonPhase { Empty, Question, Reward }

@Composable
private fun QuestionView(
    state: UiState,
    mission: MissionDto,
    answer: String,
    onAnswer: (String) -> Unit,
    ev: EvaluationDto?,
    onSubmit: (String) -> Unit,
    onNext: () -> Unit,
    onAskMentor: () -> Unit,
) {
    val uri = LocalUriHandler.current
    Column(Modifier.fillMaxSize()) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (mission.review) {
                    InfoPill(Icons.Rounded.Replay, "Повторение", Palette.Amber, Palette.AmberSoft)
                } else {
                    InfoPill(Icons.Rounded.AutoAwesome, "Новый урок", Palette.Indigo, Palette.IndigoSoft)
                }
                if (mission.code) InfoPill(Icons.Rounded.Code, "Код", Palette.Mint, Palette.MintSoft)
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("${mission.topic} · ${mission.title}", style = MaterialTheme.typography.labelLarge, color = Palette.InkSoft)
                Text(mission.task, style = MaterialTheme.typography.headlineSmall.copy(fontSize = 24.sp, lineHeight = 32.sp))
            }
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
            AppTextField(
                value = answer,
                onValueChange = onAnswer,
                placeholder = if (mission.code) "Напиши код здесь…" else "Твой ответ…",
                minLines = if (mission.code) 6 else 4,
                enabled = ev == null,
                code = mission.code,
            )
            // Разбор ответа мягко раскрывается прямо под полем.
            AnimatedVisibility(
                visible = ev != null,
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + androidx.compose.animation.shrinkVertically(),
            ) {
                ev?.let { MistakeCard(it) }
            }
            state.error?.let { Text(it, color = Palette.Coral, style = MaterialTheme.typography.bodyMedium) }
        }

        // кнопка всегда внизу, над клавиатурой
        Box(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp)) {
            if (ev == null) {
                PrimaryButton(
                    text = "Проверить",
                    onClick = { onSubmit(answer) },
                    enabled = answer.isNotBlank() && !state.offline,
                    loading = state.submitting,
                )
            } else {
                PrimaryButton(text = "Понятно, дальше", onClick = onNext)
            }
        }
    }
}

@Composable
private fun MistakeCard(ev: EvaluationDto) {
    SoftCard(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconTile(Icons.Rounded.Lightbulb, Palette.Amber, Palette.AmberSoft)
                Column(Modifier.weight(1f)) {
                    Text("Почти получилось", style = MaterialTheme.typography.titleMedium)
                    Text("${ev.score}% · разбери подсказку и двигайся дальше", style = MaterialTheme.typography.bodySmall, color = Palette.InkSoft)
                }
            }
            Text(ev.feedback, style = MaterialTheme.typography.bodyLarge)
            ev.gaps.forEach { gap ->
                Row(verticalAlignment = Alignment.Top) {
                    Box(Modifier.padding(top = 8.dp).size(6.dp).clip(CircleShape).background(Palette.Amber))
                    Text(gap, style = MaterialTheme.typography.bodyMedium, color = Palette.InkSoft, modifier = Modifier.padding(start = 10.dp))
                }
            }
        }
    }
}

// Экран-награда после верного ответа
@Composable
private fun RewardView(ev: EvaluationDto, onNext: () -> Unit, onFinish: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        ) {
            Box(
                Modifier.size(112.dp).clip(CircleShape).background(SuccessGradient),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(64.dp))
            }
            Text("Отлично!", style = MaterialTheme.typography.headlineLarge)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                InfoPill(Icons.Rounded.LocalFireDepartment, "Серия ${ev.streak} дн.", Palette.Amber, Palette.AmberSoft)
                InfoPill(Icons.Rounded.EmojiEvents, "${ev.score}%", Palette.Mint, Palette.MintSoft)
            }
            SoftCard(modifier = Modifier.fillMaxWidth()) {
                Text(ev.feedback, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(18.dp))
            }
        }
        PrimaryButton(text = "Ещё урок", onClick = onNext, brush = SuccessGradient)
        Spacer(Modifier.height(10.dp))
        TonalButton("На сегодня хватит", onFinish, modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun EmptyLesson(message: String?, onFinish: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically),
    ) {
        IconTile(Icons.Rounded.EmojiEvents, Palette.Amber, Palette.AmberSoft, size = 88.dp)
        Text("На сегодня всё", style = MaterialTheme.typography.headlineMedium)
        Text(
            message ?: "Возвращайся завтра за новым уроком.",
            style = MaterialTheme.typography.bodyLarge,
            color = Palette.InkSoft,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(8.dp))
        PrimaryButton(text = "На главную", onClick = onFinish)
    }
}
