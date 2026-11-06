package kg.aimentor.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import androidx.core.graphics.scale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

// Фото профиля хранится только на устройстве: в папке приложения, уменьшенное до 512×512.
object AvatarStore {
    private const val SIZE = 512

    // Возвращает путь к сохранённому файлу. Имя каждый раз новое, чтобы картинка обновилась на экране.
    suspend fun save(context: Context, uri: Uri): String = withContext(Dispatchers.IO) {
        val source = decode(context, uri)
        val side = minOf(source.width, source.height)
        val square = Bitmap.createBitmap(source, (source.width - side) / 2, (source.height - side) / 2, side, side)
        val scaled = square.scale(SIZE, SIZE)
        val file = File(context.filesDir, "avatar_${System.currentTimeMillis()}.jpg")
        file.outputStream().use { scaled.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        file.absolutePath
    }

    fun delete(path: String?) {
        path?.let { runCatching { File(it).delete() } }
    }

    private fun decode(context: Context, uri: Uri): Bitmap =
        if (Build.VERSION.SDK_INT >= 28) {
            // ImageDecoder сам учитывает поворот снимка из EXIF и сразу уменьшает большое фото
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
                val longest = maxOf(info.size.width, info.size.height)
                if (longest > SIZE * 2) {
                    val k = SIZE * 2f / longest
                    decoder.setTargetSize((info.size.width * k).toInt(), (info.size.height * k).toInt())
                }
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        } else {
            context.contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it) }
                ?: error("Не удалось прочитать изображение")
        }
}

// Аватар: фото, если оно есть, иначе первая буква имени на градиенте
@Composable
fun UserAvatar(name: String?, path: String?, size: Dp, modifier: Modifier = Modifier) {
    val bitmap by produceState<ImageBitmap?>(initialValue = null, path) {
        value = path?.let { p ->
            withContext(Dispatchers.IO) { runCatching { BitmapFactory.decodeFile(p)?.asImageBitmap() }.getOrNull() }
        }
    }
    Box(
        modifier.size(size).clip(CircleShape).background(PrimaryGradient),
        contentAlignment = Alignment.Center,
    ) {
        val image = bitmap
        if (image != null) {
            Image(image, contentDescription = "Фото профиля", contentScale = ContentScale.Crop, modifier = Modifier.size(size))
        } else {
            Text(
                name?.trim()?.firstOrNull()?.uppercase() ?: "🙂",
                color = Color.White,
                fontFamily = Manrope,
                fontWeight = FontWeight.ExtraBold,
                fontSize = (size.value * 0.42f).sp,
            )
        }
    }
}
