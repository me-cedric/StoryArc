internal import Foundation

internal import ReadiumNavigator
internal import ReadiumShared

internal import StoryArcCore

/// The first visible element of a reflowable page: taken when a position is saved, and used
/// when a position is resumed. `reading-progress`, decision O27.
///
/// Readium's own `firstVisibleElementLocator()` names an element that can start on the page
/// before, so a resume at its start opens one page early. The script below keeps Readium's
/// element, and then finds the first character of it that is on screen. A resume anchors on
/// the text around that character, and Readium opens the page that holds it.
///
/// Android's `FirstVisibleElement` runs the same script and applies the same rule.
enum FirstVisibleElement {

    /// Answers `{cssSelector, before, after}` for the page on screen, or null.
    static let script = """
        (function () {
          var found = readium.findFirstVisibleLocator();
          var selector = found && found.locations && found.locations.cssSelector;
          var root = (selector && document.querySelector(selector)) || document.body;
          var range = document.createRange();
          function box(node, i) {
            range.setStart(node, i);
            range.setEnd(node, i + 1);
            return range.getBoundingClientRect();
          }
          function reached(node, i) {
            var r = box(node, i);
            return r.right > 0 && r.bottom > 0;
          }
          function seen(node, i) {
            var r = box(node, i);
            return reached(node, i) && r.left < window.innerWidth && r.top < window.innerHeight;
          }
          var text = root.textContent;
          var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
          var offset = 0;
          var node;
          while ((node = walker.nextNode())) {
            var last = node.data.search(/\\S\\s*$/);
            if (last >= 0 && reached(node, last)) {
              var low = 0;
              var high = last;
              while (low < high) {
                var mid = (low + high) >> 1;
                if (reached(node, mid)) { high = mid; } else { low = mid + 1; }
              }
              if (!seen(node, low)) { return null; }
              offset += low;
              return {
                cssSelector: selector,
                before: text.slice(Math.max(0, offset - \(ElementLocator.textLimit)), offset),
                after: text.slice(offset, offset + \(ElementLocator.textLimit))
              };
            }
            offset += node.length;
          }
          return null;
        })();
        """

    /// The element on screen now, or nil when the page has no text to anchor on.
    @MainActor
    static func capture(
        from navigator: EPUBNavigatorViewController?,
        href: String,
        digest: String?
    ) async -> ElementLocator? {
        guard let navigator,
              case let .success(value) = await navigator.evaluateJavaScript(script),
              let found = value as? [String: Any]
        else { return nil }
        return ElementLocator.captured(
            href: href,
            cssSelector: found["cssSelector"] as? String,
            textBefore: found["before"] as? String,
            textAfter: found["after"] as? String,
            publicationDigest: digest
        )
    }

    /// Where a resume opens: the stored element when it is in the same file and the same
    /// resource as `fallback`, and `fallback` (the fraction's place) otherwise.
    ///
    /// The element keeps the fallback's href and progressions, and adds the selector and the
    /// text. Readium goes to a locator by its text when the text has a highlight, so the
    /// text after the point is the highlight and the text before it is the prefix.
    static func resume(_ fallback: Locator?, from position: ReadingPosition, digest: String?) -> Locator? {
        guard let fallback,
              case let .reflowable(_, _, element?) = position,
              element.resumes(publicationDigest: digest, resource: fallback.href.string)
        else { return fallback }
        return fallback.copy(
            locations: { $0.cssSelector = element.cssSelector },
            text: { $0 = Locator.Text(before: element.textBefore, highlight: element.textAfter) }
        )
    }
}
