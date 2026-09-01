package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The invariant that matters most in this change: **the app never leaves the launcher.**
 *
 * Zero enabled components carrying the launcher intent filter makes StoryArc vanish from the
 * home screen and the app drawer, and there is no way back from inside the app — a reader has
 * to reinstall it. So this is not asserted by reading the sequencing and agreeing with it. A
 * device is modelled, every plan is applied to it one write at a time, and the count of
 * launcher-visible components is checked *after every single write*, including the writes a
 * failure stopped halfway through.
 *
 * iOS has no counterpart. `setAlternateIconName` is one call, it either works or reports an
 * error, and no intermediate state exists for a test to catch.
 */
class AppIconAliasesTest {

    /**
     * The component states a fresh install has: the manifest's own, untouched.
     *
     * Every face starts at [AppIconAliasState.DEFAULT] because that is literally what a
     * device that has never been asked holds — not "Ink enabled and the rest disabled", which
     * is what a plan produces and would quietly make the starting state a *result*.
     */
    private fun freshInstall() =
        AppIconChoice.entries.associateWith { AppIconAliasState.DEFAULT }.toMutableMap()

    /** How many of the modelled components the launcher would draw. */
    private fun visible(device: Map<AppIconChoice, AppIconAliasState>) =
        device.count { (face, state) -> AppIconAliases.isEnabled(face, state) }

    /**
     * Applies a plan write by write, asserting after each one that something is still on the
     * launcher. Returns the device it left behind.
     *
     * `upTo` stops early, which is how a failure mid-sequence is modelled: the platform threw
     * on write number `upTo`, so the writes before it landed and the rest never ran.
     */
    private fun apply(
        device: MutableMap<AppIconChoice, AppIconAliasState>,
        target: AppIconChoice,
        upTo: Int = Int.MAX_VALUE,
        why: String = "",
    ): MutableMap<AppIconChoice, AppIconAliasState> {
        val plan = AppIconAliases.plan(target)
        assertTrue(
            "a fresh install must be recoverable before anything is written$why",
            visible(device) >= 1,
        )
        plan.take(upTo).forEachIndexed { at, step ->
            device[step.face] = step.state
            assertTrue(
                "the app left the launcher after write ${at + 1} of ${plan.size} " +
                    "towards $target$why — device was $device",
                visible(device) >= 1,
            )
        }
        return device
    }

    @Test
    fun `every transition ends with exactly one face on the launcher`() {
        for (from in AppIconChoice.entries) {
            for (to in AppIconChoice.entries) {
                val device = apply(freshInstall(), from, why = " (settling on $from)")
                apply(device, to, why = " ($from to $to)")
                assertEquals("$from to $to left more than one icon", 1, visible(device))
                assertTrue(
                    "$from to $to left the wrong icon",
                    AppIconAliases.isEnabled(to, device.getValue(to)),
                )
            }
        }
    }

    /**
     * The same face twice, which is what a double tap is.
     *
     * A plan that only wrote *changes* would produce nothing here, which is fine — but a plan
     * that disabled the old face first and then discovered the new one was the same would
     * open a window with none enabled. This is the test that a total, idempotent plan buys.
     */
    @Test
    fun `choosing the face already in use changes nothing and never opens a gap`() {
        for (face in AppIconChoice.entries) {
            val device = apply(freshInstall(), face)
            val settled = device.toMap()
            apply(device, face, why = " ($face again)")
            assertEquals("$face twice did not settle", settled, device.toMap())
            assertEquals(1, visible(device))
        }
    }

    /**
     * A failure at each write of each plan, from each starting face.
     *
     * Two claims, and the second is the one that makes the first survivable: the launcher
     * never empties while a plan is half-applied, and a *later* plan lands correctly from
     * whatever the half-applied one left — because the plan names every face rather than only
     * the ones that change.
     */
    @Test
    fun `a failure at any write leaves the app reachable and the next plan recovers`() {
        for (from in AppIconChoice.entries) {
            for (to in AppIconChoice.entries) {
                for (failAt in 1..AppIconChoice.entries.size) {
                    val device = apply(freshInstall(), from)
                    apply(device, to, upTo = failAt, why = " (failed at write $failAt)")
                    assertTrue(
                        "$from to $to failing at $failAt left nothing on the launcher",
                        visible(device) >= 1,
                    )
                    // And the way out, which is the only reason the state above is tolerable.
                    apply(device, from, why = " (recovering to $from after $failAt)")
                    assertEquals(1, visible(device))
                    assertTrue(AppIconAliases.isEnabled(from, device.getValue(from)))
                }
            }
        }
    }

    /**
     * The enable comes first, always.
     *
     * Disabling the currently-enabled component can close the task, which would end the
     * reader's session in the middle of a settings change. It is also the write that could
     * empty the launcher, so ordering it after the enable is what makes the gap impossible
     * rather than merely brief.
     */
    @Test
    fun `the target is written first and every other face after it`() {
        for (target in AppIconChoice.entries) {
            val plan = AppIconAliases.plan(target)
            assertEquals(AppIconChoice.entries.size, plan.size)
            assertEquals("the enable is not the first write", target, plan.first().face)
            assertTrue(AppIconAliases.isEnabled(target, plan.first().state))
            plan.drop(1).forEach {
                assertNotEquals("$target appears twice in its own plan", target, it.face)
                assertTrue(
                    "${it.face} is left on the launcher beside $target",
                    !AppIconAliases.isEnabled(it.face, it.state),
                )
            }
            assertEquals("a plan must name every face", AppIconChoice.entries.toSet(), plan.map { it.face }.toSet())
        }
    }

    /**
     * Choosing the default hands every component back to the manifest.
     *
     * Task 4.5: "a fresh install and a reset land in the same state". Not *equivalent* states
     * — the same ones, which is what [AppIconAliasState.DEFAULT] is for. A plan that wrote an
     * explicit `ENABLED` on `MainActivity` would look identical on the launcher and leave the
     * device holding an override a fresh install does not have.
     */
    @Test
    fun `resetting to the default leaves exactly the states a fresh install has`() {
        val device = apply(freshInstall(), AppIconChoice.ARC)
        assertNotEquals(freshInstall().toMap(), device.toMap())
        apply(device, AppIconChoice.DEFAULT)
        assertEquals(freshInstall().toMap(), device.toMap())
    }

    /** DEFAULT means "what the manifest says", and the manifest enables one component. */
    @Test
    fun `a device that has never been asked draws the default face and nothing else`() {
        val fresh = freshInstall()
        assertEquals(1, visible(fresh))
        assertTrue(AppIconAliases.isEnabled(AppIconChoice.DEFAULT, fresh.getValue(AppIconChoice.DEFAULT)))
    }
}
