internal import SwiftUI

internal import Catalogue
internal import DesignSystem
internal import StoryArcCore

/// Every way this catalogue offers a publication, as a choice rather than a menu.
///
/// `opds-catalog` names two things this has to do at once. It "selects EPUB for reflowable
/// reading and lets the user choose another format", so the default is one press and the
/// alternatives are visible without hunting; and where nothing is readable the entry is
/// "listed but marked unreadable, naming the formats offered", so the refusal names what was
/// on offer rather than leaving a dead screen.
struct CatalogueFormatChoice: View {
    @Environment(\.theme) private var theme

    let entry: OpdsEntry
    let isDownloaded: Bool

    /// Take this one, whatever the app would have picked.
    let onTake: (OpdsAcquisition) -> Void

    /// Take the one the app picks. The press for a reader who does not care about formats.
    let onRead: () -> Void

    let onRemove: () -> Void

    var body: some View {
        let offered = CatalogueAcquisition.readable(in: entry)

        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            if !offered.isEmpty {
                Button(action: onRead) {
                    Text("catalogue.detail.read", bundle: .module)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, StoryArcSpace.xs)
                }
                .buttonStyle(.borderedProminent)

                if isDownloaded {
                    Button(role: .destructive, action: onRemove) {
                        Text("downloads.remove", bundle: .module)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                formats(offered)
            }

            refusals
        }
    }

    /// One row per format, the default first and said to be the default.
    @ViewBuilder
    private func formats(_ offered: [OpdsAcquisition]) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("catalogue.detail.formats", bundle: .module)
                .textRole(.caption)
                .foregroundStyle(theme.palette.textSecondary)

            ForEach(Array(offered.enumerated()), id: \.element.href) { position, link in
                Button {
                    onTake(link)
                } label: {
                    row(link, isDefault: position == 0)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ link: OpdsAcquisition, isDefault: Bool) -> some View {
        HStack(spacing: StoryArcSpace.md) {
            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(name(of: link))
                    .textRole(.headline)
                    .foregroundStyle(theme.palette.textPrimary)

                if isDefault {
                    Text("catalogue.detail.default", bundle: .module)
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: isDefault ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(isDefault ? theme.accent : theme.palette.textTertiary)
        }
        .padding(StoryArcSpace.md)
        // 44pt is the floor Apple's own audit checks, and a row of one short word is the
        // control most likely to fall under it.
        .frame(minHeight: StoryArcSpace.xxl + StoryArcSpace.md, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.surfaceRaised, in: .rect(cornerRadius: StoryArcRadius.md))
    }

    /// What this catalogue offers that the app will not take, said plainly.
    @ViewBuilder
    private var refusals: some View {
        let unreadable = CatalogueAcquisition.unreadable(in: entry)
        let unsupported = CatalogueAcquisition.unsupported(in: entry)

        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            if !unreadable.isEmpty {
                Text(
                    "catalogue.entry.unreadable \(ListFormatter.localizedString(byJoining: unreadable))",
                    bundle: .module
                )
                .textRole(.footnote)
                .foregroundStyle(StoryArcColor.Status.offline)
            }

            // `opds-catalog`: a borrow or an OPDS-LCP flow makes the app "state that the
            // acquisition type is not supported rather than failing silently". One line per
            // kind, because a catalogue that offers both a loan and a purchase has refused
            // the reader twice for two different reasons.
            ForEach(unsupported, id: \.self) { kind in
                Text("catalogue.detail.unsupported \(Self.name(of: kind))", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            }

            if unreadable.isEmpty, unsupported.isEmpty,
               CatalogueAcquisition.readable(in: entry).isEmpty {
                Text("catalogue.entry.noDownload", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(StoryArcColor.Status.offline)
            }
        }
    }

    /// How a format is named to a person, falling back to the media type the feed declared
    /// when it names nothing this app knows.
    private func name(of link: OpdsAcquisition) -> String {
        PublicationFormat(mediaType: link.mediaType)?.displayName ?? link.mediaType
    }

    /// How an acquisition the app refuses is named in the sentence that refuses it.
    private static func name(of kind: OpdsAcquisition.Kind) -> String {
        switch kind {
        case .borrow: String(localized: "catalogue.acquire.kind.borrow", bundle: .module, locale: .storyArc)
        case .buy: String(localized: "catalogue.acquire.kind.buy", bundle: .module, locale: .storyArc)
        case .subscribe:
            String(localized: "catalogue.acquire.kind.subscribe", bundle: .module, locale: .storyArc)
        case .open, .direct, .sample, .indirect:
            String(localized: "catalogue.acquire.kind.indirect", bundle: .module, locale: .storyArc)
        }
    }
}
