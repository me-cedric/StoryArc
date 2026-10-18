import Formats
import Foundation

/// The resources of one open publication, as the scheme handler asks for them: the host
/// page, the pinned bundle, the manifest, the positions, and the archive's own entries.
///
/// The bundle is `apps/desktop-web/epub/dist/storyarc-epub.js`, copied into the app by
/// `project.yml`; its digest is pinned by `pnpm epub:pin`. Task 4.5.
struct EpubArchiveSource: EpubResourceSource {
    static let hostPath = "index.html"
    static let bundlePath = "storyarc-epub.js"
    static let manifestPath = "manifest.json"
    static let positionsPath = "positions.json"

    let reader: EpubReader
    let publication: EpubWebPublication
    let manifest: Data
    let positions: Data
    let bundle: URL
    /// The faces' stylesheet, by its full URL on this book's scheme.
    let fontSheet: String

    /// Opens the EPUB at `url` and builds what the renderer is owed, served under `token`.
    init(url: URL, token: String, bundle: URL) async throws {
        let source = try FileSource(url: url)
        reader = try await EpubReader(source: source)
        let zip = try await ZipReader(source: source)
        let publication = EpubWebPublication.build(
            reader: reader, compressedSizes: zip.compressedSizes,
            selfHref: EpubSchemeHandler.base(for: token) + Self.manifestPath
        )
        self.publication = publication
        manifest = try publication.manifestData()
        positions = try publication.positionsData()
        self.bundle = bundle
        fontSheet = EpubSchemeHandler.base(for: token) + EpubFonts.sheet
    }

    /// Where the app keeps the bundle.
    static var bundledRenderer: URL? {
        Bundle.main.url(forResource: "storyarc-epub", withExtension: "js")
    }

    func resource(at path: String) async -> EpubResource? {
        switch path {
        case Self.hostPath, "":
            return EpubResource(data: Data(EpubHostPage.html.utf8), mimeType: "text/html")
        case Self.bundlePath:
            guard let data = try? Data(contentsOf: bundle) else { return nil }
            return EpubResource(data: data, mimeType: "text/javascript")
        case Self.manifestPath:
            return EpubResource(data: manifest, mimeType: "application/webpub+json")
        case Self.positionsPath:
            return EpubResource(data: positions, mimeType: "application/json")
        default:
            if let font = EpubFonts.resource(at: path) { return font }
            guard let data = try? await reader.data(at: path) else { return nil }
            let type = EpubMediaTypes.type(of: path)
            return EpubResource(data: EpubFonts.linking(data, mimeType: type, sheet: fontSheet), mimeType: type)
        }
    }
}

/// The page the web view opens: the bundle, one container, and the call that opens the
/// book. The locator to open at and the first preferences are set by a user script before
/// the page runs (`EpubReaderModel`).
enum EpubHostPage {
    static let html = """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>StoryArc</title>
        <style>
        html,body{margin:0;height:100%;overflow:hidden;background:transparent}
        #reader{width:100%;height:100%}
        </style>
        </head><body><div id="reader"></div>
        <script src="storyarc-epub.js"></script>
        <script>
        (async function () {
          const door = window.webkit.messageHandlers.storyarc;
          const report = (where, message) => door.postMessage({ type: "host-error", message: where + ": " + message });
          window.addEventListener("error", (e) => report("error", e.message + " " + e.filename + ":" + e.lineno));
          window.addEventListener("unhandledrejection", (e) =>
            report("rejection", String(e.reason && e.reason.stack || e.reason)));
          if (window.__storyarcDebug) {
            const log = (level) => (...parts) =>
              door.postMessage({ type: "host-log", message: level + ": " + parts.map(String).join(" ") });
            for (const level of ["log", "info", "warn", "error", "debug"]) console[level] = log(level);
            const text = Response.prototype.text;
            Response.prototype.text = async function () {
              const t = await text.call(this); log("text")(this.url, t.length); return t;
            };
            const create = URL.createObjectURL.bind(URL);
            URL.createObjectURL = (blob) => {
              const u = create(blob); log("blob")(u, blob.size, blob.type); return u;
            };
            const fetched = window.fetch.bind(window);
            window.fetch = async (input, init) => {
              const url = typeof input === "string" ? input : input.url;
              try {
                const response = await fetched(input, init);
                log("fetch")(init && init.method || "GET", url, response.status);
                return response;
              } catch (error) {
                log("fetch")(url, "failed", String(error));
                throw error;
              }
            };
          }
          try {
            const [manifest, positions] = await Promise.all([
              fetch("manifest.json").then((r) => r.json()),
              fetch("positions.json").then((r) => r.json()),
            ]);
            window.__storyarcReader = await StoryArcEpub.open({
              container: document.getElementById("reader"),
              manifest,
              positions,
              locator: window.__storyarcLocator || undefined,
              preferences: window.__storyarcPreferences || {},
            });
          } catch (error) {
            door.postMessage({ type: "host-error", message: String(error && error.message || error) });
          }
        })();
        </script></body></html>
        """
}
