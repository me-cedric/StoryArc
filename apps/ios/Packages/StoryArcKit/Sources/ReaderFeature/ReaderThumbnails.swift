public import CoreGraphics
internal import Foundation
internal import Formats
internal import StoryArcCore

/// The thumbnail strip's supply of small page images, and the budget that bounds it.
///
/// Split out of ``ReaderModel`` because the file passed the 400-line cap, and this is the
/// seam that was already there: everything here is about *small* versions of pages, which
/// have their own size, their own cache and their own eviction rule. Full-size decoding
/// stays with the reader.
extension ReaderModel {
    /// A small version of a page, decoded on demand.
    ///
    /// `comic-reader`: the thumbnail browser shows "every page ... in a scrollable
    /// strip". Every page, so the strip is lazy and this is called per cell as it
    /// scrolls into view rather than for the whole publication at once — a
    /// 300-page comic would otherwise read 300 archive entries to open a strip.
    public func thumbnail(at index: Int) async -> CGImage? {
        if let ready = thumbnails[index] { return ready }
        guard let archive, pages.indices.contains(index) else { return nil }

        let page = pages[index]
        // Read off the actor before the detached task, so the constant crosses as a
        // value rather than the task reaching back into main-actor state.
        let size = Self.thumbnailPixelSize
        let image = await Task.detached(priority: .utility) {
            guard let data = try? await archive.data(for: page) else { return CGImage?.none }
            return try? PageDecoder.decode(data, maxPixelSize: size)
        }.value

        guard let image else { return nil }
        evictDistantThumbnails(from: index)
        thumbnails[index] = image
        return image
    }

    /// Enough to recognise a page by its composition, not to read it.
    ///
    /// `page-browser-carousel` §1: "decode thumbnails at the [carousel's] centred
    /// size, and draw the neighbours from the same image, scaled down" — so this is
    /// sized for the carousel's centred cell (about 1.6 times ``ThumbnailStrip``'s
    /// base width) rather than for a neighbour, and every smaller cell downsamples
    /// the one decode instead of asking for one of its own.
    nonisolated private static let thumbnailPixelSize = 256

    /// How many thumbnails to keep. A 300-page comic's worth would be tens of
    /// megabytes of pixels for a strip showing eight of them at a time.
    nonisolated private static let thumbnailBudget = 64

    /// Where this publication's chapters start, and what to call each one.
    ///
    /// `page-browser-carousel`: the carousel and the slider's ticks both read this. A
    /// comic archive already has it; a PDF's outline is read once, off the actor, the
    /// same way ``ChapterActionsSection`` reads its page-only version.
    func chapterMarkers() async -> [ChapterMarker] {
        if let archive {
            return ChapterBrowser.markers(
                comicStarts: archive.chapterStartIndices,
                titles: archive.chapterTitles
            )
        }
        guard let pdf else { return [] }
        return ChapterBrowser.markers(pdfOutline: await pdf.outline())
    }

    private func evictDistantThumbnails(from index: Int) {
        guard thumbnails.count >= Self.thumbnailBudget else { return }
        // The furthest from where the reader is looking, because the strip scrolls
        // outward from the current page in both directions.
        let ordered = thumbnails.keys.sorted { abs($0 - index) > abs($1 - index) }
        for key in ordered.prefix(thumbnails.count - Self.thumbnailBudget + 1) {
            thumbnails.removeValue(forKey: key)
        }
    }
}

extension ReaderModel {
    /// Derives the cover's colours, once, when the publication opens.
    ///
    /// `native-experience`: "accent and background tinting derive from the
    /// publication's cover art". From the *cover* rather than from the page in front of
    /// the reader, because a book resumed at page 57 is still that book — and from the
    /// cover's thumbnail rather than the full page, because a colour census wants a
    /// thousand pixels and decoding a 2000×3000 scan to find them would be paying for a
    /// picture nobody looks at.
    ///
    /// Quiet about a PDF, which has no archive to take a thumbnail from, and about a
    /// cover that is all ink and paper. Both leave this `nil`, and a screen with no
    /// cover colour uses the brand accent — which is what `native-experience` asks for
    /// on a surface with no publication colour of its own.
    func deriveCoverColours() async {
        guard coverColours == nil else { return }
        // The designated cover when `ComicInfo` named one, page one otherwise. The same
        // rule `open()` uses to decide which page to show first.
        let index = publication.coverPath.flatMap { path in
            pages.firstIndex { $0.path == path }
        } ?? 0
        guard let image = await thumbnail(at: index),
              let pixels = CoverAccent.pixels(of: image) else { return }
        coverColours = CoverAccent.derived(from: pixels)
    }
}
