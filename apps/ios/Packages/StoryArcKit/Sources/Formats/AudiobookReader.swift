public import Foundation

internal import AVFoundation

/// One part of an audiobook: a chapter marker inside a file, or a whole file of a folder.
///
/// `design.md`'s table calls both a *part*, and `publication-formats` requires them to
/// behave the same way — "its parts — the files, or the whole of a single file — stand in
/// for chapters". So one type, carrying where the audio is and where inside it the part
/// begins.
public struct AudiobookPart: Sendable, Equatable {
    /// The file this part is in. The same URL for every chapter of an M4B; a different one
    /// for every part of a folder.
    public let url: URL

    /// What the container calls it, or `nil` when it names nothing.
    ///
    /// **Never the file name.** `design.md` records that as a product decision:
    /// `01 - track.mp3` is not what a listener is in the middle of. A part with no name is
    /// numbered by the player, which is the one place that decision lives.
    public let title: String?

    /// Where this part starts inside ``url``. Zero for a whole file.
    public let start: TimeInterval

    /// How long it runs, when the container says.
    public let duration: TimeInterval?

    public init(url: URL, title: String?, start: TimeInterval, duration: TimeInterval?) {
        self.url = url
        self.title = title
        self.start = start
        self.duration = duration
    }
}

/// An audiobook as the format layer sees it: parts in playing order, and what was lost.
public struct Audiobook: Sendable, Equatable {
    public let parts: [AudiobookPart]

    /// How many entries looked like parts and could not be read.
    ///
    /// `publication-formats`: a damaged audiobook "plays what it can and states how much it
    /// could not … the count is stated in the player's own controls rather than
    /// interrupting playback" — the same rule that opens a comic missing pages.
    public let unreadablePartCount: Int

    /// The whole book's length, or `nil` when any part's is unknown.
    public var duration: TimeInterval? {
        let durations = parts.compactMap(\.duration)
        guard durations.count == parts.count, !parts.isEmpty else { return nil }
        return durations.reduce(0, +)
    }
}

/// Reads an audiobook's parts, from one file or from a folder of them.
///
/// **The chapter call needs the asset's own locale, and that is not obvious.**
/// `design.md` names `AVAsset.loadChapterMetadataGroups(bestMatchingPreferredLanguages:)`,
/// which is the right method — but the obvious argument, the reader's preferred languages,
/// returns **nothing** for either chaptered fixture. Both `chaptered.m4b` and
/// `id3-chapters.mp3` declare their chapter titles under the `und` locale, so
/// `["en"]` matches none of them and the book looks unchaptered. Measured on 2026-09-01
/// against both fixtures: `availableChapterLocales` answers `["und"]`, `["en"]` yields 0
/// groups, and the asset's own identifiers yield 3.
///
/// So the asset is asked what languages it has before it is asked for its chapters. Nothing
/// in the API's shape suggests it and nothing in a build would have caught it — a book with
/// three chapters would simply have opened as one long part.
public enum AudiobookReader {

    /// The parts of a single audio file: its chapter markers, or the whole of it.
    public static func read(fileAt url: URL) async -> Audiobook {
        let asset = AVURLAsset(url: url)
        let chapters = await chapters(of: asset, in: url)
        if !chapters.isEmpty { return Audiobook(parts: chapters, unreadablePartCount: 0) }

        // No markers. `publication-formats` requires the whole of the file to stand in for
        // a chapter — "nothing is reported as missing, because an unchaptered audiobook is
        // a normal audiobook" — so this is one unnamed part, never an empty list.
        let whole = AudiobookPart(url: url, title: nil, start: 0, duration: await seconds(of: asset))
        return Audiobook(parts: [whole], unreadablePartCount: 0)
    }

    /// The parts of a folder of audio files, in playing order.
    ///
    /// The ordering rule is the one that makes a folder of images one comic, so `part10`
    /// follows `part2`. An entry that will not load is counted rather than skipped silently.
    public static func read(folderAt url: URL) async -> Audiobook {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let names = entries
            .filter { PageOrdering.isCandidateEntry(path: $0) }
            .filter { FolderKind.audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted(by: PageOrdering.naturalCompare)

        var parts: [AudiobookPart] = []
        var unreadable = 0
        for name in names {
            let file = url.appending(path: name)
            guard let seconds = await seconds(of: AVURLAsset(url: file)) else {
                unreadable += 1
                continue
            }
            parts.append(AudiobookPart(url: file, title: nil, start: 0, duration: seconds))
        }
        return Audiobook(parts: parts, unreadablePartCount: unreadable)
    }

    /// Reads the chapter markers, in the locale the file actually used. See the type's note.
    private static func chapters(of asset: AVURLAsset, in url: URL) async -> [AudiobookPart] {
        guard let locales = try? await asset.load(.availableChapterLocales), !locales.isEmpty else {
            return []
        }
        guard let groups = try? await asset.loadChapterMetadataGroups(
            bestMatchingPreferredLanguages: locales.map(\.identifier)
        ) else { return [] }

        var parts: [AudiobookPart] = []
        for group in groups {
            var title: String?
            if let item = group.items.first(where: { $0.commonKey == .commonKeyTitle }) {
                title = try? await item.load(.stringValue)
            }
            parts.append(
                AudiobookPart(
                    url: url,
                    title: title,
                    start: group.timeRange.start.seconds,
                    duration: group.timeRange.duration.seconds
                )
            )
        }
        return parts
    }

    /// How long an asset runs, or `nil` when it cannot be read at all.
    ///
    /// A zero-length or non-finite duration counts as unreadable: a file the decoder
    /// accepted and can play none of is a part that was lost, not a part of no length.
    private static func seconds(of asset: AVURLAsset) async -> TimeInterval? {
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }
}
