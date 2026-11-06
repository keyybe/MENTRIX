package kg.aimentor.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.PhotoCamera
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.TaskAlt
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.automirrored.rounded.TrendingUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.launch

private val MinuteOptions = listOf(15, 20, 25, 30, 35, 40)
private val DayOptions = (3..7).toList()

private fun formatTime(minutes: Int) = "%02d:%02d".format(minutes / 60, minutes % 60)

// Какая настройка сейчас редактируется (открыт диалог или нижняя панель)
private enum class ProfileEdit { None, Goal, Minutes, Days, ReminderTime, Delete }

// ---------- Профиль (F8): привычное меню настроек ----------

@Composable
fun ProfileScreen(
    state: UiState,
    modifier: Modifier,
    onEditProfile: () -> Unit,
    onSaveSettings: (goal: String, minutesPerDay: Int, daysPerWeek: Int) -> Unit,
    onReminder: (minutes: Int?) -> Unit,
    onChangeArea: () -> Unit,
    onSignOut: () -> Unit,
    onDelete: () -> Unit,
) {
    val context = LocalContext.current
    val plan = state.plan
    val p = state.progress
    var editing by rememberSaveable { mutableStateOf(ProfileEdit.None) }
    var denied by rememberSaveable { mutableStateOf(false) }
    val reminderDefault = 19 * 60

    // с Android 13 на уведомления нужно разрешение
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        denied = !granted
        if (granted) onReminder(state.reminderMinutes ?: reminderDefault)
    }
    fun enableReminder() {
        val needsPermission = Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        if (needsPermission) permission.launch(Manifest.permission.POST_NOTIFICATIONS) else onReminder(reminderDefault)
    }
    fun save(goal: String = plan?.goal.orEmpty(), minutes: Int = plan?.minutesPerDay ?: 20, days: Int = plan?.daysPerWeek ?: 5) {
        onSaveSettings(goal, minutes, days)
    }
    val busy = state.submitting || state.offline

    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        // шапка: аватар, имя и кнопка редактирования
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.pressable(onClick = onEditProfile)) {
                UserAvatar(state.userName, state.avatarPath, size = 104.dp)
                Box(
                    Modifier
                        .align(Alignment.BottomEnd)
                        .size(34.dp)
                        .clip(CircleShape)
                        .background(Palette.Surface)
                        .border(2.dp, Palette.Background, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.PhotoCamera, contentDescription = "Изменить фото", tint = Palette.Indigo, modifier = Modifier.size(18.dp))
                }
            }
            Text(state.userName ?: "Ученик", style = MaterialTheme.typography.headlineSmall)
            plan?.let {
                Text(
                    "${it.area.title} · ${if (it.level == kg.aimentor.shared.Level.BEGINNER) "новичок" else "знаю основы"}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Palette.InkSoft,
                )
            }
            TonalButton("Редактировать профиль", onEditProfile, icon = Icons.Rounded.Edit)
        }

        // статистика
        p?.let {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile(Icons.Rounded.LocalFireDepartment, Palette.Amber, "${it.streak}", "дней подряд", Modifier.weight(1f))
                StatTile(Icons.Rounded.TaskAlt, Palette.Mint, "${it.doneMissions}", "уроков", Modifier.weight(1f))
                StatTile(
                    Icons.AutoMirrored.Rounded.TrendingUp, Palette.Indigo,
                    "${if (it.totalMissions == 0) 0 else it.doneMissions * 100 / it.totalMissions}%", "плана",
                    Modifier.weight(1f),
                )
            }
        }

        if (plan != null) {
            Section("Обучение") {
                SettingRow(plan.area.icon, Palette.Sky, "Направление", plan.area.title, enabled = !state.offline, onClick = onChangeArea)
                Divider()
                SettingRow(Icons.Rounded.Flag, Palette.Coral, "Цель", plan.goal, enabled = !busy) { editing = ProfileEdit.Goal }
                Divider()
                SettingRow(Icons.Rounded.Timer, Palette.Mint, "Время в день", "${plan.minutesPerDay} мин", enabled = !busy) { editing = ProfileEdit.Minutes }
                Divider()
                SettingRow(Icons.Rounded.CalendarMonth, Palette.Indigo, "Дней в неделю", "${plan.daysPerWeek}", enabled = !busy) { editing = ProfileEdit.Days }
                p?.gaps?.takeIf { it.isNotEmpty() }?.let { gaps ->
                    Divider()
                    SettingRow(Icons.Rounded.Replay, Palette.Amber, "Темы на повторение", gaps.joinToString(", "), onClick = null)
                }
            }
        }

        Section("Уведомления") {
            SettingRow(
                Icons.Rounded.Notifications, Palette.Amber, "Напоминание о занятии",
                if (state.reminderMinutes != null) "Каждый день" else "Выключено",
                trailing = {
                    Switch(
                        checked = state.reminderMinutes != null,
                        onCheckedChange = { on -> if (on) enableReminder() else onReminder(null) },
                        colors = SwitchDefaults.colors(checkedTrackColor = Palette.Indigo, uncheckedBorderColor = Palette.Line, uncheckedTrackColor = Palette.Background),
                    )
                },
            ) { if (state.reminderMinutes == null) enableReminder() else onReminder(null) }
            state.reminderMinutes?.let { minutes ->
                Divider()
                SettingRow(Icons.Rounded.Schedule, Palette.Sky, "Время", formatTime(minutes)) { editing = ProfileEdit.ReminderTime }
            }
            if (denied) {
                Text(
                    "Без разрешения на уведомления напоминания не придут. Разреши их в настройках телефона.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Palette.Coral,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }

        Section("Аккаунт") {
            SettingRow(Icons.AutoMirrored.Rounded.Logout, Palette.InkSoft, "Выйти", null, onClick = onSignOut)
            Divider()
            SettingRow(Icons.Rounded.DeleteOutline, Palette.Coral, "Удалить аккаунт", null, titleColor = Palette.Coral, enabled = !state.offline) {
                editing = ProfileEdit.Delete
            }
        }

        Text(
            "ИИ-ментор · версия ${BuildConfig.VERSION_NAME}",
            style = MaterialTheme.typography.bodySmall,
            color = Palette.InkSoft,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(4.dp))
    }

    // ---------- диалоги и нижние панели ----------
    val close = { editing = ProfileEdit.None }
    when (editing) {
        ProfileEdit.Goal -> plan?.let { GoalDialog(it.goal, onDismiss = close) { goal -> save(goal = goal); close() } }
        ProfileEdit.Minutes -> plan?.let {
            OptionsSheet("Время в день", MinuteOptions, it.minutesPerDay, { m -> "$m минут" }, onDismiss = close) { m -> save(minutes = m); close() }
        }
        ProfileEdit.Days -> plan?.let {
            OptionsSheet("Дней в неделю", DayOptions, it.daysPerWeek, { d -> "$d ${dayWord(d)} в неделю" }, onDismiss = close) { d -> save(days = d); close() }
        }
        ProfileEdit.ReminderTime -> ReminderTimeDialog(state.reminderMinutes ?: reminderDefault, onDismiss = close) { m -> onReminder(m); close() }
        ProfileEdit.Delete -> AlertDialog(
            onDismissRequest = close,
            containerColor = Palette.Surface,
            title = { Text("Удалить аккаунт?") },
            text = { Text("План, прогресс и серия будут удалены без возможности восстановления.") },
            confirmButton = { TextButton(onClick = { close(); onDelete() }) { Text("Удалить", color = Palette.Coral) } },
            dismissButton = { TextButton(onClick = close) { Text("Отмена", color = Palette.Ink) } },
        )
        ProfileEdit.None -> Unit
    }
}

private fun dayWord(n: Int) = if (n in 2..4) "дня" else "дней"

@Composable
private fun StatTile(icon: ImageVector, tint: Color, value: String, label: String, modifier: Modifier = Modifier) {
    SoftCard(modifier = modifier) {
        Column(Modifier.fillMaxWidth().padding(vertical = 14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(22.dp))
            Text(value, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 4.dp))
            Text(label, style = MaterialTheme.typography.bodySmall, color = Palette.InkSoft)
        }
    }
}

