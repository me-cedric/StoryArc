package app.storyarc.feature.settings

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.AppIconChoice

/**
 * The side of one chooser tile.
 *
 * `settings-and-about` asks each option to be shown "as the icon it actually is, at the size a
 * home screen draws it", and the plan settles that at 56dp here and 60pt on iOS. Fixed rather
 * than scaled with the reader's text: the requirement at the largest accessibility size is that
 * the *names* are readable and the tiles are still large enough to tell apart, and a tile that
 * grew with the text would push the name it exists beside off the row.
 */
private val tileSide = 56.dp

/**
 * A hairline, so the lightest face has an edge.
 *
 * **Found by the capture, which is what the capture is for.** Paper's plate is `#F8F6F4` and
 * the settings surface it sits on is a warm off-white too, so on the first screenshot Paper's
 * tile had no boundary at all and read as a plateless mark beside four plated ones — the one
 * face a reader could not see. iOS's tile carries the same hairline for the same reason.
 */
private val tileEdge = 1.dp

/** How this face is named on screen. */
internal val AppIconChoice.labelRes: Int
    get() = when (this) {
        AppIconChoice.INK -> R.string.app_icon_ink
        AppIconChoice.PAPER -> R.string.app_icon_paper
        AppIconChoice.BLOOM -> R.string.app_icon_bloom
        AppIconChoice.ARC -> R.string.app_icon_arc
        AppIconChoice.MONO -> R.string.app_icon_mono
    }

/**
 * The face's own launcher icon, rasterised at [side] pixels, or null if it cannot be read.
 *
 * **Asked of `PackageManager` rather than drawn from resources, and that is the point.** The
 * plates and the mark live in `:app`'s resources, which a feature module cannot reference at
 * all — and an `<adaptive-icon>` is not something `painterResource` can draw even where it
 * can see it. Loading the component's own icon means the chooser shows *the drawable the
 * launcher will use*, so a face whose manifest entry is wrong looks wrong here rather than
 * looking right here and wrong on the home screen.
 *
 * `MATCH_DISABLED_COMPONENTS` is what makes it possible: four of the five components are
 * disabled at any moment, and without the flag every option but the current one is
 * unreadable.
 *
 * Null on failure rather than a throw. This is a settings row, and a reader who opened
 * Appearance must not be shown a crash because a component could not be read.
 */
private fun launcherIcon(context: Context, choice: AppIconChoice, side: Int): ImageBitmap? {
    if (side <= 0) return null
    return try {
        val packages = context.packageManager
        val component = ComponentName(context.packageName, choice.componentClassName)
        // The deprecated overload deliberately. Its replacement, `getActivityInfo(
        // ComponentName, ComponentInfoFlags)`, arrived in API 33 and this app's floor is 31
        // (ADR-0003), so the modern call would need a version branch whose older half nothing
        // in this project ever runs. Deprecated is not removed, and one call that is exercised
        // everywhere beats two of which one is exercised nowhere.
        @Suppress("DEPRECATION")
        val info = packages.getActivityInfo(component, PackageManager.MATCH_DISABLED_COMPONENTS)
        val drawable = info.loadIcon(packages)
        val bitmap = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, side, side)
        drawable.draw(Canvas(bitmap))
        bitmap.asImageBitmap()
    } catch (failure: RuntimeException) {
        // `NameNotFoundException` is checked and cannot happen for this app's own components,
        // but a `Resources.NotFoundException` from an icon that failed to package can, and so
        // can an allocation failure on a device under pressure. Neither is worth a crash.
        null
    } catch (failure: PackageManager.NameNotFoundException) {
        null
    }
}

/**
 * The five faces, and what pressing one does.
 *
 * Part of the Appearance group rather than a screen of its own, because that is what the spec
 * asks for by name: "it sits beside Appearance, because both answer *what does the app look
 * like*". A third navigation level would put a screen between the reader and the answer, and
 * the settings search reaches it either way through [SettingsAnchor.APP_ICON].
 *
 * The switcher is remembered here because it holds nothing worth hoisting: **the platform is
 * the store**, so [AppIconSwitcher.applied] is a query and this composable's state is only the
 * refusal, which lasts until the reader presses something else.
 */
