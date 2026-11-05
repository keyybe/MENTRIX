package kg.aimentor.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kg.aimentor.shared.ChatRole
import kg.aimentor.shared.MissionDto

// Готовые вопросы – чтобы не печатать
private val QuickQuestions = listOf("С чего начать?", "Объясни проще", "Дай подсказку", "Приведи пример")

// Чат «Застрял» (F5): ментор подсказывает наводящими вопросами, но не решает задание за ученика
@Composable
fun ChatScreen(vm: ChatViewModel, mission: MissionDto, onClose: () -> Unit) {
    val state by vm.state.collectAsStateWithLifecycle()
    var input by rememberSaveable { mutableStateOf("") }
    val list = rememberLazyListState()

    // неудачная отправка возвращает вопрос в поле ввода
    LaunchedEffect(state.draft) { if (state.draft.isNotEmpty()) input = state.draft }
    LaunchedEffect(state.messages.size, state.sending) {
        val last = state.messages.size + (if (state.sending) 1 else 0)
        if (last > 0) list.animateScrollToItem(last) // +1 – первая карточка с заданием
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(Palette.Background)
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .imePadding(),
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Назад", tint = Palette.Ink) }
            GradientAvatar(size = 40.dp) { Icon(Icons.Rounded.AutoAwesome, contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp)) }
            Column(Modifier.padding(start = 12.dp)) {
                Text("ИИ-ментор", style = MaterialTheme.typography.titleMedium)
                Text(if (state.sending) "печатает…" else mission.title, style = MaterialTheme.typography.bodySmall, color = if (state.sending) Palette.Indigo else Palette.InkSoft, maxLines = 1)
            }
        }

        LazyColumn(
            state = list,
            modifier = Modifier.weight(1f).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        ) {
            item {
                SoftCard(modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("Вопрос урока", style = MaterialTheme.typography.labelMedium, color = Palette.Indigo)
                        Text(mission.task, style = MaterialTheme.typography.titleMedium)
                        Text("Я не скажу ответ сразу, но помогу до него дойти.", style = MaterialTheme.typography.bodySmall, color = Palette.InkSoft)
                    }
                }
            }
            items(state.messages) { msg -> Bubble(msg.text, mine = msg.role == ChatRole.USER) }
            if (state.sending) item { Bubble("…", mine = false) }
        }

        state.error?.let {
            Text(it, color = Palette.Coral, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(horizontal = 16.dp))
        }
        if (!state.sending) {
            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(QuickQuestions) { q ->
                    Text(
                        q,
                        style = MaterialTheme.typography.labelLarge,
                        color = Palette.Indigo,
                        modifier = Modifier
                            .clip(RoundedCornerShape(50))
                            .background(Palette.IndigoSoft)
                            .pressable { vm.send(q) }
                            .padding(horizontal = 14.dp, vertical = 8.dp),
                    )
                }
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            OutlinedTextField(
                value = input,
                onValueChange = { input = it },
                placeholder = { Text("Напиши, что непонятно", color = Palette.InkSoft) },
                shape = RoundedCornerShape(24.dp),
                maxLines = 4,
                colors = OutlinedTextFieldDefaults.colors(
                    unfocusedBorderColor = Palette.Line,
                    focusedBorderColor = Palette.Indigo,
                    unfocusedContainerColor = Palette.Surface,
                    focusedContainerColor = Palette.Surface,
                    cursorColor = Palette.Indigo,
                ),
                modifier = Modifier.weight(1f),
            )
            val canSend = input.isNotBlank() && !state.sending
            Box(
                Modifier
                    .size(52.dp)
                    .clip(CircleShape)
                    .background(if (canSend) PrimaryGradient else androidx.compose.ui.graphics.SolidColor(Palette.Line))
                    .pressable(enabled = canSend) {
                        vm.send(input)
                        input = ""
                    },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.AutoMirrored.Rounded.Send, contentDescription = "Отправить", tint = if (canSend) Color.White else Palette.InkSoft)
            }
        }
    }
}

@Composable
private fun Bubble(text: String, mine: Boolean) {
    val shape = RoundedCornerShape(
        topStart = 20.dp, topEnd = 20.dp,
        bottomStart = if (mine) 20.dp else 6.dp,
        bottomEnd = if (mine) 6.dp else 20.dp,
    )
    Box(Modifier.fillMaxWidth(), contentAlignment = if (mine) Alignment.CenterEnd else Alignment.CenterStart) {
        Text(
            text,
            style = MaterialTheme.typography.bodyLarge,
            color = if (mine) Color.White else Palette.Ink,
            modifier = Modifier
                .widthIn(max = 300.dp)
                .then(if (mine) Modifier else Modifier.shadow(4.dp, shape, ambientColor = Color(0x22343A8C), spotColor = Color(0x22343A8C)))
                .clip(shape)
                .then(if (mine) Modifier.background(PrimaryGradient) else Modifier.background(Palette.Surface))
                .padding(horizontal = 16.dp, vertical = 12.dp),
        )
    }
}