// Группа настроек с заголовком, как в системных «Настройках»
@Composable
private fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.labelLarge, color = Palette.InkSoft, modifier = Modifier.padding(start = 4.dp))
        SoftCard(modifier = Modifier.fillMaxWidth()) { Column(Modifier.padding(vertical = 4.dp), content = content) }
    }
}

@Composable
private fun Divider() {
    Box(Modifier.fillMaxWidth().padding(start = 68.dp, end = 16.dp).height(1.dp).background(Palette.Line))
}

// Строка настройки: иконка, название, текущее значение и стрелка (или свой элемент справа)
@Composable
private fun SettingRow(
    icon: ImageVector,
    tint: Color,
    title: String,
    value: String?,
    titleColor: Color = Palette.Ink,
    enabled: Boolean = true,
    trailing: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)?,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.pressable(enabled = enabled, onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        IconTile(icon, if (enabled) tint else Palette.InkSoft, (if (enabled) tint else Palette.InkSoft).copy(alpha = 0.12f), size = 38.dp)
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall, color = if (enabled) titleColor else Palette.InkSoft)
            value?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = Palette.InkSoft, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
        when {
            trailing != null -> trailing()
            onClick != null -> Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = Palette.InkSoft)
        }
    }
}

@Composable
private fun GoalDialog(current: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var goal by rememberSaveable { mutableStateOf(current) }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Palette.Surface,
        title = { Text("Твоя цель") },
        text = { AppTextField(value = goal, onValueChange = { goal = it }, placeholder = "Например, найти первую работу", singleLine = true) },
        confirmButton = {
            TextButton(onClick = { onSave(goal.trim()) }, enabled = goal.isNotBlank() && goal.trim() != current) {
                Text("Сохранить", color = if (goal.isNotBlank()) Palette.Indigo else Palette.InkSoft)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена", color = Palette.Ink) } },
    )
}

// Нижняя панель со списком вариантов, выбранный отмечен галочкой
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T> OptionsSheet(
    title: String,
    options: List<T>,
    selected: T,
    label: (T) -> String,
    onDismiss: () -> Unit,
    onPick: (T) -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Palette.Surface,
    ) {
        Column(Modifier.navigationBarsPadding().padding(bottom = 12.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
            options.forEach { option ->
                val isSelected = option == selected
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(if (isSelected) Palette.IndigoSoft else Color.Transparent)
                        .pressable { if (!isSelected) onPick(option) else onDismiss() }
                        .padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        label(option),
                        style = MaterialTheme.typography.bodyLarge,
                        color = if (isSelected) Palette.Indigo else Palette.Ink,
                        modifier = Modifier.weight(1f),
                    )
                    if (isSelected) Icon(Icons.Rounded.Check, contentDescription = "Выбрано", tint = Palette.Indigo)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReminderTimeDialog(current: Int, onDismiss: () -> Unit, onSave: (Int) -> Unit) {
    val picker = rememberTimePickerState(initialHour = current / 60, initialMinute = current % 60, is24Hour = true)
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Palette.Surface,
        title = { Text("Время напоминания") },
        text = {
            TimePicker(
                state = picker,
                colors = TimePickerDefaults.colors(
                    clockDialColor = Palette.Background,
                    selectorColor = Palette.Indigo,
                    timeSelectorSelectedContainerColor = Palette.IndigoSoft,
                    timeSelectorSelectedContentColor = Palette.Indigo,
                    timeSelectorUnselectedContainerColor = Palette.Background,
                ),
            )
        },
        confirmButton = { TextButton(onClick = { onSave(picker.hour * 60 + picker.minute) }) { Text("Готово", color = Palette.Indigo) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена", color = Palette.Ink) } },
    )
}

// ---------- Редактирование профиля: фото и имя ----------

@Composable
fun EditProfileScreen(
    state: UiState,
    onSaveName: (String) -> Unit,
    onAvatar: (String?) -> Unit,
    onAvatarError: () -> Unit,
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var name by rememberSaveable { mutableStateOf(state.userName.orEmpty()) }
    var processing by rememberSaveable { mutableStateOf(false) }

    // системный выбор фото: разрешение на доступ к галерее не нужно
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) {
            processing = true
            scope.launch {
                runCatching { AvatarStore.save(context, uri) }
                    .onSuccess(onAvatar)
                    .onFailure { onAvatarError() }
                processing = false
            }
        }
    }
    val pickPhoto = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }

    Column(
        Modifier
            .fillMaxSize()
            .background(Palette.Background)
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .imePadding(),
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Назад", tint = Palette.Ink) }
            Text("Редактировать профиль", style = MaterialTheme.typography.titleLarge)
        }

        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.pressable(enabled = !processing, onClick = pickPhoto)) {
                UserAvatar(name.ifBlank { null }, state.avatarPath, size = 128.dp)
                if (processing) {
                    Box(Modifier.size(128.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.35f)), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color.White, modifier = Modifier.size(32.dp), strokeWidth = 3.dp)
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TonalButton(if (state.avatarPath == null) "Добавить фото" else "Изменить фото", pickPhoto, icon = Icons.Rounded.PhotoCamera, enabled = !processing)
                if (state.avatarPath != null) {
                    TonalButton(
                        "Удалить", { onAvatar(null) },
                        icon = Icons.Rounded.DeleteOutline,
                        color = Palette.Coral, background = Palette.CoralSoft,
                        enabled = !processing,
                    )
                }
            }

            Spacer(Modifier.height(4.dp))
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Имя", style = MaterialTheme.typography.labelLarge, color = Palette.InkSoft, modifier = Modifier.padding(start = 4.dp))
                AppTextField(value = name, onValueChange = { if (it.length <= 40) name = it }, placeholder = "Как к тебе обращаться?", singleLine = true)
                Text(
                    "Имя и фото хранятся только на этом устройстве и используются в приветствии.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Palette.InkSoft,
                    modifier = Modifier.padding(start = 4.dp),
                )
            }
        }

        PrimaryButton(
            text = "Сохранить",
            onClick = {
                onSaveName(name)
                onClose()
            },
            enabled = name.trim() != state.userName.orEmpty() && !processing,
            modifier = Modifier.padding(20.dp),
        )
    }
}
