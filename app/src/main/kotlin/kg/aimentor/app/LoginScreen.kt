package kg.aimentor.app

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Mail
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import kotlinx.coroutines.launch

@Composable
fun LoginScreen(
    state: UiState,
    onLogin: (email: String, pass: String) -> Unit,
    onRegister: (name: String, email: String, pass: String) -> Unit,
    onGoogle: (idToken: String, name: String?) -> Unit,
    onDev: () -> Unit,
    onError: (String) -> Unit,
    onClearError: () -> Unit = {},
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val googleConfigured = BuildConfig.GOOGLE_CLIENT_ID.isNotBlank()

    var isRegister by rememberSaveable { mutableStateOf(false) }
    var name by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var passwordVisible by rememberSaveable { mutableStateOf(false) }

    // на градиенте иконки статус-бара белые, на остальных экранах – тёмные
    val view = LocalView.current
    DisposableEffect(view) {
        val window = (view.context as? Activity)?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, view) }
        controller?.isAppearanceLightStatusBars = false
        onDispose { controller?.isAppearanceLightStatusBars = true }
    }

    val submit = {
        if (isRegister) {
            val trimmedName = name.trim()
            val trimmedEmail = email.trim()
            when {
                trimmedName.isEmpty() -> onError("Укажи имя")
                trimmedEmail.isEmpty() -> onError("Укажи email")
                password.length < 8 -> onError("Пароль должен быть не короче 8 символов")
                else -> onRegister(trimmedName, trimmedEmail, password)
            }
        } else {
            val trimmedEmail = email.trim()
            when {
                trimmedEmail.isEmpty() -> onError("Укажи email")
                password.isEmpty() -> onError("Укажи пароль")
                else -> onLogin(trimmedEmail, password)
            }
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(HeroGradient)
            .verticalScroll(rememberScrollState())
            .imePadding()
    ) {
        // верхняя часть: логотип и название на градиенте
        Column(
            Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(horizontal = 24.dp, vertical = 32.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                Modifier.size(88.dp).clip(RoundedCornerShape(28.dp)).background(Color.White.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.AutoAwesome, contentDescription = null, tint = Color.White, modifier = Modifier.size(44.dp))
            }
            Spacer(Modifier.height(16.dp))
            Text("ИИ-ментор", style = MaterialTheme.typography.headlineLarge, color = Color.White)
            Text(
                "Программирование по 15 минут в день",
                style = MaterialTheme.typography.bodyLarge,
                color = Color.White.copy(alpha = 0.85f),
                textAlign = TextAlign.Center,
            )
        }

        // нижняя белая карточка с переключением Вход/Регистрация и формой
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp))
                .background(Palette.Surface)
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            // Переключатель «Вход» / «Регистрация»
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(Palette.Background)
                    .padding(4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Box(
                    Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(10.dp))
                        .background(if (!isRegister) Palette.Surface else Color.Transparent)
                        .clickable {
                            if (isRegister) {
                                isRegister = false
                                onClearError()
                            }
                        }
                        .padding(vertical = 10.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "Вход",
                        style = MaterialTheme.typography.titleSmall,
                        color = if (!isRegister) Palette.Indigo else Palette.InkSoft,
                    )
                }
                Box(
                    Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(10.dp))
                        .background(if (isRegister) Palette.Surface else Color.Transparent)
                        .clickable {
                            if (!isRegister) {
                                isRegister = true
                                onClearError()
                            }
                        }
                        .padding(vertical = 10.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "Регистрация",
                        style = MaterialTheme.typography.titleSmall,
                        color = if (isRegister) Palette.Indigo else Palette.InkSoft,
                    )
                }
            }

            if (isRegister) {
                AppTextField(
                    value = name,
                    onValueChange = { name = it; onClearError() },
                    placeholder = "Твоё имя",
                    singleLine = true,
                    leadingIcon = { Icon(Icons.Rounded.Person, contentDescription = null, tint = Palette.InkSoft) },
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Words,
                        imeAction = ImeAction.Next,
                    ),
                )
            }

            AppTextField(
                value = email,
                onValueChange = { email = it; onClearError() },
                placeholder = "Email",
                singleLine = true,
                leadingIcon = { Icon(Icons.Rounded.Mail, contentDescription = null, tint = Palette.InkSoft) },
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Email,
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    imeAction = ImeAction.Next,
                ),
            )

            AppTextField(
                value = password,
                onValueChange = { password = it; onClearError() },
                placeholder = if (isRegister) "Пароль (от 8 символов)" else "Пароль",
                singleLine = true,
                leadingIcon = { Icon(Icons.Rounded.Lock, contentDescription = null, tint = Palette.InkSoft) },
                trailingIcon = {
                    IconButton(onClick = { passwordVisible = !passwordVisible }) {
                        Icon(
                            imageVector = if (passwordVisible) Icons.Rounded.VisibilityOff else Icons.Rounded.Visibility,
                            contentDescription = if (passwordVisible) "Скрыть пароль" else "Показать пароль",
                            tint = Palette.InkSoft,
                        )
                    }
                },
                visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done,
                ),
            )

            PrimaryButton(
                text = if (isRegister) "Создать аккаунт" else "Войти",
                onClick = submit,
                loading = state.submitting,
            )

            state.error?.let {
                Text(
                    it,
                    color = Palette.Coral,
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            if (googleConfigured || BuildConfig.DEBUG) {
                Row(
                    Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.weight(1f).height(1.dp).background(Palette.Line))
                    Text(
                        "или",
                        style = MaterialTheme.typography.bodySmall,
                        color = Palette.InkSoft,
                        modifier = Modifier.padding(horizontal = 12.dp),
                    )
                    Box(Modifier.weight(1f).height(1.dp).background(Palette.Line))
                }
            }

            if (googleConfigured) {
                TonalButton(
                    text = "Войти через Google",
                    onClick = {
                        scope.launch {
                            when (val result = signInWithGoogle(context, BuildConfig.GOOGLE_CLIENT_ID)) {
                                is GoogleSignInResult.Success -> onGoogle(result.idToken, result.name)
                                is GoogleSignInResult.Failed -> onError(result.message)
                                GoogleSignInResult.Cancelled -> Unit
                            }
                        }
                    },
                    enabled = !state.submitting,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            if (BuildConfig.DEBUG || !googleConfigured) {
                TonalButton(
                    text = "Без аккаунта (для разработки)",
                    onClick = onDev,
                    enabled = !state.submitting,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}
