package app.storyarc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That resetting settings actually clears Natural, on the shell that owns the reset button.
 *
 * Task 19.1: reset cleared the two settings stores and left `NaturalTheme`'s own preference
 * untouched, so Appearance did not "go back to how it started" after all. The fix landed in
 * commit `442c3da2` with no test on either platform — `NaturalSettingTest.kt` pins what
 * `NaturalTheme.set` itself does and cannot see whether reset calls it; this is the half that
 * reads the call site, in the manner of `WhatsNewWiringTest` one file away.
 *
 * **Source text, not a composed screen.** `onResetSettings` is a lambda built inside
 * `MainActivity.setContent`, which this module declares no Robolectric Compose rule to drive,
 * and `ShelvesAskOneRuleTest` sets out at length why `:app` reads its own sources instead. A
 * tripwire, not a proof: it asserts the call is written, never that Appearance redrew.
 * `pnpm capture:android Settings` is what photographs the screen it leaves correctly reset.
 */
class ResetClearsNaturalWiringTest {

    @Test
    fun `resetting settings clears Natural too, not only the two stores`() {
        val mainActivity = read("app/src/main/kotlin/app/storyarc/MainActivity.kt")
        val onReset = onResetSettingsBody(mainActivity)

        assertTrue(
            "onResetSettings no longer calls dependencies.settings.reset() — the settings" +
                " store itself would survive a reset.",
            onReset.contains("dependencies.settings.reset()"),
        )
        assertTrue(
            "onResetSettings no longer clears NaturalTheme. Appearance would stop going" +
                " \"back to how it started\" the moment a reader turns Natural on.",
            onReset.contains("NaturalTheme.set(this@MainActivity, false)"),
        )
    }

    /** Just the `onResetSettings = { ... }` lambda's own body, bracket-matched. */
    private fun onResetSettingsBody(source: String): String {
        val key = "onResetSettings = {"
        val open = source.indexOf(key).let {
            check(it >= 0) { "MainActivity.kt no longer declares onResetSettings = { ... } — has it moved?" }
            it + key.length - 1
        }
        var depth = 1
        var i = open + 1
        while (depth > 0) {
            when (source[i]) {
                '{' -> depth++
                '}' -> depth--
            }
            i++
        }
        return source.substring(open, i)
    }

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        if (!file.isFile) error("$path is not under ${androidRoot.absolutePath} — has it moved?")
        return file.readText()
    }

    private companion object {
        /**
         * The Gradle root, found by walking up from the working directory, per
         * `ShelvesAskOneRuleTest`: the walk starts inside `:app` and stops at the first
         * ancestor holding the settings script, so it cannot climb out of an agent worktree
         * into the parent checkout.
         */
        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
