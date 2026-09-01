package app.storyarc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That what changed is presented from the shell, that About cannot record anything, and that
 * nothing about it is ever fetched.
 *
 * **This file was named by a test comment before it existed.** `WhatsNewTest.kt` said
 * "`WhatsNewWiringTest` is the half of this claim that a mutation can break" about the claim
 * that reaching the log from About changes nothing — and no such file was here. So the Android
 * gate stayed green through deleting the `ModalBottomSheet` from `AppShell`, through handing
 * [app.storyarc.feature.settings.WhatsNewHistory] a store, and through adding a fetch to the
 * log. iOS had all three halves in `WhatsNewWiringTests.swift`; this is the twin.
 *
 * `WhatsNewTest` pins the *decision* — once per version, never on a first launch, always
 * recorded — and `WhatsNewLayoutTest` pins the *layout* at the largest text size. Neither can
 * pin any of the three claims below, because each is a property of a call site or an absence:
 *
 * - the sheet is presented **from `AppShell`**, on the launch after an update. Delete it and
 *   every unit test, `lint` and both compile gates stay green while the app never tells anybody
 *   anything again;
 * - reaching it from About "does not change what the app considers seen". The way that is held
 *   is that `WhatsNewHistory` takes a list of releases and has no store — and nothing stops a
 *   later edit from handing it one;
 * - the log "ships with the app and is never fetched". Both sources say so in prose and both
 *   are correct by construction, and until this file nothing would have failed if a fetch were
 *   added.
 *
 * **So it reads Kotlin source, which wants justifying.** `AppShell` is `@Composable` and `:app`
 * declares no Robolectric or Compose test rule, so no unit suite can compose it; the
 * instrumented tests that could are compiled by `pnpm build:android:tests` and *run* by
 * nothing. `ShelvesAskOneRuleTest` sets the pattern out at length one file away, including the
 * part that makes it hold on an incremental build: `app/build.gradle.kts` declares every `.kt`
 * under the Gradle root as an input of this task, so a change in `:feature:settings` does not
 * leave this UP-TO-DATE.
 *
 * A tripwire, not a proof. It asserts a presentation is declared and two things are absent; it
 * never asserts a sheet appeared. `pnpm capture:android WhatsNew` is what photographs it.
 */
class WhatsNewWiringTest {

    @Test
    fun `the shell presents what changed on the launch after an update`() {
        val shell = read(APP_SHELL)

        assertTrue(
            "AppShell no longer asks whether this launch is the one that says what changed.",
            shell.contains("WhatsNew.onLaunch("),
        )
        assertTrue(
            "AppShell no longer presents the what's-new sheet. A reader who updates learns" +
                " nothing, and nothing else in this repository fails.",
            shell.contains("WhatsNewSheet(release = release, onDismiss ="),
        )
    }

    @Test
    fun `no screen in settings can record a version as seen`() {
        // `settings-and-about`: reaching the screen from About "does not change what the app
        // considers seen", and the way that is held is that no screen there has a store to
        // write to. `WhatsNew.kt` is the exception because the store is its own parameter —
        // the recording happens in `onLaunch`, which the shell calls and About does not.
        for (file in settingsSources().filter { it.name != "WhatsNew.kt" }) {
            assertTrue(
                "${file.name} reaches WhatsNewStore. Reading the log from About would then" +
                    " write a flag, and a reader who browsed the history would never be told" +
                    " about the next update.",
                !codeOnly(file.readText()).contains("WhatsNewStore"),
            )
        }
    }

    @Test
    fun `what changed is never fetched, on either screen`() {
        // `settings-and-about`'s *An update installed while offline*: "the screen appears in
        // full, because what changed ships with the app and is never fetched" — which is the
        // launch after an update, and may well be a launch with no network at all.
        //
        // Comment lines are stripped first, and that is what makes the test possible: both
        // files use the words *fetched* and *parser* to explain why there is neither, so a
        // naive search of the whole text fails on the prose documenting the rule it guards.
        for (name in listOf("WhatsNew.kt", "WhatsNewSheet.kt")) {
            val code = codeOnly(read("feature/settings/src/main/kotlin/app/storyarc/feature/settings/$name"))
            for (symbol in NETWORK_SYMBOLS) {
                assertTrue(
                    "$name names $symbol in code rather than in prose. The what's-new log" +
                        " ships with the app; a reader on a train sees it in full.",
                    !code.contains(symbol),
                )
            }
        }
    }

    // Reading the tree

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        if (!file.isFile) {
            error("$path is not under ${androidRoot.absolutePath} — has it moved?")
        }
        return file.readText()
    }

    /**
     * Every Kotlin source in `:feature:settings`, so a new screen is covered without being
     * named. A hand-written list goes stale the first time somebody adds a file, and the file
     * they add is exactly the one that would slip through.
     */
    private fun settingsSources(): List<File> {
        val directory = File(androidRoot, "feature/settings/src/main/kotlin/app/storyarc/feature/settings")
        val names = directory.listFiles { file: File -> file.name.endsWith(".kt") }?.toList()
            ?: error("${directory.absolutePath} could not be listed — has :feature:settings moved?")
        assertTrue("Only ${names.size} sources found in :feature:settings. Suspicious.", names.size > 5)
        return names
    }

    /**
     * A source's text with every comment line removed.
     *
     * Line comments and KDoc bodies both go. Crude — a trailing comment on a line of code
     * survives — and that is the right direction to be crude in: these are negative
     * assertions, so keeping too much code fails loudly and keeping too little passes quietly.
     */
    private fun codeOnly(text: String): String {
        var inBlock = false
        val kept = mutableListOf<String>()
        for (raw in text.lineSequence()) {
            val line = raw.trim()
            if (inBlock) {
                if (line.contains("*/")) inBlock = false
                continue
            }
            if (line.startsWith("/*")) {
                if (!line.contains("*/")) inBlock = true
                continue
            }
            if (line.startsWith("//") || line.startsWith("*")) continue
            kept += line
        }
        return kept.joinToString("\n")
    }

    private companion object {
        const val APP_SHELL = "app/src/main/kotlin/app/storyarc/AppShell.kt"

        /**
         * Anything that could reach the network from a Kotlin file in this app.
         *
         * Not exhaustive and not meant to be: every way this codebase actually reaches a
         * server, plus the JDK types anything new would be built out of.
         */
        val NETWORK_SYMBOLS = listOf(
            "OkHttp",
            "okhttp",
            "HttpURLConnection",
            "URLConnection",
            "java.net",
            "HttpClient",
            "Retrofit",
            "URL(",
            "http://",
            "https://",
        )

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
