import DesignSystem
import Foundation
import Persistence
import Playback
import StoryArcCore
import WebKit

/// One hit of a search in the book, as the renderer reports it.
struct EpubSearchHit: Identifiable, Equatable, Sendable {
    let id: Int
    let chapter: String?
    let before: String
    let match: String
    let after: String
    /// The locator to go to, as the renderer's JSON.
    let locator: String
}

/// One reflowable publication open in the Mac's web view, and the two-way message surface
/// of `apps/desktop-web/epub` (its README has the table).
///
/// The model owns the web view: it is made once the egress rule list has compiled, with the
/// scheme handler over `EpubArchiveSource`, a non-persistent data store and the `storyarc`
/// message door. What comes back is kept as state the window draws and the walks read:
/// `ready`, the current `locator` (written to the progress store as a reflowable position,
/// `reading-progress`), the search results and the theme in force. Commands go out as JSON
/// through `receive` on the reader the host page opened. Task 4.5.
@MainActor
@Observable
final class EpubReaderModel: NSObject {
    let target: ReaderTarget
    let publication: Publication
    private(set) var webView: WKWebView?
    private(set) var isReady = false
    private(set) var title: String?
    private(set) var positionCount = 0
    private(set) var position: Int?
    private(set) var totalProgression: Double = 0
    /// Where the reader is, as the renderer's locator JSON.
    private(set) var locator: String?
    private(set) var failure: String?
    private(set) var hits: [EpubSearchHit] = []
    private(set) var isSearching = false
    private(set) var theme: ThemePreset
    /// The manifest's table of contents, and the CSS properties the renderer last said are in force.
    private(set) var contents: [EpubWebLink] = []
    private(set) var appliedProperties: [String: String] = [:]
    /// Set by a move the app asked for, so a chapter change the renderer made on its own is known as a link.
    var isMovingItself = false
    let marks: EpubMarks
    /// Where a jump came from, so the reader can go back: *Returning from any jump*.
    var returnLocator: String?
    /// A link out of the book that waits for the reader to confirm its host; nothing is fetched before.
    var leaving: URL?
    /// Every message the renderer posted, by type, for the walks.
    private(set) var received: [String] = []
    /// What the book says, read once at open, or `nil` while it is being read.
    private(set) var chapters: SpokenChapters?
    /// The sentence the voice is on, for the window, or `nil` when it is quiet.
    private(set) var spokenSentence: String?
    var writer: ProgressWriter?

    /// The keys over the web view, installed once with it; `close()` removes them.
    private var keys: EpubKeyMonitor?
    /// What Escape does over the text: the window leaves the text for its chrome.
    var onEscape: (() -> Void)?

    private var handler: EpubSchemeHandler?
    /// Every path the scheme handler served, for the walks.
    var served: [String] { handler?.served ?? [] }
    private var searchID = 0
    private let token: String
    private let progress: ProgressStore?

    static let themeKey = "app.storyarc.mac.epubTheme"
    /// Set by a walk before `open()`: the page's console and its fetches come back as `logs`.
    static var isDebugging = false
    private(set) var logs: [String] = []

    init(target: ReaderTarget, publication: Publication, progress: ProgressStore?) {
        self.target = target
        self.publication = publication
        self.progress = progress
        token = Self.token(for: target.publicationID)
        theme = UserDefaults.standard.string(forKey: Self.themeKey).flatMap(ThemePreset.init) ?? .paper
        marks = EpubMarks(publicationID: publication.id)
    }

    /// A host name for the scheme URL: the publication's id, reduced to what a URL host takes.
    static func token(for id: String) -> String {
        let allowed = id.lowercased().filter { $0.isLetter || $0.isNumber }
        return allowed.isEmpty ? "book" : String(allowed.prefix(48))
    }

    // MARK: - Opening

