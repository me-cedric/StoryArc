package app.storyarc.feature.settings

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * `library-portability` tasks 2.4, 5.3 and 6.8: every transfer string is written in all four
 * languages, and a plural has both forms in each. Android's own lint fails a missing translation;
 * this names the rows this change owes, so a string dropped from one language fails here by name.
 * iOS's `ImportPreviewLineViewTests` asserts the same of its catalogue.
 */
class TransferStringsTest {

    private val languages = mapOf(
        "en" to "values",
        "fr" to "values-fr",
        "de" to "values-de",
        "es" to "values-es",
    )

    private class Entry(val name: String, val forms: List<String>)

    private fun transferEntries(folder: String): List<Entry> {
        val file = File("src/main/res/$folder/strings.xml")
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val entries = mutableListOf<Entry>()
        val nodes = document.documentElement.childNodes
        for (index in 0 until nodes.length) {
            val node = nodes.item(index) as? Element ?: continue
            val name = node.getAttribute("name")
            if (!name.startsWith("transfer_")) continue
            when (node.tagName) {
                "string" -> entries += Entry(name, listOf(node.textContent))
                "plurals" -> {
                    val items = node.getElementsByTagName("item")
                    entries += Entry(
                        name,
                        (0 until items.length).map { (items.item(it) as Element).getAttribute("quantity") },
                    )
                }
            }
        }
        return entries
    }

    @Test
    fun `every transfer string English defines is defined in French, German and Spanish`() {
        val english = transferEntries("values").map { it.name }.toSet()
        assertTrue("English defines too few transfer strings: ${english.size}", english.size > 40)

        for ((language, folder) in languages) {
            assertEquals("$language lacks or adds a transfer string", english, transferEntries(folder).map { it.name }.toSet())
        }
    }

    @Test
    fun `every plural has a one and an other form in each language`() {
        for ((language, folder) in languages) {
            transferEntries(folder).filter { it.forms.any { form -> form == "one" || form == "other" } }.forEach {
                assertEquals("$language ${it.name}", listOf("one", "other"), it.forms)
            }
        }
    }

    @Test
    fun `no transfer string is empty in any language`() {
        for ((language, folder) in languages) {
            transferEntries(folder).filter { it.forms.size == 1 && it.forms[0] !in setOf("one", "other") }.forEach {
                assertTrue("$language ${it.name} is empty", it.forms[0].isNotBlank())
            }
        }
    }

    @Test
    fun `the sentence that says what an export is not is written in every language`() {
        for ((language, folder) in languages) {
            val sentence = transferEntries(folder).first { it.name == "transfer_export_not_what" }.forms.single()
            assertTrue("$language is too short to be the sentence", sentence.length > 40)
        }
        val english = transferEntries("values").first { it.name == "transfer_export_not_what" }.forms.single()
        assertTrue(english.contains("cover cache") && english.contains("downloads"))
    }
}
