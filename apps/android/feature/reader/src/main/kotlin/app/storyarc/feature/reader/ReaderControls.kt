package app.storyarc.feature.reader

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ManageSearch
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.ScreenLockRotation
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.ViewColumn
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FloatingToolbarDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.HorizontalFloatingToolbar
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.PageFit
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.model.TransitionChoices
import app.storyarc.core.model.TransitionUnavailability
import app.storyarc.core.model.scrollAxis

/*
 * The reader's chrome controls.
 *
 * Split out of `ReaderScreen.kt`, which is 2156 lines against this project's 800-line
 * ceiling. The split is along the seam this change already works on rather than an
 * arbitrary cut: every control that sits in the chrome lives here, and `ReaderScreen.kt`
 * keeps the screen's structure - the pager, the gestures, the paging and the bottom band.
 * That file is still over the ceiling afterwards, which is a pre-existing condition this
 * slice reduces rather than resolves.
 *
 * **What changed here.** Each of these controls used to be an
 * `IconButton { Surface(color = scrim.copy(alpha = 0.6f), shape = CircleShape) { Icon() } }` -
 * a floating toolbar built by hand, one pill at a time, about ten times over. Material
 * has the component: `HorizontalFloatingToolbar` supplies the Expressive container, its
 * shape, elevation, insets and motion, and the row of separate pills becomes one bar.
 *
 * The colours are named rather than left to `standardFloatingToolbarColors()`. The
 * default is dynamic, and §4.6 of the design direction puts the reader's *content* on
 * StoryArc neutrals - but the reason here is narrower and older than the rule: this bar
 * floats over artwork that can be white, and the icons on it are white. The scrim the
 * hand-rolled pills carried is what made them legible over a white manga page, so the
 * bar carries it instead. Losing it would be a contrast regression, not a restyle.
 */

/** The scrim and white the chrome has always used, on Material's container. */
@Composable
private fun readerToolbarColours() = FloatingToolbarDefaults.standardFloatingToolbarColors(
    toolbarContainerColor = LocalStoryArcPalette.current.scrim.copy(alpha = 0.6f),
    toolbarContentColor = Color.White,
)

/**
 * The tools that act on the page: how it turns, how it is sized, how it is paired, how it
 * looks, and - for a PDF that carries text - how it is searched.
 *
 * One bar rather than five pills. The two controls that come and go with the publication's
 * shape widen it instead of arriving beside it.
 */
@Composable
internal fun ReaderToolCluster(
    choices: TransitionChoices,
    showsSeparator: Boolean,
    onToggleSeparator: (Boolean) -> Unit,
    onChooseTransition: (PageTransition) -> Unit,
    fit: PageFit,
    onChooseFit: (PageFit) -> Unit,
    hasPairs: Boolean,
    isOffset: Boolean,
    onToggleOffset: () -> Unit,
    adjustmentsAreNeutral: Boolean,
    onAdjust: () -> Unit,
    hasPdfText: Boolean,
    onFindText: () -> Unit,
    onMenuOpenChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    HorizontalFloatingToolbar(
        expanded = true,
        colors = readerToolbarColours(),
        modifier = modifier.padding(StoryArcSpace.md),
    ) {
        TransitionMenu(
            choices = choices,
            showsSeparator = showsSeparator,
            onToggleSeparator = onToggleSeparator,
            onChoose = onChooseTransition,
            onOpenChange = onMenuOpenChange,
        )
        FitMenu(fit = fit, onChange = onChooseFit, onOpenChange = onMenuOpenChange)
        // Only where there is a pairing to shift. `comic-reader` offers the offset "for
        // publications whose cover throws the pairing off", which is a question that does
        // not arise in portrait or in a scroll.
        if (hasPairs) {
            SpreadOffsetButton(isOffset = isOffset, onToggle = onToggleOffset)
        }
        AdjustButton(isNeutral = adjustmentsAreNeutral, onOpen = onAdjust)
        // Only for a PDF that carries text. `ebook-reader` requires a text-dependent
        // control to be hidden rather than disabled when there is none, and a button that
        // opened a search box over a scan would be exactly the promise the spec forbids.
        if (hasPdfText) {
            FindTextButton(onFindText)
        }
    }
}

/**
 * How the publication is laid out: which way it runs, and whether the screen may turn.
 *
 * A second bar rather than two more pills, for the same reason as the tools above - two
 * adjacent controls that both answer "how is this presented" read as two unrelated ones.
 */
