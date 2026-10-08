package app.storyarc.core.designsystem.control

import androidx.compose.ui.unit.dp

/**
 * Material 3's touch target: a control a finger can hit is laid out at least this wide and high.
 *
 * `close-the-audited-gaps` task 24.4. The accessibility service reports the box a control is
 * laid out in, so a 32 dp chip or a 40 dp icon button is measured as that, whatever area the
 * toolkit also lets a touch land on. Controls the toolkit draws smaller take this as a minimum
 * size, and neighbouring targets keep [TOUCH_TARGET_GAP] between them.
 */
val MIN_TOUCH_TARGET = 48.dp

/** Material 3's space between two touch targets. */
val TOUCH_TARGET_GAP = 8.dp
