package app.storyarc.feature.epubreader

import app.storyarc.core.model.ElementLocator
import app.storyarc.core.model.ReadingPosition
import org.json.JSONObject
import org.readium.r2.shared.publication.Locator

/**
 * The first visible element of a reflowable page: taken when a position is saved, and used
 * when a position is resumed. `reading-progress`, decision O27.
 *
 * Readium's own `firstVisibleElementLocator()` names an element that can start on the page
 * before, so a resume at its start opens one page early. [script] keeps Readium's element,
 * and then finds the first character of it that is on screen. A resume anchors on the text
 * around that character, and Readium opens the page that holds it.
 *
 * iOS's `FirstVisibleElement` runs the same script and applies the same rule.
 */
internal object FirstVisibleElement {

    /** Answers `{cssSelector, before, after}` for the page on screen, or null. */
    val script = """
        (function () {
          var found = readium.findFirstVisibleLocator();
          var selector = found && found.locations && found.locations.cssSelector;
          var root = (selector && document.querySelector(selector)) || document.body;
          var range = document.createRange();
          function seen(node, i) {
            range.setStart(node, i);
            range.setEnd(node, i + 1);
            var r = range.getBoundingClientRect();
            return r.right > 0 && r.left < window.innerWidth && r.bottom > 0 && r.top < window.innerHeight;
          }
          var text = root.textContent;
          var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
          var offset = 0;
          var node;
          while ((node = walker.nextNode())) {
            var last = node.data.search(/\S\s*${'$'}/);
            if (last >= 0 && seen(node, last)) {
              var low = 0;
              var high = last;
              while (low < high) {
                var mid = (low + high) >> 1;
                if (seen(node, mid)) { high = mid; } else { low = mid + 1; }
              }
              offset += low;
              return {
                cssSelector: selector,
                before: text.slice(Math.max(0, offset - ${ElementLocator.TEXT_LIMIT}), offset),
                after: text.slice(offset, offset + ${ElementLocator.TEXT_LIMIT})
              };
            }
            offset += node.length;
          }
          return null;
        })();
    """.trimIndent()

    /** The element in the script's answer, or null when the page has no text to anchor on. */
    fun parse(answer: String?, href: String, digest: String?): ElementLocator? {
        val found = answer?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null
        fun field(name: String) = if (found.isNull(name)) null else found.optString(name)
        return ElementLocator.captured(href, field("cssSelector"), field("before"), field("after"), digest)
    }

    /**
     * Where a resume opens: the stored element when it is in the same file and the same
     * resource as [fallback], and [fallback] (the fraction's place) otherwise.
     *
     * The element keeps the fallback's href and progressions, and adds the selector and the
     * text. Readium goes to a locator by its text when the text has a highlight, so the text
     * after the point is the highlight and the text before it is the prefix.
     */
    fun resume(fallback: Locator?, position: ReadingPosition, digest: String?): Locator? {
        val element = (position as? ReadingPosition.Reflowable)?.firstVisibleElement ?: return fallback
        if (fallback == null || !element.resumes(digest, fallback.href.toString())) return fallback
        return fallback.copy(
            locations = fallback.locations.copy(
                otherLocations = fallback.locations.otherLocations + ("cssSelector" to element.cssSelector),
            ),
            text = Locator.Text(before = element.textBefore, highlight = element.textAfter),
        )
    }
}