@Composable
internal fun AppIconGroup(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val palette = LocalStoryArcPalette.current
    val switcher = remember(context) { AppIconSwitcher.of(context) }

    // Read from the platform, not remembered across presses: an icon can change without this
    // screen — a restore, an update, a reader disabling a component — and the component states
    // are the only thing that knows. Null when the platform reports none enabled, which marks
    // no row rather than claiming the default is in use while the app is off the launcher.
    var applied by remember { mutableStateOf(switcher.applied()) }
    var refused by remember { mutableStateOf<AppIconChoice?>(null) }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        Text(
            text = stringResource(R.string.app_icon_title),
            style = MaterialTheme.typography.titleSmall,
            color = palette.textPrimary,
        )

        // What the platform can and cannot do with the choice, stated rather than papered
        // over. `settings-and-about`: on Android "the reader is told it appears the next time
        // the launcher draws its list, because that platform offers no way to change it in
        // place". iOS changes there and then and says so instead — the two notes differ
        // because the platforms do.
        //
        // The refusal replaces this rather than joining it: a reader who has just been told
        // the change failed does not need the general note underneath. And it names the face
        // still in use, because "it could not be changed" alone leaves them guessing what they
        // are now looking at.
        val inUse = applied
        Text(
            text = when {
                refused == null -> stringResource(R.string.app_icon_note)
                inUse != null ->
                    stringResource(R.string.app_icon_refused, stringResource(inUse.labelRes))
                // Nothing is enabled, so there is no face still in use to name. Naming one
                // would tell a reader whose launcher entry is already gone that the app is
                // using the icon they can no longer see.
                else -> stringResource(R.string.app_icon_refused_none)
            },
            style = MaterialTheme.typography.labelLarge,
            color = if (refused == null) palette.textTertiary else palette.textPrimary,
        )

        AppIconChoice.entries.forEach { face ->
            AppIconRow(
                face = face,
                isApplied = applied == face,
                onChoose = {
                    // A no-op is a no-op: rewriting five component states for the icon
                    // already drawn would ask the platform for nothing and could only fail.
                    //
                    // **A device with nothing enabled is not that state**, and this comparison
                    // is why it is now pressable: `applied` is null there rather than the
                    // default, so it equals no face and the guard lets every press through.
                    // While it answered the default, the one press that puts the launcher
                    // entry back — Ink — was the single press this refused.
                    if (applied != face) {
                        refused = if (switcher.choose(face)) null else face
                        // Re-read rather than assume. On success this is the face; on a
                        // refusal it is whatever the platform is still drawing, which is the
                        // half of the message the reader needs.
                        applied = switcher.applied()
                    }
                },
            )
        }
    }
}

@Composable
private fun AppIconRow(face: AppIconChoice, isApplied: Boolean, onChoose: () -> Unit) {
    val context = LocalContext.current
    val palette = LocalStoryArcPalette.current
    val side = with(LocalDensity.current) { tileSide.roundToPx() }
    // Keyed on the face and the size only. A component's icon does not depend on whether it is
    // enabled — `MATCH_DISABLED_COMPONENTS` reads all five alike — so keying on `isApplied`
    // would rasterise five drawables again on every press for no change at all.
    val tile = remember(face, side) { launcherIcon(context, face, side) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .selectableRow(selected = isApplied, onClick = onChoose)
            .padding(vertical = StoryArcSpace.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = isApplied, onClick = null)
        if (tile != null) {
            Image(
                bitmap = tile,
                // Decorative. `settings-and-about`: "the tile itself is decorative to
                // assistive technology, because the name is what identifies it". A described
                // tile would make every row announce "image, Paper" and say nothing a blind
                // reader can act on — and `selectableRow` already merges the row into one
                // control announced by name and by whether it is in use.
                contentDescription = null,
                // Circular, and the hairline with it. The launcher has already masked the
                // drawable to *its* shape — a circle here, a squircle elsewhere — and this
                // module cannot ask which without an API that arrived after this app's floor.
                // So the chooser normalises the mask and rings it, which is what gives the
                // hairline something to sit on. The plate and the mark are the component's
                // own; only the outline is this screen's.
                modifier = Modifier
                    .padding(start = StoryArcSpace.sm)
                    .size(tileSide)
                    .clip(CircleShape)
                    .border(tileEdge, palette.textSecondary.copy(alpha = 0.25f), CircleShape),
            )
        }
        Column(modifier = Modifier.padding(start = StoryArcSpace.sm)) {
            Text(
                text = stringResource(face.labelRes),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
            )
            if (face.isDefault) {
                Text(
                    text = stringResource(R.string.app_icon_default),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                )
            }
        }
    }
}
