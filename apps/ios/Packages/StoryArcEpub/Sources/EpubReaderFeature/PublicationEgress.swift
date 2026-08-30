internal import Foundation
internal import WebKit

/// Stops a publication reaching the network.
///
/// ADR-0015. A reflowable EPUB is HTML rendered in a real web view, and HTML that is
/// only being read can still fetch: a one-pixel image, a script's `fetch`, a
/// `sendBeacon`, a socket, a frame, a redirect. None of it needs the reader to touch
/// anything, and the host on the other end learns the device's address, the moment of
/// reading and — through a URL the publication's author chose — which book and which
/// chapter. `README.md` promises data leaves the device only for sources the reader
/// configured, and a publication is not one of them.
///
/// One lever, and it is WebKit's own: a compiled ``WKContentRuleList`` blocks every
/// load whose URL is not the publication's own. It sits below the page rather than
/// inside it, so it does not care which API a script used — ``PublicationEgressTests``
/// fires eight vectors at a listener on the device's own loopback and none arrive.
///
/// Nothing in Readium's rendering path is touched. `EPUBNavigatorViewController` hands
/// the app the live `WKUserContentController` of each spread through
/// `setupUserScripts`, which is where this is installed; everything the navigator
/// serves — the resource, ReadiumCSS, its injected scripts, the bundled fonts — is on
/// the `readium` scheme and is let through.
///
/// What it costs: a publication that genuinely references a remote font, image or
/// stylesheet loses it. That is deliberate. Those are not features of this app; a
/// publication reaching out is the defect. Nothing is said about it on screen — the
/// posture is recorded in the repository, not in the reader's page.
///
/// Scripting stays on. Readium drives pagination, locators, decorations and selection
/// through injected `WKUserScript`s, and a publication's own scripts are part of what
/// it renders. Blocking egress is not the same as blocking scripting, and only the
/// first is free.
@MainActor
enum PublicationEgress {

    /// Deny everything, then let back the schemes the app itself serves.
    ///
    /// `readium` is the navigator's scheme — `WebViewServer` is constructed with it,
    /// and both the publication's resources and the toolkit's static assets are served
    /// under it. `about` covers the blank document a frame starts as, and `data` and
    /// `blob` are bytes the page already holds: neither can leave the device, and
    /// blocking them would lose an embedded image for nothing.
    ///
    /// A rule list is evaluated in order and the last match wins, which is why the
    /// blanket block comes first.
    static let rules = """
        [
          { "trigger": { "url-filter": ".*" }, "action": { "type": "block" } },
          { "trigger": { "url-filter": "^readium://" },
            "action": { "type": "ignore-previous-rules" } },
          { "trigger": { "url-filter": "^about:" },
            "action": { "type": "ignore-previous-rules" } },
          { "trigger": { "url-filter": "^data:" },
            "action": { "type": "ignore-previous-rules" } },
          { "trigger": { "url-filter": "^blob:" },
            "action": { "type": "ignore-previous-rules" } }
        ]
        """

    private static let identifier = "app.storyarc.publication-egress"

    private static var compiled: WKContentRuleList?

    /// Compiles the list, once per run of the app.
    ///
    /// Awaited before the navigator is built rather than inside the delegate callback,
    /// because compilation is asynchronous and ``deny(_:)`` is not: a spread view that
    /// asked for its scripts before the list existed would render its first resource
    /// unguarded, which is the one page a beacon would be on.
    static func prepare() async {
        guard compiled == nil else { return }
        compiled = try? await WKContentRuleListStore.default()
            .compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules)
    }

    /// Installs the list on one spread's content controller.
    ///
    /// Called from `EPUBNavigatorDelegate.navigator(_:setupUserScripts:)`, which is the
    /// only supported way into a `WKWebViewConfiguration` the toolkit builds privately.
    /// The navigator issues the spread's load a moment earlier, inside the spread view's
    /// initialiser — which does not open the window it looks like: that load is the
    /// resource itself, on the `readium` scheme, and a subresource cannot be asked for
    /// until it has been fetched and parsed.
    static func deny(_ controller: WKUserContentController) {
        guard let compiled else { return }
        controller.add(compiled)
    }
}
