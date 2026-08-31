public import CoreGraphics
public import Foundation

public import StoryArcCore

/// Produces a publication's cover image, on demand.
///
/// Separate from indexing on purpose. `publication-formats` requires that a scan
/// of 10,000 publications show its first screen within three seconds, and that
/// "covers are extracted lazily as rows approach the viewport, not all at once
/// during the scan". So `PublicationIndexer` records *where* the cover is and this
/// reads it only when a row is about to be seen.
///
/// Every load is bounded by the size it will be drawn at. A grid thumbnail is a
/// couple of hundred points across; decoding a 2000×3000 page to fill one costs
/// 24 MB of pixels for something shown at a fortieth of that.
public enum CoverLoader {
    public enum CoverError: Error, Equatable {
        /// The publication has no cover to load — no pages, or a format that does
        /// not carry one.
        case noCover
        /// The cover is named and could not be read.
        case unreadable
    }

    /// The cover of a publication, decoded and bounded on its longest edge.
    ///
    /// `maxPixelSize` is the size it will be *drawn* at, in pixels. Passing the
    /// display's need rather than nothing is the whole point of the type.
    public static func cover(
        for publication: Publication,
        at url: URL,
        maxPixelSize: Int
    ) async throws -> CGImage {
        let data = try await coverData(for: publication, at: url)
        do {
            return try PageDecoder.decode(data, maxPixelSize: maxPixelSize)
        } catch {
            throw CoverError.unreadable
        }
    }

    /// The cover's raw bytes, undecoded.
    ///
    /// For a caller that wants to cache the bytes rather than the pixels — a
    /// thumbnail store, say, which wants one copy at one size rather than whatever
    /// the last viewport asked for.
    public static func coverData(
        for publication: Publication, at url: URL
    ) async throws -> Data {
        switch publication.format {
        case .pdf:
            // A PDF page is rendered rather than extracted, so there is nothing to
            // read out. `renderedCover` produces one instead.
            throw CoverError.noCover

        case .epub:
            return try await bookCover(for: publication, at: url)

        case .audiobook, .audioFolder:
            // An M4B can carry embedded artwork and this does not read it yet, so the
            // library draws its no-art placeholder. Named rather than folded into the comic
            // case: a folder of audio has no first page to fall back to, and reaching for
            // one would open a file the reader is about to hear rather than see.
            throw CoverError.noCover

        case .cbz, .cbr, .cbt, .cb7, .imageFolder:
            guard let path = publication.coverPath else { throw CoverError.noCover }
            guard let archive = try? await ComicArchiveOpener.open(fileAt: url) else {
                throw CoverError.unreadable
            }
            guard let page = archive.pages.first(where: { $0.path == path })
                    ?? archive.coverPage
            else { throw CoverError.noCover }
            guard let data = try? await archive.data(for: page) else {
                throw CoverError.unreadable
            }
            return data
        }
    }

    /// An EPUB's cover bytes.
    ///
    /// Its own function because the EPUB path has two ways to find a cover where every
    /// other format has one: the path the indexer recorded, and — for a publication that
    /// declares none — the image its first spine item shows. Resolved here as well as in
    /// the indexer so a library catalogued before ``EpubSpineCover`` existed heals on the
    /// next cover it draws, rather than on the next full rescan.
    private static func bookCover(for publication: Publication, at url: URL) async throws -> Data {
        guard let reader = try? await EpubReader(source: try FileSource(url: url)) else {
            throw CoverError.unreadable
        }
        var resolved = publication.coverPath
        if resolved == nil { resolved = await reader.coverOrSpineHref() }
        guard let path = resolved else { throw CoverError.noCover }
        guard let data = try? await reader.data(at: path) else { throw CoverError.unreadable }
        return data
    }

    /// A cover for a format whose pages are drawn rather than stored.
    ///
    /// PDF only. Kept separate from `cover(for:at:maxPixelSize:)` because the two
    /// have genuinely different costs — one reads bytes, the other rasterises a
    /// page — and a caller batching thumbnails will want to know which it is doing.
    public static func renderedCover(at url: URL, maxPixelSize: Int) throws -> CGImage {
        let reader: PdfDocumentReader
        do {
            reader = try PdfDocumentReader(url: url)
        } catch {
            throw CoverError.unreadable
        }
        guard reader.pageCount > 0 else { throw CoverError.noCover }
        do {
            return try reader.render(pageAt: 0, maxPixelSize: maxPixelSize)
        } catch {
            throw CoverError.unreadable
        }
    }

    /// The cover of any publication, whichever way it has to be produced.
    ///
    /// The one call a grid cell should make. It hides the difference between a
    /// stored cover and a rendered one, which is not a distinction a list of rows
    /// should have to care about.
    public static func anyCover(
        for publication: Publication, at url: URL, maxPixelSize: Int
    ) async throws -> CGImage {
        if publication.format == .pdf {
            return try renderedCover(at: url, maxPixelSize: maxPixelSize)
        }
        return try await cover(for: publication, at: url, maxPixelSize: maxPixelSize)
    }
}
