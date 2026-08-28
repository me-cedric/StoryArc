package app.storyarc.core.model

import kotlinx.serialization.Serializable

/**
 * What to do to a page before it is shown.
 *
 * `comic-reader`: "per-publication image adjustments for poorly scanned material",
 * offering "brightness, contrast, sharpness, colour inversion, and greyscale ... with a live
 * preview". A scan too dark to read, or grey where it should be white, is the ordinary state
 * of a lot of comics, and a reader who cannot fix it has to stop reading.
 *
 * The three continuous values are signed and neutral at zero, so [isNeutral] is a comparison
 * against a fresh value rather than a list of magic numbers, and a stored adjustment that
 * does nothing is indistinguishable from none. iOS's `ImageAdjustments` is the same object.
 *
 * @property brightness −1 (black) to 1 (white), 0 unchanged.
 * @property contrast −1 (flat) to 1 (hard), 0 unchanged.
 * @property sharpness 0 to 1. Not signed: blurring a scan is not a repair anyone asks for.
 * @property isInverted white on black, for a scan whose page is already dark.
 * @property isGreyscale colour removed, which reads better than a bad colour cast.
 */
@Serializable
data class ImageAdjustments(
    val brightness: Float = 0f,
    val contrast: Float = 0f,
    val sharpness: Float = 0f,
    val isInverted: Boolean = false,
    val isGreyscale: Boolean = false,
) {
    /**
     * Nothing to do.
     *
     * Worth asking, because applying a no-op filter still costs a pass over every page.
     */
    val isNeutral: Boolean get() = this == NEUTRAL

    /**
     * The multiplier a renderer wants for contrast, where 1 is unchanged.
     *
     * A signed −1..1 is what a reader drags; a 0..2 multiplier is what every image pipeline
     * takes. Kept here rather than in each renderer so Android and iOS cannot drift.
     */
    val contrastFactor: Float get() = 1f + contrast

    /** The same values, brought back into the ranges the renderers assume. */
    fun clamped(): ImageAdjustments = copy(
        brightness = brightness.coerceIn(-1f, 1f),
        contrast = contrast.coerceIn(-1f, 1f),
        sharpness = sharpness.coerceIn(0f, 1f),
    )

    companion object {
        val NEUTRAL = ImageAdjustments()
    }
}
