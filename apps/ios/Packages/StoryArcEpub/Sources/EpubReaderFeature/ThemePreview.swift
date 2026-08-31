internal import SwiftUI
internal import WebKit

internal import DesignSystem
internal import StoryArcCore
internal import StoryArcFonts

/// The live preview: a chapter title and body text, drawn by the engine that draws the
/// book.
///
/// ## What "the real renderer" means here, and what it does not
///
/// `reading-themes` asks for a preview "rendered by the same engine that renders the
/// publication, so the preview cannot disagree with the result". Readium renders a
/// reflowable EPUB in a `WKWebView`; this is a `WKWebView`, given the same axis values
/// through ``ThemePreviewDocument``, which is asserted against the Readium mapping axis by
/// axis. Type, spacing, measure, alignment and colour behave here exactly as they behave
/// on the page, because the same layout engine is deciding.
///
/// **It is not a second Readium navigator over the publication's own resources**, and the
/// spec's own preview content is why it cannot be: the same requirement asks for "a
/// chapter title and at least three lines of body text", which is a *constructed*
/// specimen. A navigator renders the resource at a locator and nothing else, so it can
/// show a page but never that. What is given up by the difference is worth naming:
///
/// - **The publisher's stylesheet is absent.** Under any preset but Original that is what
///   the reader asked for anyway — `publisherStyles` is off and StoryArc's values win. It
///   is a real gap only under Original, where the preview shows the browser's defaults
///   rather than the publisher's design.
/// - **ReadiumCSS itself is absent.** Its own resets and its `--USER__*` plumbing are not
///   reproduced; the same *numbers* are emitted as plain CSS instead. Where ReadiumCSS
///   does something StoryArc's values do not describe, the page has it and the preview
///   does not.
///
/// Task 3.6 in the change's task list records this in the same words.
struct ThemePreview: View {
    @Environment(\.theme) private var theme

    let readingTheme: ReadingTheme
    let values: ThemeValues
    /// The chapter the reader is in, or `nil` before the book reports one.
    let title: String?
    /// Words from the open publication, or empty for the sample paragraph.
    let excerpt: String

    /// Tall enough to judge a spacing change, and fixed so it stays that way.
    ///
    /// `reading-themes` asks the preview to stay "large enough to judge a spacing change"
    /// at large text sizes — which on a sheet that grows with Dynamic Type means the
    /// preview must *not* grow with it, because every point the preview takes is a point
    /// the controls below it lose. Six lines at the default step, fewer at 200 %, which is
    /// still enough to see two lines' leading.
    private static let height: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.preview", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            PreviewWeb(html: html)
                .frame(height: Self.height)
                .clipShape(.rect(cornerRadius: StoryArcRadius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: StoryArcRadius.lg)
                        .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
                }
                // A picture of the page, not the page. VoiceOver reading two paragraphs of
                // sample text between the preset grid and the size stepper would be a
                // detour through content the reader is not here to read; the label says
                // what the thing is instead.
                .accessibilityElement()
                .accessibilityLabel(Text("theme.preview.description", bundle: .module))
        }
    }

    private var html: String {
        ThemePreviewDocument.html(
            theme: readingTheme,
            values: values,
            title: title,
            body: excerpt.isEmpty ? String(localized: "theme.preview.sample", bundle: .module) : excerpt
        )
    }
}

/// The web view itself.
///
/// Reloaded on every change rather than mutated, which is what makes the preview "reflow
/// continuously during a drag": the sliders are stepped to a tenth of their range, so a
/// drag submits at most ten documents rather than one per frame, and each is a few hundred
/// bytes of HTML with no network and no publication behind it.
private struct PreviewWeb: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(FontServer(), forURLScheme: ThemePreviewDocument.fontScheme)

        let web = WKWebView(frame: .zero, configuration: configuration)
        // The page paints its own background from the theme, and a white flash between
        // documents during a drag is the one artefact a live preview cannot have.
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        // A specimen, not a place to read. A drag that started on the preview belongs to
        // the sheet underneath it.
        web.isUserInteractionEnabled = false
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.rendered != html else { return }
        context.coordinator.rendered = html
        web.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Rendered { Rendered() }

    /// What is already on screen, so an unrelated redraw does not reload the document and
    /// flash the page.
    final class Rendered {
        var rendered: String?
    }
}

/// Serves the bundled typefaces to the preview.
///
/// `WKWebView` will not load a `file:` subresource from a document loaded as a string, and
/// the two ways round that are both worse than this: copying the type into a cache
/// directory duplicates two megabytes on disk, and inlining a face as base64 rebuilds a
/// megabyte of data URI on every slider step. A scheme handler reads the file the app
/// already ships, once per document.
///
/// It serves nothing but the bundled fonts. A request for anything `StoryArcFonts` does
/// not know about fails, which is the whole of its threat model — the document is built by
/// ``ThemePreviewDocument`` and asks for one file.
private final class FontServer: NSObject, WKURLSchemeHandler {
    func webView(_ web: WKWebView, start task: any WKURLSchemeTask) {
        guard let name = task.request.url?.host ?? task.request.url?.lastPathComponent,
              let stem = name.split(separator: ".").first.map(String.init),
              let url = StoryArcFonts.url(stem),
              let data = try? Data(contentsOf: url)
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(
            url: task.request.url ?? url,
            mimeType: "font/ttf",
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ web: WKWebView, stop task: any WKURLSchemeTask) {}
}
