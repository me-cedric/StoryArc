import Foundation
import WebKit

/// Stops a publication reaching the network from the Mac's EPUB web view.
///
/// ADR-0015, as `design.md` Decision 6 binds it on every desktop: a compiled
/// `WKContentRuleList` denies every load whose URL is not on the app's own scheme, and
/// every response the scheme handler answers carries a Content-Security-Policy header that
/// says the same thing a second way, for the paths a rule list does not see. The rules are
/// the iOS `PublicationEgress` list with the scheme renamed: `readium` there is the
/// navigator's, `storyarc-epub` here is `EpubSchemeHandler`'s. `Tests/EpubEgressTests.swift`
/// loads the shared eight-vector page through both and counts arrivals at a loopback
/// collector. Task 4.5.
@MainActor
enum EpubEgress {
    /// The one scheme the web view may load from. The host of a URL names the publication.
    nonisolated static let scheme = "storyarc-epub"

    /// Deny everything, then let back what the app serves itself. Last match wins, which
    /// is why the blanket block comes first. `about`, `data` and `blob` are bytes the page
    /// already holds: the renderer builds each chapter as a `blob:` document.
    static let rules = """
        [
          { "trigger": { "url-filter": ".*" }, "action": { "type": "block" } },
          { "trigger": { "url-filter": "^\(scheme)://" },
            "action": { "type": "ignore-previous-rules" } },
          { "trigger": { "url-filter": "^about:" },
            "action": { "type": "ignore-previous-rules" } },
          { "trigger": { "url-filter": "^data:" },
            "action": { "type": "ignore-previous-rules" } },
          { "trigger": { "url-filter": "^blob:" },
            "action": { "type": "ignore-previous-rules" } }
        ]
        """

    /// The header on every response. Nothing by default; the scheme, `blob:` and `data:`
    /// for each kind of load the renderer and a book make; inline scripts and styles stay
    /// allowed because a publication's own markup carries them and the renderer injects
    /// its own; no form may be submitted and no base may be moved.
    static let contentSecurityPolicy = [
        "default-src 'none'",
        "script-src 'self' \(scheme): blob: 'unsafe-inline' 'unsafe-eval'",
        "style-src 'self' \(scheme): blob: 'unsafe-inline'",
        "img-src 'self' \(scheme): blob: data:",
        "font-src 'self' \(scheme): blob: data:",
        "media-src 'self' \(scheme): blob: data:",
        "connect-src 'self' \(scheme): blob: data:",
        "frame-src 'self' \(scheme): blob: about:",
        "child-src 'self' \(scheme): blob: about:",
        "worker-src 'self' \(scheme): blob:",
        "form-action 'none'",
        "base-uri 'none'",
    ].joined(separator: "; ")

    private static let identifier = "app.storyarc.mac.publication-egress"
    private static var compiled: WKContentRuleList?

    /// Compiles the list once per run. Awaited before a web view is made, because the
    /// first page it loads is the one a beacon would be on.
    static func prepare() async {
        guard compiled == nil else { return }
        compiled = try? await WKContentRuleListStore.default()
            .compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules)
    }

    /// Whether `prepare()` has a list to install. A web view is not opened without one.
    static var isPrepared: Bool { compiled != nil }

    /// Installs the list on a web view's content controller.
    static func deny(_ controller: WKUserContentController) {
        guard let compiled else { return }
        controller.add(compiled)
    }
}
