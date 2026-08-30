internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The rest of this series, as a shelf that behaves like every other shelf.
///
/// A shelf and not a second screen: `publication-detail`'s non-goals are explicit that
/// whether a series deserves a screen of its own is a different question with its own
/// increment. Each entry leads to its own page, which is the whole navigation this needs.
///
/// Absent entirely when the library holds nothing else from the series, rather than shown
/// with an empty state. A heading over nothing is a promise the shelf did not keep.
struct DetailSeriesShelf: View {
    @Environment(\.theme) private var theme

    let publications: [Publication]
    let model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            Text("detail.series.title", bundle: .module)
                .textRole(.title3)
                .foregroundStyle(theme.palette.textPrimary)
                // The heading keeps the page's gutter; the run below no longer inherits one,
                // because the shelf now sits outside the page's measured column so that it
                // can reach the window's edges (§3.11).
                .padding(.horizontal, StoryArcSpace.gutter)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: StoryArcSpace.coverGap) {
                    ForEach(publications) { publication in
                        DetailSeriesEntry(publication: publication, model: model)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            // On the *content*, so the first cover starts at the gutter and the run still
            // scrolls edge to edge underneath the chrome — the same pair of decisions
            // ``HomeShelfRow`` makes, so a shelf behaves the same wherever it appears.
            .contentMargins(.horizontal, StoryArcSpace.gutter, for: .scrollContent)
        }
    }

    /// The rest of `publication`'s series, in volume and chapter order.
    ///
    /// Sorted by volume, then by the issue number read the way a person reads it —
    /// `localizedStandardCompare` puts 2 before 10 and keeps "3.5" between 3 and 4, which a
    /// plain string comparison does neither of. A publication with no number sorts last
    /// rather than first: an annual with no issue number belongs after the run, not before
    /// issue one.
    /// `nonisolated` because it is arithmetic over value types and nothing else. A `View` is
    /// implicitly main-actor isolated, and a pure ordering rule that can only be asked on the
    /// main actor is a rule that can only be asserted there too.
    nonisolated static func rest(
        of publication: Publication,
        in library: [Publication]
    ) -> [Publication] {
        guard let series = publication.series, !series.isEmpty else { return [] }
        return library
            .filter { $0.series == series && $0.id != publication.id }
            .sorted { one, other in
                let left = one.volume ?? Int.max
                let right = other.volume ?? Int.max
                if left != right { return left < right }
                let leftNumber = one.number ?? "\u{10FFFF}"
                let rightNumber = other.number ?? "\u{10FFFF}"
                if leftNumber != rightNumber {
                    return leftNumber.localizedStandardCompare(rightNumber) == .orderedAscending
                }
                return one.displayTitle.localizedStandardCompare(other.displayTitle)
                    == .orderedAscending
            }
    }
}

/// One publication on the series shelf.
///
/// Marked with what has been read and what is on the device, and those marks are **words**
/// in the accessibility label as well as symbols on the artwork: a tick in the corner of a
/// cover is invisible to VoiceOver, and "have I read this one" is the entire question the
/// shelf is being scanned for.
private struct DetailSeriesEntry: View {
    @Environment(\.theme) private var theme

    let publication: Publication
    let model: LibraryModel

    @State private var cover: CGImage?

    private var isRead: Bool { model.finishedPublications.contains(publication.id) }
    private var isOnDevice: Bool { model.isOnDevice(publication) }

    var body: some View {
        // A link rather than a button with a callback: the enclosing stack already
        // registers `PublicationRoute` once, so the fourth issue of a run opens through the
        // same destination the shelf did — and back from it lands on the third.
        NavigationLink(value: PublicationRoute(publication)) {
            VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
                artwork
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .frame(width: 96)
                    .clipShape(.rect(cornerRadius: StoryArcRadius.cover))
                    .overlay {
                        RoundedRectangle(cornerRadius: StoryArcRadius.cover)
                            .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isRead {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, theme.palette.scrim.opacity(0.6))
                                .padding(StoryArcSpace.xs)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isOnDevice { OnDeviceMark() }
                    }

                Text(publication.number.map { "#\($0)" } ?? publication.displayTitle)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 96, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .task(id: publication.id) {
            guard cover == nil else { return }
            cover = await model.cover(for: publication, maxPixelSize: 240)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let cover {
            ZStack {
                theme.palette.surfaceSunken
                Image(decorative: cover, scale: 1).resizable().scaledToFit()
            }
        } else {
            theme.palette.surfaceRaised
        }
    }

    private var label: String {
        var parts = [publication.displayTitle]
        if isRead {
            parts.append(
                String(localized: "library.readState.finished", bundle: .module, locale: .storyArc)
            )
        }
        if isOnDevice {
            parts.append(
                String(localized: "catalogue.entry.downloaded", bundle: .module, locale: .storyArc)
            )
        }
        return parts.joined(separator: ", ")
    }
}
