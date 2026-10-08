package app.storyarc

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `publication-detail` task 6.4: one queue, owned in one place.
 *
 * A second queue over the same store reclaims a running row and queues it again, and the
 * foreground service's count is then driven from two places. So two surfaces that ask for the
 * queue -- the publication page and a catalogue screen -- must get the same object, and no other
 * file may build one.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class OneDownloadQueueTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `two surfaces asking for the queue get the same one`() {
        val dependencies = AppDependencies.open(context)

        assertSame(dependencies.queue, dependencies.queue)
    }

    @Test
    fun `AppDependencies is the only place that builds a download queue`() {
        val builders = sources().filter { file ->
            CONSTRUCTION.containsMatchIn(file.readText()) && !file.name.endsWith("DownloadQueue.kt")
        }.map { it.name }

        assertEquals(
            "A download queue is built outside AppDependencies: $builders. Two queues over one store " +
                "reclaim each other's running rows.",
            listOf("AppDependencies.kt"),
            builders,
        )
    }

    /** Every production Kotlin file of the app and its feature modules. */
    private fun sources(): List<File> =
        listOf("app", "feature", "core").flatMap { top ->
            File(androidRoot, top).walkTopDown()
                .filter { it.isFile && it.extension == "kt" && "/src/main/" in it.path && "/build/" !in it.path }
                .toList()
        }

    private companion object {
        /** A call, not the class declaration and not a mention in a comment. */
        val CONSTRUCTION = Regex("""(?m)^(?!\s*(\*|//|/\*)).*(?<![\w.])(?<!class )DownloadQueue\(""")

        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("No settings.gradle.kts above ${File("").absolutePath}.")
    }
}
