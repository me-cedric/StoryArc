package app.storyarc.feature.settings

import app.storyarc.core.model.AppIconAliasState
import app.storyarc.core.model.AppIconAliases
import app.storyarc.core.model.AppIconChoice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The part that touches `PackageManager`, driven without a device.
 *
 * `AppIconAliasesTest` in `:core:model` owns the invariant — never zero enabled, over every
 * transition and every mid-sequence failure. This asserts the four things the executor adds:
 * the writes reach the platform in the plan's order, a failure stops the sequence rather than
 * carrying on, `applied()` answers from the platform rather than from anything remembered, and
 * a device the invariant cannot reach on its own — every alias off, which a package tool or the
 * platform's own `DISABLED_UNTIL_USED` can produce — reads as *no* face rather than as the
 * default, because the chooser's no-op guard turns the latter into a refusal of the one press
 * that recovers.
 */
class AppIconSwitcherTest {

    /** A device that records its writes and can be told to throw on one of them. */
    private class FakeDevice {
        val states = AppIconChoice.entries.associateWith { AppIconAliasState.DEFAULT }.toMutableMap()
        val writes = mutableListOf<Pair<AppIconChoice, AppIconAliasState>>()

        /** One-based index of the write that fails, or null for a device that accepts everything. */
        var failsAt: Int? = null

        val switcher: AppIconSwitcher
            get() = AppIconSwitcher(
                read = { states.getValue(it) },
                write = { face, state ->
                    writes.add(face to state)
                    if (writes.size == failsAt) throw SecurityException("the platform said no")
                    states[face] = state
                },
            )

        fun visible() = states.count { (face, state) -> AppIconAliases.isEnabled(face, state) }
    }

    @Test
    fun `a fresh device reports the default face`() {
        assertEquals(AppIconChoice.DEFAULT, FakeDevice().switcher.applied())
    }

    @Test
    fun `applied reads the platform rather than remembering what it wrote`() {
        val device = FakeDevice()
        val switcher = device.switcher
        assertTrue(switcher.choose(AppIconChoice.BLOOM))
        assertEquals(AppIconChoice.BLOOM, switcher.applied())

        // Something outside this app changed a component — a restore, or a reader disabling
        // one by hand. The switcher must follow the platform, not its own last word.
        device.states[AppIconChoice.BLOOM] = AppIconAliasState.DISABLED
        device.states[AppIconChoice.ARC] = AppIconAliasState.ENABLED
        assertEquals(AppIconChoice.ARC, switcher.applied())
    }

    /**
     * The enable reaches the platform first, which is what makes a failure survivable rather
     * than merely brief: disabling the drawn component before enabling the new one can close
     * the task, and for an instant leaves nothing on the launcher.
     */
    @Test
    fun `the writes reach the platform in the plan's order, enable first`() {
        val device = FakeDevice()
        assertTrue(device.switcher.choose(AppIconChoice.ARC))
        assertEquals(AppIconAliases.plan(AppIconChoice.ARC).map { it.face to it.state }, device.writes)
        assertEquals(AppIconChoice.ARC, device.writes.first().first)
        assertEquals(1, device.visible())
    }

    /**
     * A refusal on the first write — the enable — must leave the device untouched, because
     * that is the write the rest of the plan is safe *behind*. If the switcher carried on it
     * would disable four components with none enabled, and the app would leave the launcher.
     */
    @Test
    fun `a refusal on the enable disables nothing`() {
        val device = FakeDevice()
        device.failsAt = 1
        assertFalse(device.switcher.choose(AppIconChoice.PAPER))
        assertEquals(1, device.writes.size)
        assertEquals(1, device.visible())
        assertEquals(AppIconChoice.DEFAULT, device.switcher.applied())
    }

    @Test
    fun `a refusal partway stops the sequence and leaves the app reachable`() {
        for (failAt in 1..AppIconChoice.entries.size) {
            val device = FakeDevice()
            device.failsAt = failAt
            assertFalse("write $failAt failed and choose() claimed success", device.switcher.choose(AppIconChoice.MONO))
            assertEquals("the sequence carried on past a failure", failAt, device.writes.size)
            assertTrue("failing at $failAt took the app off the launcher", device.visible() >= 1)

            // And the way out. The plan names every face, so the next one settles the device
            // whatever the failed one left behind.
            device.failsAt = null
            assertTrue(device.switcher.choose(AppIconChoice.INK))
            assertEquals(1, device.visible())
            assertEquals(AppIconChoice.INK, device.switcher.applied())
        }
    }

