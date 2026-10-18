import StoryArcLicences
import SwiftUI

/// About, the last tab of the preferences: who made this, that it costs nothing, what it
/// is built on, and where to report a problem. `MacAbout` holds the facts.
struct AboutSettingsTab: View {
    @State private var shown: Notice?
    /// Whether the generated notices file is shown whole.
    @State private var showsNotices = false
    private let allNotices = MacAbout.thirdPartyNotices()
    private let notices = Result { try MacAbout.notices() }

    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: "\(MacAbout.version) (\(MacAbout.build))").textSelection(.enabled)
            } label: {
                Text("desktop.about.version")
            }
            // The byline is the way to the author, so no other row opens that address.
            if let author = MacAbout.author {
                Link(destination: author) { Text("desktop.about.author").hitTarget() }
            }
            Text("desktop.about.free").foregroundStyle(.secondary)
        }
        Section {
            link("desktop.about.repository", MacAbout.repository)
            link("desktop.about.licence", MacAbout.licence)
            // The one support link, on the one screen. Never a prompt.
            link("desktop.about.support", MacAbout.support)
            link("desktop.about.report", MacAbout.issue())
        } footer: {
            Text("desktop.about.report.footer").foregroundStyle(.secondary)
        }
        Section {
            switch notices {
            case let .success(listed):
                ForEach(listed) { notice in
                    Button { shown = notice } label: {
                        LabeledContent {
                            Text(verbatim: notice.licence).foregroundStyle(.secondary)
                        } label: {
                            Text(verbatim: notice.version.map { "\(notice.name) \($0)" } ?? notice.name)
                        }
                        .hitTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("desktop.about.acknowledgements.hint"))
                }
            case .failure:
                // A packaging bug, said rather than drawn as an empty list.
                Text("desktop.about.acknowledgements.unreadable").foregroundStyle(.secondary)
            }
            if allNotices != nil {
                Button { showsNotices = true } label: { Text("desktop.about.notices").hitTarget() }
                    .accessibilityHint(Text("desktop.about.acknowledgements.hint"))
            } else {
                Text("desktop.about.acknowledgements.unreadable").foregroundStyle(.secondary)
            }
        } header: {
            Text("desktop.about.acknowledgements")
        }
        .sheet(item: $shown) { notice in LicenceSheet(title: notice.name, text: MacAbout.licenceText(for: notice)) }
        .sheet(isPresented: $showsNotices) {
            LicenceSheet(title: String(localized: "desktop.about.notices"), text: allNotices)
        }
    }

    @ViewBuilder
    private func link(_ title: LocalizedStringKey, _ url: URL?) -> some View {
        if let url { Link(destination: url) { Text(title).hitTarget() } }
    }
}

/// One licence, or the whole notices file, in full: a summary of a licence is not a licence.
private struct LicenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: title).scaledFont(.title3, weight: .semibold)
            ScrollView {
                Text(text ?? String(localized: "desktop.about.licenceMissing"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: { Text("desktop.about.done") }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
    }
}
