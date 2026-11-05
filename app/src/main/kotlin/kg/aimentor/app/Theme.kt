package kg.aimentor.app

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.googlefonts.Font
import androidx.compose.ui.text.googlefonts.GoogleFont
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// ---------- Цвета ----------

object Palette {
    val Indigo = Color(0xFF5B5BF6)       // основной
    val Violet = Color(0xFF9B5CF6)       // второй цвет градиента
    val IndigoSoft = Color(0xFFEEEEFE)   // тонированный фон основного
    val IndigoDeep = Color(0xFF3F3DC8)
    val Mint = Color(0xFF12B5A0)         // успех
    val MintSoft = Color(0xFFE3F7F3)
    val Amber = Color(0xFFF59E0B)        // серия занятий
    val AmberSoft = Color(0xFFFEF3DC)
    val Coral = Color(0xFFF2545B)        // ошибки
    val CoralSoft = Color(0xFFFDECEC)
    val Sky = Color(0xFF3B9EF5)
    val SkySoft = Color(0xFFE6F2FE)
    val Ink = Color(0xFF14152B)          // основной текст
    val InkSoft = Color(0xFF6B6F86)      // второстепенный текст
    val Line = Color(0xFFE7E8F0)         // рамки
    val Background = Color(0xFFF6F6FB)
    val Surface = Color(0xFFFFFFFF)
}

val PrimaryGradient = Brush.linearGradient(listOf(Palette.Indigo, Palette.Violet))
val HeroGradient = Brush.linearGradient(listOf(Color(0xFF4F46E5), Color(0xFF8B5CF6), Color(0xFFC06CF0)))

private val LightColors = lightColorScheme(
    primary = Palette.Indigo,
    onPrimary = Color.White,
    primaryContainer = Palette.IndigoSoft,
    onPrimaryContainer = Palette.IndigoDeep,
    secondary = Palette.Mint,
    onSecondary = Color.White,
    tertiary = Palette.Amber,
    background = Palette.Background,
    onBackground = Palette.Ink,
    surface = Palette.Surface,
    onSurface = Palette.Ink,
    surfaceVariant = Palette.Background,
    onSurfaceVariant = Palette.InkSoft,
    surfaceContainer = Palette.Surface,
    surfaceContainerHigh = Palette.Surface,
    outline = Palette.Line,
    error = Palette.Coral,
    errorContainer = Palette.CoralSoft,
)

// ---------- Шрифт ----------

// Manrope – современный геометрический шрифт с хорошей кириллицей. Загружается через Google Fonts
// (сервисы Google Play), а если их нет – Compose возьмёт системный шрифт.
private val fontProvider = GoogleFont.Provider(
    providerAuthority = "com.google.android.gms.fonts",
    providerPackage = "com.google.android.gms",
    certificates = R.array.com_google_android_gms_fonts_certs,
)

private val manrope = GoogleFont("Manrope")

val Manrope = FontFamily(
    Font(manrope, fontProvider, FontWeight.Normal),
    Font(manrope, fontProvider, FontWeight.Medium),
    Font(manrope, fontProvider, FontWeight.SemiBold),
    Font(manrope, fontProvider, FontWeight.Bold),
    Font(manrope, fontProvider, FontWeight.ExtraBold),
)

private val AppTypography: Typography = Typography().run {
    fun TextStyle.m(weight: FontWeight, size: Int? = null, spacing: Float = 0f) = copy(
        fontFamily = Manrope,
        fontWeight = weight,
        fontSize = size?.sp ?: fontSize,
        letterSpacing = spacing.sp,
    )
    copy(
        headlineLarge = headlineLarge.m(FontWeight.ExtraBold, 32, -0.5f),
        headlineMedium = headlineMedium.m(FontWeight.ExtraBold, 26, -0.4f),
        headlineSmall = headlineSmall.m(FontWeight.Bold, 22, -0.3f),
        titleLarge = titleLarge.m(FontWeight.Bold, 20, -0.2f),
        titleMedium = titleMedium.m(FontWeight.Bold, 16),
        titleSmall = titleSmall.m(FontWeight.SemiBold, 14),
        bodyLarge = bodyLarge.m(FontWeight.Medium, 16).copy(lineHeight = 24.sp),
        bodyMedium = bodyMedium.m(FontWeight.Medium, 14).copy(lineHeight = 20.sp),
        bodySmall = bodySmall.m(FontWeight.Medium, 12),
        labelLarge = labelLarge.m(FontWeight.SemiBold, 15),
        labelMedium = labelMedium.m(FontWeight.SemiBold, 12),
        labelSmall = labelSmall.m(FontWeight.SemiBold, 11),
    )
}

@Composable
fun MentorTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = LightColors, typography = AppTypography, content = content)
}

// ---------- Кнопки ----------

private val PillShape = RoundedCornerShape(18.dp)

// Нажатие слегка «утапливает» элемент
@Composable
private fun pressScale(interaction: MutableInteractionSource): Float {
    val pressed by interaction.collectIsPressedAsState()
    return animateFloatAsState(if (pressed) 0.97f else 1f, label = "press").value
}

