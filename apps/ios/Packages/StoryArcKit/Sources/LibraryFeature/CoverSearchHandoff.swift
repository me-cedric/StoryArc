internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

#if os(iOS)
internal import SafariServices
#endif

/// Hands the reader to the system browser to find a cover, and learns nothing from it.
///
/// **`SFSafariViewController`, never a `WKWebView`.** `design.md` records the reason at
/// length and it is two reasons:
///
/// - App Store Review Guideline 5.2.3 bans saving media from a third-party source without
///   that source's authorization. A web view this app owns, capturing an image by screenshot
///   or by reading an element's `src`, is StoryArc performing that save. The system browser
///   performing it is the reader using their browser.
/// - StoryArc's only web view today, the EPUB reader, denies all network egress through
///   `PublicationEgress`. A second web view that exists to load a search engine would be the
///   opposite rule on the same app, and two rules about one primitive is how a security
///   property quietly stops being true.
///
/// `SFSafariViewController` hides its page from the host app by design, so the app cannot
/// read it even if a later edit tried to. That is the feature here, not the limit. The only
/// route a picture takes back into StoryArc is the system picker.
struct CoverSearchHandoff: View {
    /// The publication the reader is looking for a cover for.
    let title: String

    /// The author, when the file states one, which narrows a common title.
    var author: String?

    /// Opens the address in the system browser. Supplied by the platform below, and
    /// injectable so a test can watch the address without opening anything.
    var open: (URL) -> Void

    @Environment(\.theme) private var theme

    /// Where the reader is sent. Nil when there is no title to search for, which is when
    /// the row below refuses rather than opening an engine's front page.
    var destination: URL? {
        CoverWebSearch.url(title: title, author: author)
    }

    var body: some View {
        VStack(alignment: .center, spacing: StoryArcSpace.hair) {
            Button {
                guard let destination else { return }
                open(destination)
            } label: {
                Text("covers.web.search", bundle: .module)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .textRole(.subheadline)
            .buttonStyle(.borderless)
            .disabled(destination == nil)

            Text("covers.web.note", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

#if os(iOS)
/// Presents the system browser, with no delegate and no way back into the app.
///
/// Deliberately has no `SFSafariViewControllerDelegate`. The delegate's hooks report what
/// the reader did — the address they finished on, whether they completed a load — and this
/// feature has no use for any of it. An absent delegate is a channel that cannot be opened
/// by accident.
struct SystemBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
