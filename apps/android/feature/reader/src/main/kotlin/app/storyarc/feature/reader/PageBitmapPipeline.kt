package app.storyarc.feature.reader

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * A decoded page, cropped and — where the shader can't draw it live (D9) — sharpened,
 * ready to draw.
 *
 * The crop is cheap enough to stay on the composition thread: it detects its margin
 * from a 256-pixel thumbnail (`Bitmap.cropped`) and then makes one native crop call.
 * `Bitmap.sharpened` touches every pixel of the full page, so it runs on
 * `Dispatchers.Default` and the page keeps showing its unsharpened self until that
 * finishes — never a blank frame for it.
 */
@Composable
internal fun pageDisplayBitmap(bitmap: Bitmap, trims: Boolean, sharpness: Float): ImageBitmap {
    val cropped = remember(bitmap, trims) { bitmap.cropped(trims) }
    var sharpened by remember(cropped) { mutableStateOf<Bitmap?>(null) }
    val needsCpuSharpen = sharpness > 0f && !canSharpenWithShader
    LaunchedEffect(cropped, sharpness, needsCpuSharpen) {
        sharpened = if (needsCpuSharpen) {
            withContext(Dispatchers.Default) { cropped.sharpened(sharpness) }
        } else {
            null
        }
    }
    return remember(cropped, sharpened) { (sharpened ?: cropped).asImageBitmap() }
}
