public import Foundation

public import StoryArcCore

/// Turns a file into a `Publication`.
///
/// The seam between the format layer and the library. Everything below it knows
/// about containers; everything above it knows about books. `local-library`
/// requires a folder scan to "identify supported publications, extract covers and
/// metadata", and this is the per-file half of that.
///
/// Metadata has a precedence, and it is the whole point of the type. Embedded
/// metadata beats a guess from the filename, and both record where they came from
/// so an authoritative source can replace them later without raising a conflict
/// the app invented (`publication-formats`).
public enum PublicationIndexer {
    /// What went wrong, in terms the library can show without inventing a reason.
    public enum IndexError: Error, Equatable {
        /// A container StoryArc recognises and does not read. Carries the name so
        /// the message can say "7-Zip" rather than "could not open file".
        case unsupported(format: String)
        /// Recognised, supported, and this particular file cannot be read.
        case unreadable(reason: String)
        /// Audio behind a store's content protection — an Audible `.aax` or `.aaxc`.
        ///
        /// **Its own case, and `publication-formats` requires it to be**: "the refusal is
        /// distinct from an unsupported container, because the format itself is supported
        /// and this particular file is locked". MPEG-4 audio *is* read; this file is not
        /// readable by anyone without the store's key.
        ///
        /// It carries nothing. There is no key to ask for, no account to name and no
        /// activation code to prompt for, and a payload here would be an invitation to
        /// build one. StoryArc does not implement, circumvent or advise on removing a
        /// content protection, so this refusal will not change.
        case contentProtected
    }

    /// Indexes one local publication.
    ///
    /// Opens the container, so it costs one read of the index and one of the cover
    /// — not of the whole file. A CBR is catalogued from its headers with nothing
    /// decompressed at all.
    /// - Parameter seriesHint: the name of the folder the file sits in, when that
    ///   folder is a subfolder of a picked library rather than the library itself.
    ///   `local-library` presents such a subfolder "as a series whose name is the
    ///   folder name", and this is the metadata half of that: a hint used only
    ///   where nothing better exists. Embedded metadata and the filename both beat
    ///   it, because both are statements about *this* publication and a folder name
    ///   is a statement about its neighbours.
    /// - Parameter catalogueSeries: the series a server that keeps the catalogue reported.
    ///   It beats the filename, which for a downloaded or cached publication is often an
    ///   identifier rather than a name.
    public static func index(
        fileAt url: URL,
        seriesHint: String? = nil,
        catalogueSeries: String? = nil
    ) async throws -> Publication {
        let filename = url.lastPathComponent
        let fallback = FilenameMetadata(
            filename: filename,
            seriesHint: seriesHint,
            catalogued: catalogueSeries
        )

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else { throw IndexError.unreadable(reason: "the file is not there") }

        if isDirectory.boolValue { return try await folderPublication(at: url) }

        let source = try FileSource(url: url)
        // Taken from the handle the sniff below is about to use, so both reads land on
        // pages this index is touching anyway. See `contentDigest(of:)`.
        let found = identity(forPath: url.path, digest: try? await contentDigest(of: source))
        let probe = try await source.read(offset: 0, count: FormatSniffer.probeLength)
        let container = FormatSniffer.container(of: probe)

        // Hoisted out of the switch so `container` is non-optional inside it. A
        // `where audio.isAudio` case reads better and does not count toward
        // exhaustiveness, which would cost the compiler's naming of every call site
        // a new container must be decided for.
        guard let container else {
            throw IndexError.unreadable(reason: "the format was not recognised")
        }

        switch container {
        case .pdf:
            return try pdf(at: url, identity: found, filename: filename, fallback: fallback)
        case .zip:
            return try await zipPublication(
                at: url, source: source, identity: found, filename: filename, fallback: fallback
            )
        case .tar:
            return try await comicArchive(
                url: url, identity: found, format: .cbt, filename: filename, fallback: fallback
            )
        case .rar:
            return try await comicArchive(
                url: url, identity: found, format: .cbr, filename: filename, fallback: fallback
            )
        case .sevenZip:
            throw IndexError.unsupported(format: PublicationFormat.cb7.displayName)
        case .mp4, .mp3, .flac, .ogg:
            return await audiobook(
                at: url, identity: found, format: .audiobook, fallback: fallback
            )
        case .protectedAudiobook:
            // Refused for being locked, not for being the wrong kind of file. The brand at
            // offset 8 said so before a decoder was ever asked — and `protected.aax` in the
            // corpus still holds a decodable stream on purpose, so a decoder that merely
            // choked would not have satisfied this.
            throw IndexError.contentProtected
        }
    }