@Composable
internal fun ReaderLayoutCluster(
    direction: ReadingDirection,
    onChooseDirection: (ReadingDirection) -> Unit,
    isOrientationLocked: Boolean,
    onToggleOrientation: () -> Unit,
    onMenuOpenChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    HorizontalFloatingToolbar(
        expanded = true,
        colors = readerToolbarColours(),
        modifier = modifier,
    ) {
        DirectionMenu(
            direction = direction,
            onChoose = onChooseDirection,
            onOpenChange = onMenuOpenChange,
        )
        OrientationToggle(isLocked = isOrientationLocked, onToggle = onToggleOrientation)
    }
}

/** Opens the text search over a PDF that carries text. */
@Composable
private fun FindTextButton(onClick: () -> Unit) {
    IconButton(onClick = onClick) {
        Icon(
            imageVector = Icons.AutoMirrored.Filled.ManageSearch,
            contentDescription = stringResource(R.string.reader_pdf_find),
        )
    }
}

/**
 * Shifts which pages are paired, for a publication whose cover throws the pairing off.
 *
 * iOS's spread-offset button is the same control.
 */
@Composable
private fun SpreadOffsetButton(isOffset: Boolean, onToggle: () -> Unit) {
    IconButton(onClick = onToggle) {
        Icon(
            imageVector = Icons.Filled.ViewColumn,
            contentDescription = stringResource(R.string.reader_spreads_offset),
            tint = if (isOffset) LocalStoryArcPalette.current.accent else LocalContentColor.current,
        )
    }
}

/** How the page is sized. `comic-reader` names the four modes. */
@Composable
private fun FitMenu(
    fit: PageFit,
    onChange: (PageFit) -> Unit,
    onOpenChange: (Boolean) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    LaunchedEffect(open) { onOpenChange(open) }

    IconButton(onClick = { open = true }) {
        Icon(
            imageVector = Icons.Filled.Fullscreen,
            contentDescription = stringResource(R.string.reader_fit),
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            PageFit.entries.forEach { candidate ->
                DropdownMenuItem(
                    text = { Text(stringResource(candidate.labelRes)) },
                    leadingIcon = { RadioButton(selected = fit == candidate, onClick = null) },
                    onClick = {
                        onChange(candidate)
                        open = false
                    },
                )
            }
        }
    }
}

/**
 * Which way the pages run.
 *
 * `comic-reader` opens a publication in the direction its metadata declares and lets the
 * reader overrule that, for the series. Two rows and a radio, the same shape as [FitMenu]
 * rather than a bare toggle: metadata gets this wrong often enough that a reader who
 * suspects it needs to see which way the comic is running, not only be able to flip it.
 */
@Composable
private fun DirectionMenu(
    direction: ReadingDirection,
    onChoose: (ReadingDirection) -> Unit,
    onOpenChange: (Boolean) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    LaunchedEffect(open) { onOpenChange(open) }

    IconButton(onClick = { open = true }) {
        Icon(
            imageVector = Icons.Filled.SwapHoriz,
            contentDescription = stringResource(R.string.reader_direction),
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            ReadingDirection.entries.forEach { candidate ->
                DropdownMenuItem(
                    text = { Text(stringResource(candidate.labelRes)) },
                    leadingIcon = { RadioButton(selected = direction == candidate, onClick = null) },
                    onClick = {
                        onChoose(candidate)
                        open = false
                    },
                )
            }
        }
    }
}

/**
 * Holds the screen at the way up it is now.
 *
 * `comic-reader` scopes the lock to the reader, so it is a button here rather than a row
 * in Settings. Its name says what pressing it would do rather than what the state is:
 * with no label on screen beside the icon, that sentence is all TalkBack has to go on.
 */
@Composable
private fun OrientationToggle(isLocked: Boolean, onToggle: () -> Unit) {
    IconButton(onClick = onToggle) {
        Icon(
            imageVector = if (isLocked) {
                Icons.Filled.ScreenLockRotation
            } else {
                Icons.Filled.ScreenRotation
            },
            contentDescription = stringResource(
                if (isLocked) R.string.reader_orientation_unlock else R.string.reader_orientation_lock,
            ),
            tint = if (isLocked) LocalStoryArcPalette.current.accent else LocalContentColor.current,
        )
    }
}