// Главная кнопка: градиентная «капсула»
@Composable
fun PrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    loading: Boolean = false,
    icon: ImageVector? = null,
    brush: Brush = PrimaryGradient,
) {
    val interaction = remember { MutableInteractionSource() }
    val scale = pressScale(interaction)
    val active = enabled && !loading
    Box(
        modifier
            .fillMaxWidth()
            .height(56.dp)
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .then(if (enabled) Modifier.shadow(10.dp, PillShape, ambientColor = Palette.Indigo, spotColor = Palette.Indigo) else Modifier)
            .clip(PillShape)
            .then(if (enabled) Modifier.background(brush) else Modifier.background(Palette.Line))
            .clickable(interactionSource = interaction, indication = null, enabled = active, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        val color = if (enabled) Color.White else Palette.InkSoft
        if (loading) {
            CircularProgressIndicator(Modifier.size(22.dp), color = color, strokeWidth = 2.5.dp)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                icon?.let { Icon(it, contentDescription = null, tint = color, modifier = Modifier.size(20.dp).padding(end = 0.dp)) }
                if (icon != null) Box(Modifier.width(8.dp))
                Text(text, color = color, style = MaterialTheme.typography.titleMedium)
            }
        }
    }
}

// Тонированная кнопка для второстепенных действий
@Composable
fun TonalButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    color: Color = Palette.Indigo,
    background: Color = Palette.IndigoSoft,
    enabled: Boolean = true,
) {
    val interaction = remember { MutableInteractionSource() }
    val scale = pressScale(interaction)
    val tint = if (enabled) color else Palette.InkSoft
    Row(
        modifier
            .height(48.dp)
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .clip(RoundedCornerShape(14.dp))
            .background(if (enabled) background else Palette.Background)
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
    ) {
        icon?.let {
            Icon(it, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
            Box(Modifier.width(8.dp))
        }
        Text(text, color = tint, style = MaterialTheme.typography.labelLarge)
    }
}

// ---------- Карточки ----------

private val CardShape = RoundedCornerShape(22.dp)

// Белая «парящая» карточка с мягкой тенью. selected – выбранный вариант (рамка основного цвета).
@Composable
fun SoftCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    selected: Boolean = false,
    color: Color = Palette.Surface,
    content: @Composable ColumnScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val scale = if (onClick != null) pressScale(interaction) else 1f
    Column(
        modifier
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .shadow(if (selected) 0.dp else 6.dp, CardShape, ambientColor = Color(0x22343A8C), spotColor = Color(0x22343A8C))
            .clip(CardShape)
            .background(if (selected) Palette.IndigoSoft else color)
            .then(if (selected) Modifier.border(BorderStroke(2.dp, Palette.Indigo), CardShape) else Modifier)
            .then(
                if (onClick != null) Modifier.clickable(interactionSource = interaction, indication = null, onClick = onClick)
                else Modifier
            ),
        content = content,
    )
}

// Иконка в скруглённом квадрате с тонированным фоном
@Composable
fun IconTile(icon: ImageVector, tint: Color, background: Color, modifier: Modifier = Modifier, size: Dp = 44.dp) {
    Box(
        modifier.size(size).clip(RoundedCornerShape(size * 0.32f)).background(background),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(size * 0.5f))
    }
}

// Круглый аватар с градиентом
@Composable
fun GradientAvatar(modifier: Modifier = Modifier, size: Dp = 48.dp, content: @Composable BoxScope.() -> Unit) {
    Box(
        modifier.size(size).clip(RoundedCornerShape(50)).background(PrimaryGradient),
        contentAlignment = Alignment.Center,
        content = content,
    )
}

// ---------- Прогресс ----------

@Composable
fun SlimProgress(progress: Float, modifier: Modifier = Modifier, track: Color = Palette.Line, brush: Brush = PrimaryGradient, height: Dp = 8.dp) {
    val animated by animateFloatAsState(progress.coerceIn(0f, 1f), label = "progress")
    Box(modifier.fillMaxWidth().height(height).clip(RoundedCornerShape(50)).background(track)) {
        Box(Modifier.fillMaxWidth(animated).fillMaxHeight().clip(RoundedCornerShape(50)).background(brush))
    }
}

// Кольцо прогресса с подписью в центре
@Composable
fun ProgressRing(
    progress: Float,
    modifier: Modifier = Modifier,
    size: Dp = 72.dp,
    stroke: Dp = 8.dp,
    track: Color = Color.White.copy(alpha = 0.25f),
    color: Color = Color.White,
    content: @Composable BoxScope.() -> Unit = {},
) {
    val animated by animateFloatAsState(progress.coerceIn(0f, 1f), label = "ring")
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size)) {
            val w = stroke.toPx()
            val arc = Size(this.size.width - w, this.size.height - w)
            val topLeft = Offset(w / 2, w / 2)
            drawArc(track, -90f, 360f, false, topLeft, arc, style = Stroke(w, cap = StrokeCap.Round))
            drawArc(color, -90f, 360f * animated, false, topLeft, arc, style = Stroke(w, cap = StrokeCap.Round))
        }
        content()
    }
}

// Небольшая «пилюля» с иконкой и текстом
@Composable
fun InfoPill(icon: ImageVector, text: String, tint: Color, background: Color, modifier: Modifier = Modifier) {
    Row(
        modifier.clip(RoundedCornerShape(50)).background(background).padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(16.dp))
        Box(Modifier.width(4.dp))
        Text(text, color = tint, style = MaterialTheme.typography.labelMedium)
    }
}

// Нажимаемая область с эффектом «утапливания», без ряби
@Composable
fun Modifier.pressable(enabled: Boolean = true, onClick: () -> Unit): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val scale = pressScale(interaction)
    return this
        .graphicsLayer { scaleX = scale; scaleY = scale }
        .clickable(interactionSource = interaction, indication = null, enabled = enabled, onClick = onClick)
}