    /**
     * A reader who taps an icon must not be shown a crash. Every way `PackageManager` refuses
     * a component is a `RuntimeException` of some kind, and the refusal path is what the spec
     * asks for in its place.
     */
    @Test
    fun `a platform that throws is a refusal rather than a crash`() {
        val device = FakeDevice()
        var thrown: Throwable? = null
        val switcher = AppIconSwitcher(
            read = { device.states.getValue(it) },
            write = { _, _ -> throw IllegalArgumentException("unknown component") },
        )
        val answer = try {
            switcher.choose(AppIconChoice.ARC)
        } catch (failure: RuntimeException) {
            thrown = failure
            true
        }
        assertEquals(null, thrown)
        assertFalse(answer)
    }

    /**
     * A platform that will not answer a *read* is the default, not a crash.
     *
     * Reachable in ordinary use: a component the platform does not recognise answers with an
     * `IllegalArgumentException`, and `applied()` is called while a settings screen is being
     * composed — the one moment where a throw is a blank screen rather than a refusal.
     *
     * **The default here and `null` in the test below are deliberately different answers to
     * two different devices**, and this pair used to be one assertion covering both. A device
     * that cannot report a component's state is one where nothing has changed it, so the
     * default is the honest answer and the chooser marks Ink. A device that reports every
     * component *off* has had them changed and has no launcher entry left; answering the
     * default there is the defect the next test pins.
     */
    @Test
    fun `a platform that will not report a component reads as the default`() {
        val switcher = AppIconSwitcher(
            read = { throw IllegalArgumentException("unknown component") },
            write = { _, _ -> },
        )
        assertEquals(AppIconChoice.DEFAULT, switcher.applied())
    }

    /**
     * **Every alias off is the one state a reader cannot see their way out of, and the app must
     * not be the thing standing in the way.**
     *
     * `AppIconAliases` calls zero enabled unrecoverable without a reinstall, and its own plans
     * never produce it — but the platform can arrive there without this app: a package tool can
     * disable the component that was on, and `COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED`,
     * which the platform sets on a component it has parked, is read as off by `stateOf`.
     *
     * While `applied()` answered [AppIconChoice.DEFAULT] here, the chooser marked Ink as in use
     * and `AppIconGroup`'s `if (applied != face)` guard then refused a press on Ink as a press
     * on the face already drawn — so the single press that puts the launcher entry back was the
     * one press the app would not perform. `null` equals no face, which is why the guard now
     * lets it through, and that comparison is asserted here rather than left to be read off the
     * composable.
     */
    @Test
    fun `a device with every alias off reports no face and recovers on one press`() {
        val device = FakeDevice()
        AppIconChoice.entries.forEach { device.states[it] = AppIconAliasState.DISABLED }
        val switcher = device.switcher
        assertEquals("the device this test is about was not built", 0, device.visible())

        assertNull("nothing is enabled, so no face is in use", switcher.applied())
        // The chooser's own guard, as it is written. `null` must equal no face — least of all
        // the default, whose row is the way back.
        AppIconChoice.entries.forEach {
            assertNotEquals("$it would read as in use on a device drawing nothing", it, switcher.applied())
        }

        assertTrue("the recovery press was refused", switcher.choose(AppIconChoice.DEFAULT))
        assertEquals(1, device.visible())
        assertEquals(AppIconChoice.DEFAULT, switcher.applied())
    }

    /** And from that state any face recovers, not only the default's row. */
    @Test
    fun `every face is a way back from a device with every alias off`() {
        for (face in AppIconChoice.entries) {
            val device = FakeDevice()
            AppIconChoice.entries.forEach { device.states[it] = AppIconAliasState.DISABLED }
            val switcher = device.switcher
            assertTrue("$face was refused as a recovery", switcher.choose(face))
            assertEquals("$face left more than one icon", 1, device.visible())
            assertEquals(face, switcher.applied())
        }
    }

    /** The default face goes by the same route, and lands on the manifest's own states. */
    @Test
    fun `returning to the default writes what a fresh install holds`() {
        val device = FakeDevice()
        val fresh = device.states.toMap()
        assertTrue(device.switcher.choose(AppIconChoice.MONO))
        assertTrue(device.switcher.choose(AppIconChoice.DEFAULT))
        assertEquals(fresh, device.states.toMap())
    }
}
