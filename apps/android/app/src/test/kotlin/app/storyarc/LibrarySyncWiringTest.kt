package app.storyarc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-sync` tasks 4.1 and 4.2: where the triggers are wired. The runner's own rules are
 * `LibrarySyncRunnerTest`'s; this guards that the app calls it at the moments the spec names,
 * which spread across composables and an activity result a behavioural test cannot reach. The
 * same shape as `EpubNextOfferWiringTest`.
 */
class LibrarySyncWiringTest {

    @Test
    fun `the foreground asks for a sync, launched so it never holds the first frame`() {
        val wiring = read(WIRING)
        assertTrue(
            "LibrarySyncEffects no longer runs a foreground sync on ON_RESUME.",
            wiring.contains("LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {\n" +
                "        host.activity.lifecycleScope.launch { runner.run(LibrarySyncRunner.Trigger.FOREGROUND) }"),
        )
        assertTrue("AppShell no longer draws LibrarySyncEffects.", read(APP_SHELL).contains("LibrarySyncEffects(host, onSettingsChange)"))
    }

    @Test
    fun `after a sync the app reloads what it holds, and the job follows the setting`() {
        val wiring = read(WIRING)
        assertTrue(wiring.contains("host.library.reloadAfterImport()"))
        assertTrue(wiring.contains("onSettingsChange(host.dependencies.settings.settings())"))
        assertTrue(wiring.contains("LibrarySyncJob.update(host.activity, isOn = status != SyncStatus.Off)"))
    }

    @Test
    fun `closing either reader syncs that publication`() {
        assertTrue(
            "ReaderHost no longer syncs the publication it closes.",
            read(READER_HOST).contains("activity.lifecycleScope.launch { report() }\n                host.syncAfterLeaving(publication)"),
        )
        assertTrue(
            "AppShell no longer syncs the EPUB the reader came back from.",
            read(APP_SHELL).contains("epubOpen.value?.let(host::syncAfterLeaving)"),
        )
        assertTrue(
            "A Kavita publication is no longer told apart when the reader leaves it.",
            read(WIRING).contains("val ownedByKavita = dependencies.kavitaProgress.origin(publication.id) != null"),
        )
    }

    @Test
    fun `settings shows the process's one runner`() {
        assertTrue(read(SETTINGS_HOST).contains("syncRunner = LibrarySyncHub.runner(context)"))
    }

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        if (!file.isFile) error("$path is not under ${androidRoot.absolutePath} — has it moved?")
        return file.readText()
    }

    private companion object {
        const val APP_SHELL = "app/src/main/kotlin/app/storyarc/AppShell.kt"
        const val READER_HOST = "app/src/main/kotlin/app/storyarc/ReaderHost.kt"
        const val SETTINGS_HOST = "app/src/main/kotlin/app/storyarc/SettingsHost.kt"
        const val WIRING = "app/src/main/kotlin/app/storyarc/LibrarySyncWiring.kt"

        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
