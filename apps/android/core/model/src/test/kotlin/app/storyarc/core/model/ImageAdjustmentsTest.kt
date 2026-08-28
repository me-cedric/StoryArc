package app.storyarc.core.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImageAdjustmentsTest {
    @Test
    fun aFreshAdjustmentDoesNothing() {
        // Worth asserting rather than assuming: `isNeutral` is what stops a filter being
        // applied to every page of every comic.
        assertTrue(ImageAdjustments().isNeutral)
        assertFalse(ImageAdjustments(brightness = 0.1f).isNeutral)
        assertFalse(ImageAdjustments(isGreyscale = true).isNeutral)
    }

    @Test
    fun valuesOutsideTheRangeAreBroughtBackIntoIt() {
        // A slider cannot produce these; a decoded value from an older or altered store
        // can, and a contrast of 40 is a black page.
        assertEquals(1f, ImageAdjustments(brightness = 9f).clamped().brightness, 0f)
        assertEquals(-1f, ImageAdjustments(contrast = -9f).clamped().contrast, 0f)
        assertEquals(0f, ImageAdjustments(sharpness = -1f).clamped().sharpness, 0f)
    }

    @Test
    fun contrastIsOfferedAsTheMultiplierARendererTakes() {
        assertEquals(1f, ImageAdjustments().contrastFactor, 0f)
        assertEquals(2f, ImageAdjustments(contrast = 1f).contrastFactor, 0f)
        assertEquals(0f, ImageAdjustments(contrast = -1f).contrastFactor, 0f)
    }

    @Test
    fun aStoreWrittenBeforeAFieldExistedStillReads() {
        // The same forgiveness `ShelfSettings` needs, for the same reason: a build that adds
        // a field must not lose what an earlier build wrote.
        val json = Json { ignoreUnknownKeys = true }
        val decoded = json.decodeFromString<ImageAdjustments>("""{"brightness":0.5}""")
        assertEquals(0.5f, decoded.brightness, 0f)
        assertFalse(decoded.isGreyscale)
    }

    @Test
    fun aShelfKeepsItsOwnAdjustment() {
        // `comic-reader`: an adjustment applies "to the series and [is not] applied
        // globally". The store is what makes that true, so the store is what is tested.
        val adjusted = ShelfSettings(adjustments = ImageAdjustments(contrast = 0.4f))
        val memory = ShelfMemory().remembering(adjusted, ThemeScope.FIXED_LAYOUT, "Bone")
        val bone = memory.theme(ThemeScope.FIXED_LAYOUT, "Bone")
        val other = memory.theme(ThemeScope.FIXED_LAYOUT, "Blame!")
        assertEquals(0.4f, bone.adjustments.contrast, 0f)
        assertEquals(0f, other.adjustments.contrast, 0f)
    }
}
