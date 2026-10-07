package app.storyarc.feature.settings

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AcknowledgementsTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val notices get() = Notices.forAndroid(context.assets).getOrThrow()

    @Test
    fun `the inventory reaches the app rather than staying in the repository`() {
        assertTrue(
            "The app ships no acknowledgements at all. The licence inventory did not reach" +
                " the assets, so the About screen draws a heading over nothing.",
            notices.isNotEmpty(),
        )
    }

    @Test
    fun `every listed component ships the licence text it names`() {
        notices.forEach { notice ->
            val text = Notices.text(context.assets, notice)
            assertTrue(
                "${notice.name} names the ${notice.licence} licence and this build carries no" +
                    " text for it, so its row opens on a packaging-bug message.",
                !text.isNullOrBlank(),
            )
        }
    }

    @Test
    fun `the list holds this platform's components and not the other app's`() {
        assertTrue(
            "No listed component names Android, so the platform filter matched nothing.",
            notices.any { it.platforms.contains("android") },
        )
        notices.forEach { notice ->
            assertTrue(
                "${notice.name} is the other app's: it declares ${notice.platforms}.",
                notice.platforms.isEmpty() || notice.platforms.contains("android"),
            )
        }
    }

    @Test
    fun `every listed component states why it is here`() {
        notices.forEach { notice ->
            assertTrue("${notice.name} has no name", notice.name.isNotBlank())
            assertTrue("${notice.name} states no reason", notice.why.isNotBlank())
            assertTrue("${notice.name} names no licence", notice.licence.isNotBlank())
        }
    }

    /**
     * Everything the APK carries beyond AndroidX and Kotlin, named.
     *
     * `settings-and-about` asks for *every* third-party library, and the inventory listed the
     * two toolkits and the fonts only. These eleven are the rest of the release runtime
     * classpath: `smbj` comes from `apps/android/core/smb/build.gradle.kts` and brings
     * `bcprov`, `asn-one`, MBassador and `SLF4J`, `desugar_jdk_libs` comes from the two
     * `coreLibraryDesugaring` lines, `jsoup`, `Timber` and `Koi` arrive through the Readium
     * toolkit, `Guava` through media3 and `JSpecify` through `jsoup` and `Guava`.
     *
     * `media3` itself is deliberately absent: it is `androidx.media3`, which the AndroidX
     * entry already covers.
     */
    @Test
    fun `every library the APK carries beyond AndroidX and Kotlin has an entry`() {
        val shipped = mapOf(
            "smbj" to "com.hierynomus:smbj",
            "ASN.1 (asn-one)" to "com.hierynomus:asn-one",
            "MBassador" to "net.engio",
            "Bouncy Castle" to "org.bouncycastle",
            "desugar_jdk_libs" to "com.android.tools",
            "jsoup" to "org.jsoup",
            "SLF4J API" to "org.slf4j",
            "Timber" to "com.jakewharton.timber",
            "Koi" to "com.mcxiaoke.koi",
            "Guava" to "com.google.guava",
            "JSpecify" to "org.jspecify",
        )

        shipped.forEach { (name, group) ->
            assertTrue(
                "$group ships in the APK and the acknowledgements list no \"$name\" row," +
                    " so the screen claims a library the reader is running is not there.",
                notices.any { it.name == name },
            )
        }
    }

    /**
     * No component is LGPL any more.
     *
     * `jcifs-ng` was the one LGPL-2.1-or-later entry, and ADR-0018 replaced it with `smbj`,
     * which is Apache-2.0. An LGPL row that came back would bring back the relinking duty
     * the replacement removed, so it fails here by name.
     */
    @Test
    fun `no component is LGPL, and the SMB client is under the Apache licence`() {
        val lesser = notices.filter { it.licence.startsWith("LGPL") }.map { it.name }
        assertTrue("LGPL components are listed: $lesser", lesser.isEmpty())

        val smbj = notices.firstOrNull { it.name == "smbj" }
            ?: error("smbj has no entry, so the SMB client the APK runs is not acknowledged.")
        assertTrue("smbj declares ${smbj.licence}", smbj.licence == "Apache-2.0")
        assertTrue(
            "The smbj row opens on text that is not the Apache licence.",
            Notices.text(context.assets, smbj).orEmpty().contains("Apache License", ignoreCase = true),
        )
    }

    /**
     * A broken inventory is reported rather than swallowed.
     *
     * It used to return an empty list, which the About screen drew as a heading over nothing —
     * indistinguishable from an app that ships nothing of anyone else's.
     */
    @Test
    fun `an inventory that does not decode is a failure rather than an empty list`() {
        val outcome = runCatching { Notices.decode("{ \"notices\": [ { \"name\": 7 } ] }") }

        assertTrue(
            "A malformed inventory decoded to ${outcome.getOrNull()}. Swallowing it is what" +
                " emptied the acknowledgements section with no word to the reader.",
            outcome.isFailure,
        )
    }

    /**
     * An entry with no `platforms` is listed, not rejected.
     *
     * `scripts/notices.mjs` has always read `platforms` as optional and falls back to
     * "iOS, Android". The iOS decode required it, so an entry written the way the generator
     * allows failed the decode of the whole file on one platform and not the other.
     */
    @Test
    fun `an entry that names no platform is listed on this one`() {
        val entry = """
            { "notices": [ { "name": "Example", "licence": "MIT",
              "url": "https://example.invalid", "why": "A test entry." } ] }
        """.trimIndent()

        val listed = Notices.decode(entry)

        assertTrue(
            "An entry with no platforms list was dropped, so the generator and this decode" +
                " disagree about the same file.",
            listed.map { it.name } == listOf("Example"),
        )
    }
}
