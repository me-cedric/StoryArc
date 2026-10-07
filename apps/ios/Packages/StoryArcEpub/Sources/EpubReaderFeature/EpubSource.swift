public import Foundation

internal import Formats
internal import ReadiumShared

extension EpubReaderModel {
    /// The book's bytes, reached the way its address says, or `nil` when they cannot be.
    ///
    /// A book on a share or a server streams: Readium reads its ZIP through a
    /// ``SourceResource``, one range at a time, and never fetches the whole file
    /// (`publication-formats`, *Streaming capability per format*). A local book is a file.
    nonisolated static func asset(for url: URL, retriever: AssetRetriever) async -> Asset? {
        if ComicArchiveOpener.isRemote(url) {
            guard let source = try? await ComicArchiveOpener.source(for: url) else { return nil }
            let resource = SourceResource(source: source, name: url.lastPathComponent)
            return try? await retriever.retrieve(resource: resource, hints: FormatHints(mediaType: .epub)).get()
        }
        guard let fileURL = FileURL(url: url) else { return nil }
        return try? await retriever.retrieve(url: fileURL).get()
    }
}

/// A Readium resource that reads through a ranged source.
///
/// It has no URL, so Readium's ZIP opener reads it as a stream of ranges rather than as a
/// file. Each read is one ranged read of the source, clamped to its length.
struct SourceResource: Resource {
    let source: any RandomAccessSource
    let name: String

    var sourceURL: AbsoluteURL? { nil }

    func properties() async -> ReadResult<ResourceProperties> {
        .success(ResourceProperties { $0.filename = name })
    }

    func estimatedLength() async -> ReadResult<UInt64?> {
        .success(UInt64(source.length))
    }

    func stream(range: Range<UInt64>?, consume: @escaping (Data) -> Void) async -> ReadResult<Void> {
        let length = UInt64(max(source.length, 0))
        let lower = min(range?.lowerBound ?? 0, length)
        let upper = min(max(range?.upperBound ?? length, lower), length)
        var offset = lower
        do {
            // A transport may answer with less than it was asked for, as SMB does past its
            // own reply cap, so the read goes on until the range is whole.
            while offset < upper {
                let chunk = try await source.read(offset: Int64(offset), count: Int(upper - offset))
                guard !chunk.isEmpty else { break }
                consume(chunk)
                offset += UInt64(chunk.count)
            }
            return .success(())
        } catch {
            return .failure(.access(.other(error)))
        }
    }
}
