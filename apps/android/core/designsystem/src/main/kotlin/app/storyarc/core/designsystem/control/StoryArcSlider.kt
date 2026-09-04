package app.storyarc.core.designsystem.control

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.SliderState
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp

/**
 * A slider's rail, drawn so that the handle is standing on it.
 *
 * **What the sweep of 2026-09-02 photographed.** `android-comic-menu.png`: the page slider
 * "draws its thumb as a tall vertical bar at the far left, outside and above the rounded
 * track that starts about 17 px to its right. It reads as a rendering fault rather than a
 * control." Measured off the frame, the thumb is 4 dp wide and 44 dp tall, the rail is 16 dp
 * tall, and between them is a 15-device-pixel gap — Material's own `ThumbTrackGapSize`, which
 * is 6 dp.
 *
 * **It is not a fault, and it is not only the page slider.** Material 3 Expressive separates
 * the handle from both halves of the rail so the handle reads against the *active* half, and
 * at a mid-range value it works: `android-comic-adjustments.png` shows Brightness and
 * Contrast doing exactly that, and they look right. The same frame shows Sharpness at zero
 * and it looks broken, for the reason the page slider does — at either end of the travel one
 * half of the rail has no width, so the gap on that side has nothing behind it and the handle
 * is left floating beside a rail it is not touching.
 *
 * A comic's page slider sits at that end whenever a reader has just opened the book, which is
 * why it was the frame somebody noticed.
 *
 * **So the gap goes, and everything else stays Material's.** One parameter, one place, every
 * slider in the app: `comic-reader` and `reading-themes` both describe controls a reader
 * drags, and a control that looks broken at rest is not one they will. The stop indicators,
 * the shapes, the heights, the colours and the motion are untouched — including the accent
 * `AccentReachesTheControlsTest` put on the rail at rest.
 *
 * `SliderTrackTouchesItsThumbTest` draws it and counts the pixels between the two.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StoryArcSliderTrack(state: SliderState) {
    SliderDefaults.Track(sliderState = state, thumbTrackGapSize = 0.dp)
}
