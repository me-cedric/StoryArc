import DesignSystem
import StoryArcCore
import SwiftUI

/// The rest of a publication's series, for its page.
///
/// `publication-detail`, *Other issues in this series*: offered as a shelf, in volume and
/// chapter order, marked with what has been read and what is on the device, each entry
/// leading to its own page. The order is a Mac copy of `DetailSeriesShelf.rest(of:in:)`,
/// which is internal to `LibraryFeature`; making it public is a parent edit under
/// `apps/ios` (task 5.12's family), and until then the two are held to the same table.
enum OtherIssues {
    /// One entry on the shelf, with the two marks the spec names.
    struct Entry: Identifiable, Equatable {
        let publication: Publication
        let isRead: Bool
        /// Whether the file is here to open now. A folder source has no download, so "on the
        /// device" is the file being reachable.
        let isOnThisMac: Bool

        var id: String { publication.id }

        /// What sits under the cover: the issue number, or the title when there is none.
        var label: String { publication.number.map { "#\($0)" } ?? publication.displayTitle }

        /// The whole entry for VoiceOver, so neither mark is told by colour or a glyph alone.
        var spoken: String {
            var parts = [publication.displayTitle]
            if let number = publication.number { parts.append(String(localized: "desktop.cover.issue \(number)")) }
            if isRead { parts.append(String(localized: "desktop.detail.series.read")) }
            if !isOnThisMac { parts.append(String(localized: "desktop.detail.series.notHere")) }
            return parts.joined(separator: ", ")
        }
    }

    /// The rest of `publication`'s series: by volume, then by issue number read the way a
    /// person reads it, a publication with no number last, never the publication itself.
    static func rest(of publication: Publication, in library: [Publication]) -> [Publication] {
        let series = publication.series?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let series, !series.isEmpty else { return [] }
        return library
            .filter { $0.series?.trimmingCharacters(in: .whitespacesAndNewlines) == series && $0.id != publication.id }
            .sorted(by: precedes)
    }

    private static func precedes(_ one: Publication, _ other: Publication) -> Bool {
        let left = one.volume ?? Int.max
        let right = other.volume ?? Int.max
        if left != right { return left < right }
        let leftNumber = one.number ?? "\u{10FFFF}"
        let rightNumber = other.number ?? "\u{10FFFF}"
        if leftNumber != rightNumber {
            return leftNumber.localizedStandardCompare(rightNumber) == .orderedAscending
        }
        return one.displayTitle.localizedStandardCompare(other.displayTitle) == .orderedAscending
    }
}

/// The shelf on a publication's page. Absent when the series holds nothing else.
struct OtherIssuesShelf: View {
    @Environment(\.theme) private var theme

    let library: MacLibrary
    let publication: Publication
    let onShow: (Publication) -> Void

    var body: some View {
        let entries = entries
        if !entries.isEmpty, let series = publication.series {
            VStack(alignment: .leading, spacing: 12) {
                Text("desktop.detail.series.title \(series)").scaledFont(.title3, weight: .semibold)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(entries) { entry in cell(entry) }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var entries: [OtherIssues.Entry] {
        OtherIssues.rest(of: publication, in: library.model.publications).map { issue in
            OtherIssues.Entry(
                publication: issue,
                isRead: library.record(of: issue)?.isFinished == true,
                isOnThisMac: library.model.location(of: issue).map(MacLibrary.isReachable) ?? false
            )
        }
    }

    private func cell(_ entry: OtherIssues.Entry) -> some View {
        Button { onShow(entry.publication) } label: {
            VStack(alignment: .leading, spacing: 6) {
                CoverImage(library: library, publication: entry.publication, maxPixelSize: 240)
                    .frame(width: 96, height: 144)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if entry.isRead {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, theme.accent)
                                .padding(4)
                        }
                    }
                    .opacity(entry.isOnThisMac ? 1 : 0.55)
                Text(entry.label).scaledFont(.callout, weight: .medium).lineLimit(1)
                if !entry.isOnThisMac {
                    Text("desktop.detail.series.notHere")
                        .scaledFont(.caption).foregroundStyle(theme.palette.textSecondary)
                } else if entry.isRead {
                    Text("desktop.detail.series.read").scaledFont(.caption).foregroundStyle(theme.palette.textSecondary)
                }
            }
            .frame(width: 96, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(entry.spoken))
        .accessibilityAddTraits(.isButton)
    }
}
