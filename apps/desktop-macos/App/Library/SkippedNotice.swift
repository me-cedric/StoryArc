import Formats
import LibraryFeature
import SwiftUI

/// The words for a publication a folder scan could not open, in the app's language.
///
/// A Mac copy of `LibraryFeature`'s `SkipReason.sentence`, which is internal to the package;
/// the strings are the iOS catalogue's `library.skipped.*`, copied under `desktop.skipped.*`.
/// `library-browsing`, *What could not be opened*.
enum SkippedWords {
    /// The catalogue key for a reason, as the compiler writes it.
    static func key(for reason: SkipReason) -> String {
        switch reason {
        case .unsupportedFormat: "desktop.skipped.reason.unsupported %@"
        case .notThere: "desktop.skipped.reason.notThere"
        case .formatNotRecognised: "desktop.skipped.reason.formatNotRecognised"
        case .archivePasswordProtected: "desktop.skipped.reason.archivePasswordProtected"
        case .archiveUnreadable: "desktop.skipped.reason.archiveUnreadable"
        case .pdfUnopenable: "desktop.skipped.reason.pdfUnopenable"
        case .contentProtected: "desktop.skipped.reason.contentProtected"
        case .unknown: "desktop.skipped.reason.unknown"
        }
    }

    /// The sentence for a reason. The format's name is content and is shown as it is.
    static func text(for reason: SkipReason) -> Text {
        if case let .unsupportedFormat(format) = reason {
            return Text("desktop.skipped.reason.unsupported \(format)")
        }
        return Text(LocalizedStringKey(key(for: reason)))
    }
}

/// The notice above the shelf for what a scan could not open, and the list behind it.
///
/// One publication is named with its reason; several are counted, with *Show* leading to
/// the list; a notice the reader dismissed leaves a way back to the list, so a reader who
/// put it away in the middle of something can come back to it. The decision is
/// `SkippedPublications.notice`, StoryArcKit's.
struct SkippedNotice: View {
    @Environment(\.theme) private var theme

    let library: MacLibrary

    @State private var isShowingList = false

    var body: some View {
        let skipped = library.model.skipped
        Group {
            switch skipped.notice {
            case .nothing:
                EmptyView()
            case let .one(name, reason):
                banner(Text("desktop.skipped.one \(name)") + Text(verbatim: " · ") + SkippedWords.text(for: reason))
            case let .several(count):
                banner(Text("desktop.skipped \(count)"))
            case .reachable:
                HStack {
                    Spacer()
                    Button { isShowingList = true } label: { Text("desktop.skipped.list").hitTarget() }
                        .buttonStyle(.link)
                        .scaledFont(.callout)
                }
            }
        }
        .sheet(isPresented: $isShowingList) { SkippedList(entries: skipped.entries) }
    }

    private func banner(_ sentence: Text) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
            sentence.lineLimit(2)
            Spacer()
            // The notice's own action, then its close, as the iOS notice draws them: a link and
            // a borderless mark rather than two buttons side by side (AGENTS.md section 6).
            Button { isShowingList = true } label: { Text("desktop.skipped.show").hitTarget() }
                .buttonStyle(.link)
            Button { library.model.dismissSkipped() } label: { Image(systemName: "xmark").hitTarget() }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("desktop.skipped.dismiss"))
                .help(Text("desktop.skipped.dismiss"))
        }
        .scaledFont(.callout)
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(theme.palette.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Each publication a scan could not open, with its own reason.
private struct SkippedList: View {
    @Environment(\.dismiss) private var dismiss

    let entries: [SkippedPublications.Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("desktop.skipped.list").scaledFont(.headline)
            List(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).scaledFont(.body)
                    SkippedWords.text(for: entry.reason).scaledFont(.callout).foregroundStyle(.secondary)
                }
                // One stop per publication, naming it and saying why.
                .accessibilityElement(children: .combine)
            }
            .frame(minWidth: 420, minHeight: 240)
            HStack {
                Spacer()
                Button { dismiss() } label: { Text("desktop.skipped.done") }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
    }
}