/**
 * The page-transition picker.
 *
 * Four rows, and `page-transitions` is specific about what a row that cannot run
 * looks like: "shown unavailable with a one-line reason, never silently absent". So a
 * row disabled by reduced motion stays, greyed, with the reason under it — a control
 * that vanishes teaches the reader nothing.
 *
 * Curl is the one exception, and the spec draws that line itself: where the *device*
 * cannot honour it, Curl is "absent from the picker on that device… with the reason
 * stated once in plain language — naming the requirement, not an API level". A
 * permanently dead row is furniture; a sentence is an explanation.
 */
@Composable
private fun TransitionMenu(
    choices: TransitionChoices,
    onChoose: (PageTransition) -> Unit,
    onOpenChange: (Boolean) -> Unit,
    /** Whether a continuous scroll draws a line where one page ends and the next begins. */
    showsSeparator: Boolean,
    onToggleSeparator: (Boolean) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    LaunchedEffect(open) { onOpenChange(open) }

    IconButton(onClick = { open = true }) {
        Icon(
            imageVector = Icons.AutoMirrored.Filled.MenuBook,
            contentDescription = stringResource(R.string.reader_transition),
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            choices.offered.forEach { mode ->
                val reason = choices.unavailable[mode]
                DropdownMenuItem(
                    text = {
                        Column {
                            Text(stringResource(mode.labelRes))
                            if (reason != null) {
                                Text(
                                    text = stringResource(reason.labelRes),
                                    style = MaterialTheme.typography.labelSmall,
                                )
                            }
                        }
                    },
                    leadingIcon = {
                        RadioButton(
                            selected = choices.chosen == mode,
                            onClick = null,
                            enabled = reason == null,
                        )
                    },
                    enabled = reason == null,
                    onClick = {
                        onChoose(mode)
                        open = false
                    },
                )
            }
            // Only where there are stitched pages to separate. In a paged mode there is a
            // whole screen between one page and the next already.
            if (choices.effective.scrollAxis != null) {
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.reader_separator)) },
                    leadingIcon = { Checkbox(checked = showsSeparator, onCheckedChange = null) },
                    onClick = { onToggleSeparator(!showsSeparator) },
                )
            }
            if (choices.curlIsAbsent) {
                // Once, and in the reader's language rather than the platform's.
                DropdownMenuItem(
                    text = {
                        Text(
                            text = stringResource(R.string.reader_transition_no_curl),
                            style = MaterialTheme.typography.labelSmall,
                        )
                    },
                    enabled = false,
                    onClick = {},
                )
            }
        }
    }
}

/** How the transition modes are named on screen. */
private val PageTransition.labelRes: Int
    get() = when (this) {
        PageTransition.PAGE_CURL -> R.string.reader_transition_curl
        PageTransition.SLIDE -> R.string.reader_transition_slide
        PageTransition.FAST_FADE -> R.string.reader_transition_fade
        PageTransition.VERTICAL_SCROLL -> R.string.reader_transition_scroll_vertical
        PageTransition.HORIZONTAL_SCROLL -> R.string.reader_transition_scroll_horizontal
    }

/** Why a mode cannot run, in one line. */
private val TransitionUnavailability.labelRes: Int
    get() = when (this) {
        TransitionUnavailability.REDUCE_MOTION -> R.string.reader_transition_reduce_motion
        // A comic page is already an image, so this reason cannot arise here. It is
        // named rather than swallowed by an `else`, so that adding a third reason still
        // breaks this file rather than silently showing the wrong sentence.
        TransitionUnavailability.REFLOWABLE_TEXT -> R.string.reader_transition_reflowable
    }

/**
 * Which way the pages run, named the way a reader would say it.
 *
 * Right-to-left reuses the sentence TalkBack already reads out on entering a manga,
 * because it is the same fact and a second wording of it would be one to keep in step
 * for nothing.
 */
private val ReadingDirection.labelRes: Int
    get() = when (this) {
        ReadingDirection.LEFT_TO_RIGHT -> R.string.reader_left_to_right
        ReadingDirection.RIGHT_TO_LEFT -> R.string.reader_right_to_left
    }

/**
 * How the fit modes are named on screen.
 *
 * The enum lives in `:core:model` and carries no resources: the domain has no
 * business holding UI copy.
 */
private val PageFit.labelRes: Int
    get() = when (this) {
        PageFit.SCREEN -> R.string.reader_fit_screen
        PageFit.WIDTH -> R.string.reader_fit_width
        PageFit.HEIGHT -> R.string.reader_fit_height
        PageFit.ORIGINAL -> R.string.reader_fit_original
    }