    /// Builds the manifest and the web view, and loads the host page at the saved position.
    func open() async {
        guard webView == nil else { return }
        guard let bundle = EpubArchiveSource.bundledRenderer else {
            failure = "The EPUB renderer is missing from the app."
            return
        }
        let source: EpubArchiveSource
        do {
            source = try await EpubArchiveSource(url: target.url, token: token, bundle: bundle)
        } catch {
            failure = String(describing: error)
            return
        }
        // What the Mac built itself, so the chrome does not wait on the renderer for it.
        title = source.publication.manifest.metadata.title
        positionCount = source.publication.positions.count
        contents = source.publication.manifest.toc
        chapters = try? await SpokenChapters.read(url: target.url)
        await EpubEgress.prepare()
        guard EpubEgress.isPrepared else {
            failure = "The network rule list did not compile, so the book is not opened."
            return
        }
        let handler = EpubSchemeHandler(source: source)
        self.handler = handler
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(handler, forURLScheme: EpubEgress.scheme)
        configuration.userContentController.add(EpubMessageDoor(model: self), name: "storyarc")
        EpubEgress.deny(configuration.userContentController)
        if let script = await openingScript() {
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }
        let webView = EpubWebViewHost(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView
        keys = EpubKeyMonitor(over: webView) { [weak self] key in
            switch key {
            case .next: self?.next()
            case .previous: self?.previous()
            case .escape: self?.onEscape?()
            }
        }
        // Loaded once the view has a size: the renderer measures its container when the
        // page opens, and a container that is still zero by zero leaves it waiting for a
        // resize that never comes (seen in about one walk in two).
        let url = URL(string: EpubSchemeHandler.base(for: token) + EpubArchiveSource.hostPath)
        webView.onFirstLayout = { [weak webView] in
            guard let webView, let url else { return }
            webView.load(URLRequest(url: url))
        }
    }

    /// The saved locator and the theme, set on `window` before the host page runs.
    private func openingScript() async -> String? {
        var lines: [String] = []
        if Self.isDebugging { lines.append("window.__storyarcDebug = true;") }
        if let saved = try? await progress?.progress(for: publication.identity),
           case let .reflowable(_, json, _) = saved.position, !json.isEmpty {
            lines.append("window.__storyarcLocator = \(json);")
        }
        if let axes = try? JSONSerialization.data(withJSONObject: Self.readerAxes(theme)),
           let text = String(data: axes, encoding: .utf8) {
            lines.append("window.__storyarcPreferences = \(text);")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Lets the keys go when the window closes.
    func close() {
        keys?.remove()
        keys = nil
    }

    // MARK: - Read aloud

    /// Whether the Read Aloud control is drawn: a voice exists and the book has text.
    static func offersReadAloud(chapters: SpokenChapters?, voices: any SpeechVoices = MacReadAloud.voices) -> Bool {
        guard let chapters, chapters.hasSomethingToSay else { return false }
        return MacReadAloud.isAvailable(language: chapters.language, voices: voices)
    }

    var offersReadAloud: Bool { Self.offersReadAloud(chapters: chapters) }

    /// Whether the voice on the player is this book's.
    var isBeingReadAloud: Bool { PlayerCentre.shared.book?.id == publication.id && PlayerCentre.shared.isRunning }

    /// Starts the voice at the chapter of the current position, on the one player, or stops it.
    func toggleReadAloud(speaker: (any SentenceSpeaking)? = nil) {
        let centre = PlayerCentre.shared
        if isBeingReadAloud { return centre.end() }
        guard let chapters, offersReadAloud else { return }
        let href = (try? JSONSerialization.jsonObject(with: Data((locator ?? "{}").utf8))) as? [String: Any]
        let part = chapters.chapters.firstIndex { $0.href == href?["href"] as? String } ?? 0
        let source = MacSpokenSource(
            chapters: chapters, speaker: speaker ?? SystemSentenceSpeaker(),
            voice: MacReadAloud.voice(for: chapters.language), from: PlaybackPlace(partIndex: part, offset: 0)
        )
        source.onSentence = { [weak self] in self?.spokenSentence = $0 }
        MacPlayer.adoptPlatform()
        centre.begin(SpokenBook(publication: publication, url: target.url), source: source)
    }

    // MARK: - Commands

    func next() { isMovingItself = true; send(["type": "next"]) }

    func previous() { isMovingItself = true; send(["type": "previous"]) }

    /// Goes to a locator, remembering where the reader was so they can come back.
    func go(to locator: String) {
        returnLocator = self.locator
        isMovingItself = true
        send(json: "{\"type\":\"go\",\"locator\":\(locator)}")
    }

    /// Back to where the last jump left: using it is not itself a place to return from.
    func goBack() {
        guard let returnLocator else { return }
        self.returnLocator = nil
        isMovingItself = true
        send(json: "{\"type\":\"go\",\"locator\":\(returnLocator)}")
    }

    func apply(_ preset: ThemePreset) {
        theme = preset
        UserDefaults.standard.set(preset.rawValue, forKey: Self.themeKey)
        let theme: [String: AnyHashable] = ["name": preset.rawValue, "axes": Self.readerAxes(preset)]
        send(["type": "theme", "theme": theme])
    }

    /// Searches the book; a newer search silences an older one, as the renderer promises.
    func search(_ query: String) {
        searchID += 1
        hits = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = !trimmed.isEmpty
        guard !trimmed.isEmpty else { return }
        send(["type": "search", "id": searchID, "query": trimmed])
    }

    /// The axes a preset sets, in the renderer's names: the colours from the design tokens,
    /// and the publisher's stylesheet kept only by *Original* (`ReadingTheme`).
    static func axes(of preset: ThemePreset) -> [String: AnyHashable] {
        var axes: [String: AnyHashable] = ["publisherStyles": preset.keepsPublisherStyles]
        guard !preset.keepsPublisherStyles else { return axes }
        let (background, text): (String, String) = switch preset {
        case .original: (StoryArcReadingThemeHex.originalBg, StoryArcReadingThemeHex.originalFg)
        case .quiet: (StoryArcReadingThemeHex.quietBg, StoryArcReadingThemeHex.quietFg)
        case .paper: (StoryArcReadingThemeHex.paperBg, StoryArcReadingThemeHex.paperFg)
        case .bold: (StoryArcReadingThemeHex.boldBg, StoryArcReadingThemeHex.boldFg)
        case .calm: (StoryArcReadingThemeHex.calmBg, StoryArcReadingThemeHex.calmFg)
        case .focus: (StoryArcReadingThemeHex.focusBg, StoryArcReadingThemeHex.focusFg)
        }
        axes["backgroundColor"] = background
        axes["textColor"] = text
        if preset == .bold { axes["fontWeight"] = 1.5 }
        return axes
    }

    private func send(_ message: [String: AnyHashable]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8)
        else { return }
        send(json: json)
    }

    func send(json: String) {
        guard let webView, isReady else { return }
        webView.evaluateJavaScript("window.__storyarcReader && window.__storyarcReader.receive(\(json)); 0") { _, _ in }
    }

    // MARK: - What comes back

    /// One message from the renderer, as the door hands it over.
    func receive(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        received.append(type)
        switch type {
        case "ready", "locator":
            // The renderer reports its first position before its own `load()` settles, and
            // on a Mac that settlement was seen to come late or not at all: the first
            // locator is the book on screen, which is what ready means here.
            isReady = true
            guard let locator = body["locator"] as? [String: Any] else { return }
            moved(to: locator)
        case "theme", "preferences":
            appliedProperties = body["properties"] as? [String: String] ?? appliedProperties
        case "search-results":
            guard body["id"] as? Int == searchID else { return }
            let base = hits.count
            let results = body["results"] as? [[String: Any]] ?? []
            hits += results.enumerated().compactMap { EpubSearchHit.of($1, id: base + $0) }
            if body["done"] as? Bool == true { isSearching = false }
        case "link":
            leaving = Self.outward(body["href"] as? String)
        case "host-log", "host-error":
            noted(type, body["message"] as? String ?? "")
        default:
            marks.receive(type, body)
        }
    }

    private func noted(_ type: String, _ message: String) {
        if type == "host-error" { failure = message } else { logs.append(message) }
    }

    /// A link out of the book, `http` and `https` only; any other scheme is dropped. It waits in ``leaving`` for
    /// the reader to confirm its host (`ebook-reader`, *Following a link out of the publication*).
    static func outward(_ href: String?) -> URL? {
        guard let href, let url = URL(string: href), url.host() != nil,
              ["http", "https"].contains(url.scheme?.lowercased())
        else { return nil }
        return url
    }

    private func moved(to raw: [String: Any]) {
        noteJump(from: locator, to: raw)
        let locations = raw["locations"] as? [String: Any]
        position = locations?["position"] as? Int
        totalProgression = locations?["totalProgression"] as? Double ?? totalProgression
        guard let data = try? JSONSerialization.data(withJSONObject: raw),
              let json = String(data: data, encoding: .utf8)
        else { return }
        locator = json
        writer?.note(ReadingProgress(
            identity: publication.identity,
            position: .reflowable(progression: totalProgression, locator: json),
            isFinished: totalProgression >= 0.98,
            updatedAt: Date()
        ))
    }
}

extension EpubReaderModel: WKNavigationDelegate {
    /// Only the app's own scheme navigates the web view, and the `blob:` documents the
    /// renderer builds each chapter as. A book's link to the web was already decided in the
    /// content frame and posted as `link`; this is the second lock.
    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        Self.navigates(action.request.url) ? .allow : .cancel
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        failure = "The book's page stopped. Close the window and open the book again."
    }

    nonisolated static func navigates(_ url: URL?) -> Bool {
        [EpubEgress.scheme, "blob", "about"].contains(url?.scheme?.lowercased() ?? "")
    }
}

/// The message door, held by the content controller rather than the model, so the controller
/// does not keep the model alive after its window closes.
private final class EpubMessageDoor: NSObject, WKScriptMessageHandler {
    private weak var model: EpubReaderModel?

    init(model: EpubReaderModel) {
        self.model = model
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated { model?.receive(body) }
    }
}

/// The web view, loading its page once it has a size.
final class EpubWebViewHost: WKWebView {
    /// Called once, the first time the view is laid out with a size. The page loads then.
    var onFirstLayout: (() -> Void)?

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0, let onFirstLayout else { return }
        self.onFirstLayout = nil
        onFirstLayout()
    }
}

/// Opens a book's external link in the default browser, and nothing else.
/// `desktop-experience`, *A link to the web*. The walks replace it with a spy.
@MainActor
enum EpubLinkOpener {
    static var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
}
