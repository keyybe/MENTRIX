package kg.aimentor.app

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Timeline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel

@Composable
fun MentorApp(vm: MentorViewModel = viewModel(factory = MentorViewModel.Factory)) {
    val state by vm.state.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(state.notice) {
        state.notice?.let {
            snackbar.showSnackbar(it)
            vm.consumeNotice()
        }
    }

    MentorTheme {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Box(Modifier.fillMaxSize()) {
                when {
                    !state.signedIn ->
                        LoginScreen(state, onGoogle = vm::loginWithGoogle, onDev = vm::loginDev, onError = vm::loginFailed)

                    state.loading && state.plan == null ->
                        Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = Palette.Indigo) }

                    !state.hasProfile || state.changingArea ->
                        OnboardingScreen(
                            state,
                            onCreate = vm::createProfile,
                            onRetry = vm::load,
                            onCancel = if (state.changingArea) vm::cancelChangeArea else null,
                        )

                    else -> MainScaffold(state, vm)
                }
                SnackbarHost(
                    snackbar,
                    Modifier
                        .align(Alignment.BottomCenter)
                        .windowInsetsPadding(WindowInsets.safeDrawing)
                        .padding(bottom = 96.dp),
                )
            }
        }
    }
}

private val Tabs: List<Pair<ImageVector, String>> = listOf(
    Icons.Rounded.Home to "Сегодня",
    Icons.Rounded.Timeline to "План",
    Icons.Rounded.Person to "Профиль",
)

@Composable
private fun MainScaffold(state: UiState, vm: MentorViewModel) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var chatOpen by rememberSaveable { mutableStateOf(false) }
    val mission = state.today?.mission

    // Чат открывается поверх вкладок и закрывается системной кнопкой «Назад»
    BackHandler(enabled = chatOpen) { chatOpen = false }
    if (chatOpen && mission != null) {
        val chatVm: ChatViewModel = viewModel(factory = ChatViewModel.Factory)
        LaunchedEffect(mission.id) { chatVm.open(mission.id) }
        ChatScreen(chatVm, mission, onClose = { chatOpen = false })
        return
    }

    Scaffold(
        containerColor = Palette.Background,
        bottomBar = {
            NavigationBar(
                containerColor = Palette.Surface,
                tonalElevation = 0.dp,
                modifier = Modifier.shadow(16.dp, ambientColor = Palette.Indigo.copy(alpha = 0.2f), spotColor = Palette.Indigo.copy(alpha = 0.2f)),
            ) {
                Tabs.forEachIndexed { i, (icon, label) ->
                    NavigationBarItem(
                        selected = tab == i,
                        onClick = { tab = i },
                        icon = { Icon(icon, contentDescription = label) },
                        label = { Text(label, style = MaterialTheme.typography.labelMedium) },
                        colors = NavigationBarItemDefaults.colors(
                            indicatorColor = Palette.IndigoSoft,
                            selectedIconColor = Palette.Indigo,
                            selectedTextColor = Palette.Indigo,
                            unselectedIconColor = Palette.InkSoft,
                            unselectedTextColor = Palette.InkSoft,
                        ),
                    )
                }
            }
        },
    ) { padding ->
        val mod = Modifier.padding(padding).consumeWindowInsets(padding)
        when (tab) {
            0 -> TodayScreen(
                state, mod,
                onSubmit = vm::submitAnswer,
                onNext = vm::next,
                onAskMentor = { chatOpen = true },
                onRetry = vm::load,
            )
            1 -> PlanScreen(state, mod, onStart = { tab = 0 })
            2 -> ProfileScreen(
                state, mod,
                onSaveSettings = vm::saveSettings,
                onReminder = vm::setReminder,
                onChangeArea = vm::startChangeArea,
                onSignOut = { vm.signOut() },
                onDelete = vm::deleteAccount,
            )
        }
    }
}
