package app.storyarc.core.format

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File

/**
 * Locates the shared fixture corpus at `packages/test-fixtures`.
 *
 * The corpus lives outside this module on purpose — both platforms read the same
 * files, which is what stops the two implementations from quietly disagreeing
 * about what a correct parse is (ADR-0001). The path arrives as a system
 * property set by the module's build script, with a walk-up fallback so the
 * tests also run when launched from an IDE.
 */
object FixtureCorpus {
    val root: File by lazy {
        System.getProperty("storyarc.fixtures")?.let(::File)?.takeIf { it.isDirectory }
            ?: walkUpForCorpus()
            ?: error("fixture corpus not found — expected packages/test-fixtures above ${File("").absolutePath}")
    }

    private fun walkUpForCorpus(): File? {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, "packages/test-fixtures")
            if (File(candidate, "manifest.json").isFile) return candidate
            dir = dir.parentFile
        }
        return null
    }

    fun file(relativePath: String): File = File(root, relativePath)

    /** One entry from `manifest.json`, which records what a correct parse yields. */
    data class Fixture(
        val file: String,
        val pins: String,
        val expectedPageCount: Int?,
        val expectedPageOrder: List<String>?,
        val isRecoverable: Boolean?,
        val actualContainer: String?,
        val hasComicInfo: Boolean?,
        val expectedSeries: String?,
        val spreadIndices: List<Int>?,
    )

    val comics: List<Fixture> by lazy {
        val root = Json.parseToJsonElement(file("manifest.json").readText()).jsonObject
        root.getValue("comics").jsonArray.map { element ->
            val obj = element.jsonObject
            fun str(key: String) = obj[key]?.jsonPrimitive?.contentOrNull
            fun int(key: String) = obj[key]?.jsonPrimitive?.intOrNull
            fun bool(key: String) = obj[key]?.jsonPrimitive?.booleanOrNull
            fun strings(key: String) =
                obj[key]?.takeIf { it !is kotlinx.serialization.json.JsonNull }
                    ?.jsonArray?.map { it.jsonPrimitive.content }
            fun ints(key: String) =
                obj[key]?.takeIf { it !is kotlinx.serialization.json.JsonNull }
                    ?.jsonArray?.map { it.jsonPrimitive.content.toInt() }

            Fixture(
                file = str("file")!!,
                pins = str("pins")!!,
                expectedPageCount = int("expectedPageCount"),
                expectedPageOrder = strings("expectedPageOrder"),
                isRecoverable = bool("isRecoverable"),
                actualContainer = str("actualContainer"),
                hasComicInfo = bool("hasComicInfo"),
                expectedSeries = str("expectedSeries"),
                spreadIndices = ints("spreadIndices"),
            )
        }
    }

    fun comic(name: String): Fixture =
        comics.firstOrNull { it.file == "comics/$name" }
            ?: error("no fixture named $name in manifest.json")
}