    /// Indexes a publication that is not a local file.
    ///
    /// Everything the file-based path does, over a `RandomAccessSource` instead — which is
    /// what ADR-0008 put that interface there for. A share supplies one, so a comic on a NAS
    /// is catalogued from its headers rather than fetched.
    ///
    /// - Parameter decoderPath: a local copy, for the two decoders that cannot take a
    ///   source. PDFKit wants a file and libarchive wants a path; without one, those
    ///   formats are catalogued as records with their pages marked refused rather than
    ///   failing outright — the same honest degradation the file path already gives a
    ///   solid archive.
    public static func index(
        source: any RandomAccessSource,
        name: String,
        identity: PublicationIdentity,
        decoderPath: URL? = nil,
        seriesHint: String? = nil
    ) async throws -> Publication {
        let fallback = FilenameMetadata(filename: name, seriesHint: seriesHint)
        // The caller's identity says *where* this came from; the digest says *what* it
        // is. Recorded together, which is what ADR-0006 asks for whenever both are
        // known — and here both are, because the source is already open. A caller that
        // supplied a digest of its own keeps it.
        let found = identity.recordingDigest(try? await contentDigest(of: source))
        let probe = try await source.read(offset: 0, count: FormatSniffer.probeLength)

        let container = FormatSniffer.container(of: probe)

        guard let container else { // see the guard above
            throw IndexError.unreadable(reason: "the format was not recognised")
        }

        return try await remote(
            container,
            source: source,
            decoderPath: decoderPath,
            naming: Naming(name: name, identity: found, fallback: fallback)
        )
    }

    /// The three facts every builder needs about a publication before its container is open.
    ///
    /// They have always travelled together — what it is called, what it *is*, and what its
    /// filename implies — and passing them as one is what keeps the switch below inside the
    /// parameter count the linter allows.
    struct Naming: Sendable {
        let name: String
        let identity: PublicationIdentity
        let fallback: FilenameMetadata
    }

    /// Which reader a sniffed remote container gets.
    ///
    /// Split from its caller only because the switch and the preamble together crossed the
    /// complexity limit once audio stopped being one refusal and became two outcomes. The
    /// cut is where the file path already cuts: above it is identity and sniffing, below it
    /// is what the container turns into.
    private static func remote(
        _ container: FormatSniffer.Container,
        source: any RandomAccessSource,
        decoderPath: URL?,
        naming: Naming
    ) async throws -> Publication {
        let name = naming.name
        let found = naming.identity
        let fallback = naming.fallback

        switch container {
        case .pdf:
            guard let decoderPath else { return record(.pdf, found, name, fallback) }
            return try pdf(at: decoderPath, identity: found, filename: name, fallback: fallback)

        case .zip:
            return try await zipPublication(
                source: source, identity: found, name: name,
                decoderPath: decoderPath, fallback: fallback
            )

        case .tar:
            return comic(
                try await TarComicArchive(source: source),
                format: .cbt,
                identity: found,
                filename: name,
                fallback: fallback
            )

        case .rar:
            guard let decoderPath else { return record(.cbr, found, name, fallback) }
            return try await comicArchive(
                url: decoderPath, identity: found, format: .cbr, filename: name,
                fallback: fallback
            )

        case .sevenZip:
            throw IndexError.unsupported(format: PublicationFormat.cb7.displayName)

        case .mp4, .mp3, .flac, .ogg:
            // `AVURLAsset` wants a file, so without a local copy this is a record: the
            // library lists it, says what it is and offers the download, rather than
            // dropping it — the same honest degradation a PDF and a RAR already get here.
            guard let decoderPath else { return record(.audiobook, found, name, fallback) }
            return await audiobook(
                at: decoderPath, identity: found, format: .audiobook, fallback: fallback
            )

        case .protectedAudiobook:
            // See the file path's own case: the brand at offset 8 decides this, not a
            // decoder, and the refusal is distinct from an unsupported container.
            throw IndexError.contentProtected

        }
    }

}
