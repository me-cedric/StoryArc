package app.storyarc.feature.epubreader

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import app.storyarc.core.model.ReaderTypeface

/**
 * The bundled typefaces, in front of Compose's own text stack.
 *
 * [FontDeclarations] puts them in front of Readium's web view, and that is all the
 * *page* needs. Nothing puts them in front of Compose — so a typeface picker asking
 * for a family Compose has never heard of would silently draw in the default font,
 * which is exactly the failure a typeface picker must not have.
 *
 * The files come from the same staged assets the navigator is served from, so the
 * specimen and the page can only ever show the same face.
 */
@Composable
internal fun ReaderTypeface.fontFamily(): FontFamily {
    val assets = LocalContext.current.assets
    val stem = fileStem

    return remember(this) {
        when {
            // The publisher's own, and the two CSS generics. Compose has its own
            // words for the last two; the first has nothing to show but the default.
            stem == null -> when (this) {
                ReaderTypeface.SERIF -> FontFamily.Serif
                ReaderTypeface.SANS -> FontFamily.SansSerif
                else -> FontFamily.Default
            }
            // Four statics or two variables, told apart by what is actually there.
            // Asking for a file the build did not produce is a crash at first draw,
            // and the difference is a property of the family rather than of this
            // call site.
            else -> FontFamily(
                listOfNotNull(
                    asset(assets, "$stem.ttf", FontWeight.Normal, FontStyle.Normal)
                        ?: asset(assets, "$stem-Regular.ttf", FontWeight.Normal, FontStyle.Normal),
                    asset(assets, "$stem-Italic.ttf", FontWeight.Normal, FontStyle.Italic),
                    asset(assets, "$stem-Bold.ttf", FontWeight.Bold, FontStyle.Normal),
                    asset(assets, "$stem-BoldItalic.ttf", FontWeight.Bold, FontStyle.Italic),
                ),
            )
        }
    }
}

private fun asset(
    assets: android.content.res.AssetManager,
    name: String,
    weight: FontWeight,
    style: FontStyle,
): Font? = runCatching {
    assets.open("fonts/$name").close()
    Font(path = "fonts/$name", assetManager = assets, weight = weight, style = style)
}.getOrNull()
