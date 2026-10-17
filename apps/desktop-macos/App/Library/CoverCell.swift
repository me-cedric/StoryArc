import AppKit
import DesignSystem
import Formats
import LibraryFeature
import StoryArcCore
import SwiftUI

/// One cover in the grid: the cover ladder, the title, the series, and the progress rail.
///
/// `cover-art`'s ladder, drawn: a placeholder well until the cover is decoded, then the
/// cover. The decode is a `task` on the cell, off the main actor inside the model, so a
/// scroll never waits for one. VoiceOver reads the cell as `docs/designs/desktop/macos.md`
/// section 10 asks: title, series, issue, percent read.
struct CoverCell: View {
    @Environment(\.theme) private var theme

    let library: MacLibrary
    let publication: Publication
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                CoverImage(library: library, publication: publication, maxPixelSize: 400)
                    .aspectRatio(CoverArtwork.aspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                if let fraction = library.model.readFraction(of: publication) {
                    ProgressRail(fraction: fraction)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? theme.accent : .clear, lineWidth: 3)
                    .padding(-3)
            )
            Text(publication.displayTitle)
                .scaledFont(.callout, weight: .medium)
                .lineLimit(2)
                .foregroundStyle(theme.palette.textPrimary)
            if let line = Self.secondLine(of: publication) {
                Text(line).scaledFont(.caption).foregroundStyle(theme.palette.textSecondary).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.label(for: publication, fraction: library.model.readFraction(of: publication))))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The series and the issue, under the title. Absent when it would only repeat the
    /// title: a series guessed from a file name is often the file name itself.
    static func secondLine(of publication: Publication) -> String? {
        guard let series = publication.series else { return nil }
        if let number = publication.number { return "\(series) · \(number)" }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let repeatsTitle = series.compare(publication.displayTitle, options: options) == .orderedSame
        return repeatsTitle ? nil : series
    }

    /// "Saga, Saga, issue 4, 62 percent read".
    static func label(for publication: Publication, fraction: Double?) -> String {
        var parts = [publication.displayTitle]
        if let series = publication.series { parts.append(series) }
        if let number = publication.number { parts.append(String(localized: "desktop.cover.issue \(number)")) }
        if let fraction { parts.append(String(localized: "desktop.cover.percentRead \(Int(fraction * 100))")) }
        return parts.joined(separator: ", ")
    }
}

/// The cover, through the model's cache and ladder, or the well while it is not there.
struct CoverImage: View {
    let library: MacLibrary
    let publication: Publication
    let maxPixelSize: Int

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                CoverlessWell(format: publication.format)
            }
        }
        .task(id: publication.id) {
            image = library.model.cachedCover(for: publication)
            guard image == nil else { return }
            image = await library.model.cover(for: publication, maxPixelSize: maxPixelSize)
        }
    }
}

/// The progress rail along the foot of a cover.
struct ProgressRail: View {
    @Environment(\.theme) private var theme

    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(theme.palette.scrim)
                Rectangle().fill(theme.accent).frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// The context menu of a cover or a row: `docs/designs/desktop/macos.md` section 7.
struct PublicationMenu: View {
    let library: MacLibrary
    let publication: Publication
    let onOpen: (Publication) -> Void
    let onShow: (Publication) -> Void
    /// How many publications the menu acts on; *Start from the Beginning* needs exactly one.
    var selectionCount = 1
    /// The covers selected with this one, which the shelf and bulk actions act on together.
    var selected: Set<String> = []

    /// What the shelf and bulk actions act on: the selection when this cover is in it.
    private var targets: [String] {
        selected.count > 1 && selected.contains(publication.id)
            ? library.model.publications.map(\.id).filter(selected.contains) : [publication.id]
    }

    var body: some View {
        Button { onOpen(publication) } label: { Text("desktop.menu.read") }
            .disabled(library.model.location(of: publication) == nil)
        Button { onShow(publication) } label: { Text("desktop.menu.showDetails") }
        Divider()
        AddToShelfMenu(library: library, ids: targets)
        if targets.count > 1 {
            // Bulk actions, `collections-and-reading-lists`: the single path, for the selection.
            Button { Task { await library.markOffering(Set(targets), read: true) } } label: {
                Text("desktop.bulk.markRead")
            }
            Button { Task { await library.markOffering(Set(targets), read: false) } } label: {
                Text("desktop.bulk.markUnread")
            }
            if !library.downloadable(among: Set(targets)).isEmpty {
                Button { library.offerDownload(Set(targets)) } label: { Text("desktop.menu.download") }
            }
        } else if RemoteEntry.isDownloadable(publication, in: library.model.registry) {
            Button { Task { await library.download(publication) } } label: { Text("desktop.menu.download") }
        }
        if let url = library.model.location(of: publication), url.isFileURL {
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                Text("desktop.menu.showInFinder")
            }
        }
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(publication.displayTitle, forType: .string)
        } label: { Text("desktop.menu.copyTitle") }
        if RestartRequest.isOffered(
            hasProgress: library.record(of: publication) != nil, selectionCount: selectionCount,
            hasStore: library.progress != nil
        ) {
            Divider()
            Button { library.requestRestart(publication) } label: { Text("desktop.menu.restart") }
        }
    }
}
