package kg.aimentor.app

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
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.ChatBubble
import androidx.compose.material.icons.rounded.TaskAlt
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import android.app.Activity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

@Composable
fun LoginScreen(
    state: UiState,
    onGoogle: (idToken: String) -> Unit,
    onDev: () -> Unit,
    onError: (String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val googleConfigured = BuildConfig.GOOGLE_CLIENT_ID.isNotBlank()

    // на градиенте иконки статус-бара белые, на остальных экранах – тёмные
    val view = LocalView.current
    DisposableEffect(view) {
        val window = (view.context as? Activity)?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, view) }
        controller?.isAppearanceLightStatusBars = false
        onDispose { controller?.isAppearanceLightStatusBars = true }
    }

    Column(Modifier.fillMaxSize().background(HeroGradient)) {
        // верхняя часть: логотип и название на градиенте
        Column(
            Modifier.weight(1f).fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars).padding(24.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                Modifier.size(96.dp).clip(RoundedCornerShape(32.dp)).background(Color.White.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.AutoAwesome, contentDescription = null, tint = Color.White, modifier = Modifier.size(48.dp))
            }
            Spacer(Modifier.height(20.dp))
            Text("ИИ-ментор", style = MaterialTheme.typography.headlineLarge, color = Color.White)
            Text(
                "Программирование по 15 минут в день",
                style = MaterialTheme.typography.bodyLarge,
                color = Color.White.copy(alpha = 0.85f),
                textAlign = TextAlign.Center,
            )
        }

        // нижняя белая карточка с преимуществами и кнопкой входа
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp))
                .background(Palette.Surface)
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Feature(Icons.Rounded.Bolt, Palette.Amber, "Короткие уроки с простыми вопросами")
            Feature(Icons.Rounded.TaskAlt, Palette.Mint, "ИИ проверяет ответ за секунду")
            Feature(Icons.Rounded.ChatBubble, Palette.Indigo, "Ментор подскажет, если застрял")
            Spacer(Modifier.height(6.dp))

            if (googleConfigured) {
                PrimaryButton(
                    text = "Войти через Google",
                    onClick = {
                        scope.launch {
                            when (val result = signInWithGoogle(context, BuildConfig.GOOGLE_CLIENT_ID)) {
                                is GoogleSignInResult.Success -> onGoogle(result.idToken)
                                is GoogleSignInResult.Failed -> onError(result.message)
                                GoogleSignInResult.Cancelled -> Unit
                            }
                        }
                    },
                    loading = state.submitting,
                )
            }
            // Без Google Client ID (или в debug-сборке) можно войти по id устройства – сервер должен разрешать это (AUTH_DEV=true)
            if (BuildConfig.DEBUG || !googleConfigured) {
                if (googleConfigured) {
                    TonalButton("Без Google (для разработки)", onDev, enabled = !state.submitting, modifier = Modifier.fillMaxWidth())
                } else {
                    PrimaryButton(text = "Начать", onClick = onDev, loading = state.submitting)
                }
            }
            state.error?.let { Text(it, color = Palette.Coral, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center) }
        }
    }
}

@Composable
private fun Feature(icon: ImageVector, tint: Color, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(tint.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
        }
        Text(text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 12.dp))
    }
}
