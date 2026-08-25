internal import SwiftUI

internal import DesignSystem
internal import StoryArcLicences

/// About: who made this, that it costs nothing, and what it is built on.
///
/// `settings-and-about` is unusually specific here, and two of its clauses are about
/// restraint rather than content. The support link "is never presented as a prompt, an
/// interstitial, or a nag — it appears only on this screen". And the problem report
/// carries "the app version, platform version, and device class pre-filled, and no
/// personal data" — which is why it composes a URL from three known values rather than
/// collecting anything.
struct AboutSettings: View {
    @Environment(\.theme) private var theme

    private let notices = StoryArcLicences.forApple()

    var body: some View {
        List {
            Section {
                Text("about.version \(BuildInfo.version) \(BuildInfo.build)", bundle: .module)
                Text("about.author", bundle: .module)
                // Stated plainly, because the spec asks for it plainly: free, open
                // source, no paid tier, no advertising.
                Text("about.free", bundle: .module)
                    .foregroundStyle(theme.palette.textSecondary)
            }

            Section {
                Link(destination: BuildInfo.repository) {
                    Text("about.repository", bundle: .module)
                }
                Link(destination: BuildInfo.author) {
                    Text("about.authorLink", bundle: .module)
                }
                Link(destination: BuildInfo.licence) {
                    Text("about.licence", bundle: .module)
                }
                // The one support link, on the one screen. Never a prompt.
                Link(destination: BuildInfo.support) {
                    Text("about.support", bundle: .module)
                }
                Link(destination: BuildInfo.issue) {
                    Text("about.report", bundle: .module)
                }
            }

            Section {
                ForEach(notices) { notice in
                    NavigationLink {
                        LicenceText(notice: notice)
                    } label: {
                        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                            Text(notice.version.map { "\(notice.name) \($0)" } ?? notice.name)
                            Text(verbatim: "\(notice.licence) · \(notice.why)")
                                .textRole(.footnote)
                                .foregroundStyle(theme.palette.textTertiary)
                        }
                    }
                }
            } header: {
                Text("about.acknowledgements", bundle: .module)
            } footer: {
                Text("about.acknowledgements.note", bundle: .module)
            }
        }
    }
}

/// One licence, in full, because a summary of a licence is not a licence.
private struct LicenceText: View {
    @Environment(\.theme) private var theme

    let notice: Notice

    var body: some View {
        ScrollView {
            Text(
                StoryArcLicences.text(for: notice.licence)
                    ?? String(describing: MissingLicence(identifier: notice.licence))
            )
            // Monospaced, because a licence is a document and its own line breaks are
            // part of it.
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(theme.palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(StoryArcSpace.gutter)
        }
        .navigationTitle(notice.name)
    }
}

/// What to say when a licence text is missing from the build.
///
/// It is a packaging bug rather than a display problem, and saying so is more useful than
/// an empty screen — the file is meant to be there.
private struct MissingLicence: CustomStringConvertible {
    let identifier: String

    var description: String {
        "The \(identifier) text is missing from this build. That is a packaging bug — please report it."
    }
}
