package app.storyarc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `sources`' corrected note for task 22.1: a server added during a session used to join the
 * library only at the next pull or launch, because `addSource` wrote the registry and nothing
 * asked the new source for anything. Each of the three add-a-source sheets now reads every
 * server right after adding one, through the same `readServers` the library's own restore
 * calls.
 *
 * A source guard, for the reason `KeepForOfflineWiringTest` gives its own: driving the three
 * sheets end to end needs a live `AppHost` with its sheet navigation, a `Context` and
 * credentials, none of which this module's test sources can build without an instrumented
 * device.
 */
class AddSourceStartsAReadWiringTest {

    private val source = "app/src/main/kotlin/app/storyarc/AppSheets.kt"

    @Test
    fun `each add-a-source sheet reads every server right after adding`() {
        val calls = Regex(
            """onAdd = \{ host\.library\.addSource\(it\); host\.library\.readServers\(dependencies\.pins\) }""",
        ).findAll(code()).count()
        assertTrue(
            "AppSheets.kt calls addSource then readServers $calls time(s); expected 3" +
                " (the catalogue, Kavita and SMB sheets).",
            calls == 3,
        )
    }

    private fun code(): String {
        val file = File(androidRoot, source)
        assertTrue("$source has moved; this test names it by path", file.isFile)
        return file.readText()
    }

    private companion object {
        /** `apps/android`, found rather than hardcoded. See `ShelvesAskOneRuleTest`. */
        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
