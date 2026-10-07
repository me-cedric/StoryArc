public import Foundation

/// The reader's library, in one versioned JSON document they can open.
///
/// `library-portability` / *One versioned document*: an export "declares a format version,
/// the app version and the platform that wrote it, and the moment it was written", and the
/// body is "readable JSON, so a reader can open it and a later version can diff it".
///
/// **This type is the wire, not a store.** design.md settles that the two platforms keep
/// their own stores and reconcile here instead, because changing a store to agree is a
/// migration on every existing install to fix a divergence only the export can see. So the
/// five records the two platforms spell differently — the source timestamp, the source
/// kind, the shelf cover key, the reading position and the pinned-shelf container — take
/// the shape below, and each platform converts at its own boundary.
///
/// The document spells an enum case the way Swift already does, in lower camel. Android's
/// `LibraryDocument` carries the same fields and converts its own SCREAMING_SNAKE names.
/// `LibraryDocumentTests` pins the JSON text so a rename on this side cannot silently
/// change the wire.
public struct LibraryDocument: Sendable, Equatable, Codable {

    /// The newest format this build writes, and the newest it can read.
    ///
    /// One is the first. design.md: the transform chain exists from the start with nothing
    /// in it, so the second version has somewhere to go.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var appVersion: String
    public var writtenBy: String
    public var writtenAt: Date
    public var library: LibraryBody

    /// Reserved, and never filled by this writer.
    ///
    /// The owner asked for credentials to travel encrypted under a passphrase. Two standing
    /// rules forbid it and both name backups by name: the `sources` capability's *Credential
    /// storage* requirement, and `AGENTS.md` non-negotiable 4. An encrypted secret in a file
    /// is still a secret in a file, so turning this on is an amendment the owner makes
    /// knowingly rather than a thing an unrelated change slips in.
    ///
    /// The field exists so that saying yes later is one change and no rework: fill it, and
    /// amend the two rules. design.md fixes the crypto — PBKDF2-HMAC-SHA256, AES-256-GCM,
    /// every parameter in the document — so the decision is a yes or a no.
    public var secrets: LibrarySecrets?

    public init(
        formatVersion: Int = LibraryDocument.currentFormatVersion,
        appVersion: String,
        writtenBy: String,
        writtenAt: Date,
        library: LibraryBody,
        secrets: LibrarySecrets? = nil
    ) {
        self.formatVersion = formatVersion
        self.appVersion = appVersion
        self.writtenBy = writtenBy
        self.writtenAt = writtenAt
        self.library = library
        self.secrets = secrets
    }
}

/// The two names this build writes and knows, for the field ``LibraryDocument/writtenBy``.
///
/// Recorded because a reader asking why a record did not arrive is asking about a pair of
/// builds, and the document is the only place that can answer. The field is text, not a
/// closed set: a document from a third platform names it, and the name decides nothing. An
/// importer that read a record one way for iOS and another for Android would be two formats
/// wearing one version number.
public enum WritingPlatform {
    public static let ios = "ios"
    public static let android = "android"
}

/// The passphrase-encrypted credential block, which this writer never produces.
///
/// Its parameters are all in the document on purpose: a hard-coded iteration count cannot be
/// raised later without breaking every file already written. See ``LibraryDocument/secrets``.
public struct LibrarySecrets: Sendable, Equatable, Codable {
    public var kdf: String
    public var iterations: Int
    public var salt: String
    public var cipher: String
    public var nonce: String
    public var ciphertext: String

    public init(
        kdf: String,
        iterations: Int,
        salt: String,
        cipher: String,
        nonce: String,
        ciphertext: String
    ) {
        self.kdf = kdf
        self.iterations = iterations
        self.salt = salt
        self.cipher = cipher
        self.nonce = nonce
        self.ciphertext = ciphertext
    }
}

/// Everything the export carries.
///
/// `library-portability` / *The library's shape* names the list: "the sources and servers,
/// the collections and reading lists, the pinned shelves, the settings, the reading themes,
/// the per-publication reader settings, the reading progress, and the covers the reader
/// chose". The last of those is a member identifier rather than an image — a shelf's chosen
/// cover names one of its own members — so it travels inside the shelf that chose it.
public struct LibraryBody: Sendable, Equatable, Codable {
    public var sources: [DocumentSource]

    /// Accepted certificate fingerprints, per host.
    ///
    /// Carried because a reader who accepted a self-signed certificate on one device should
    /// not have to read the same fingerprint off the same server again. `library-portability`
    /// requires the import to say "which source gained a pin and from where" rather than
    /// changing what the app trusts without a word.
    public var certificatePins: [String: [String]]

    public var collections: [DocumentCollection]
    public var readingLists: [DocumentReadingList]

    /// Pinned shelves as a list of ``ShelfPin`` tokens.
    ///
    /// The token spelling is already shared; the container is not. iOS keeps one
    /// space-separated scalar because `@AppStorage` stores scalars, and Android keeps a
    /// string set because its preferences take one natively. A list is the shape both can
    /// write without either having to change how it stores them.
    public var pinnedShelves: [String]

    public var settings: DocumentSettings
    public var readingThemes: DocumentThemes
    public var progress: [DocumentProgress]

    /// The covers the reader chose, each filed under the key the cover store uses.
    ///
    /// Images in base64, because a chosen cover has no other source: a publication's own cover
    /// is read from the publication, and the cover cache is recreated.
    public var covers: [DocumentCover]

    public init(
        sources: [DocumentSource] = [],
        certificatePins: [String: [String]] = [:],
        collections: [DocumentCollection] = [],
        readingLists: [DocumentReadingList] = [],
        pinnedShelves: [String] = [],
        settings: DocumentSettings = DocumentSettings(),
        readingThemes: DocumentThemes = DocumentThemes(),
        progress: [DocumentProgress] = [],
        covers: [DocumentCover] = []
    ) {
        self.sources = sources
        self.certificatePins = certificatePins
        self.collections = collections
        self.readingLists = readingLists
        self.pinnedShelves = pinnedShelves
        self.settings = settings
        self.readingThemes = readingThemes
        self.progress = progress
        self.covers = covers
    }

    /// Decodes what is there and defaults what is not.
    ///
    /// `library-portability` / *A field this version does not know*: an unknown field is
    /// ignored and the rest is imported. The mirror of that rule is a *missing* field, which
    /// is what a document written by an older build of the same version looks like, and
    /// Swift's synthesised decoder fails on one even where the property has a default. The
    /// same forgiveness `ShelfSettings` already gives its own stored shape.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sources: try container.decodeIfPresent([DocumentSource].self, forKey: .sources) ?? [],
            certificatePins: try container.decodeIfPresent(
                [String: [String]].self, forKey: .certificatePins
            ) ?? [:],
            collections: try container.decodeIfPresent(
                [DocumentCollection].self, forKey: .collections
            ) ?? [],
            readingLists: try container.decodeIfPresent(
                [DocumentReadingList].self, forKey: .readingLists
            ) ?? [],
            pinnedShelves: try container.decodeIfPresent(
                [String].self, forKey: .pinnedShelves
            ) ?? [],
            settings: try container.decodeIfPresent(DocumentSettings.self, forKey: .settings)
                ?? DocumentSettings(),
            readingThemes: try container.decodeIfPresent(
                DocumentThemes.self, forKey: .readingThemes
            ) ?? DocumentThemes(),
            progress: try container.decodeIfPresent([DocumentProgress].self, forKey: .progress)
                ?? [],
            covers: try container.decodeIfPresent([DocumentCover].self, forKey: .covers) ?? []
        )
    }
}

/// A source, without its secret.
///
/// `library-portability` / *A server in the export*: "its address, its name, its username and
/// its settings travel, and its secret does not". ``Source/credentialReference`` is a handle
/// into this device's secure store and means nothing on another device, so it does not travel
/// either — ``needsSignIn`` carries the one fact the other device needs from it.
public struct DocumentSource: Sendable, Equatable, Codable {
    public var id: UUID
    public var displayName: String

    /// The kind in lower camel, which is iOS's own spelling and Android's after conversion.
    public var kind: String

    /// When this source last answered, as ISO 8601. iOS keeps a `Date` and Android epoch
    /// millis; neither spelling is readable in a file, and one of them is not even a date.
    public var lastSuccessfulSync: Date?

    public var locator: String?

    /// Whether the source held a secret on the device that wrote the document.
    ///
    /// The secret itself never travels, so this is how the importing device knows to list the
    /// source as needing a sign-in rather than as simply unreachable.
    public var needsSignIn: Bool

    public init(
        id: UUID,
        displayName: String,
        kind: String,
        lastSuccessfulSync: Date? = nil,
        locator: String? = nil,
        needsSignIn: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.lastSuccessfulSync = lastSuccessfulSync
        self.locator = locator
        self.needsSignIn = needsSignIn
    }
}

/// A collection, with the cover its reader chose.
///
/// `coverMemberId`, with a lower-case `d`. iOS stores `coverMemberID` and Android
/// `coverMemberId`; one of the two has to give, and the document takes Android's because
/// JSON keys elsewhere in this file are lower camel throughout.
public struct DocumentCollection: Sendable, Equatable, Codable {
    public var id: UUID
    public var name: String
    public var members: [String]
    public var coverMemberId: String?

    public init(id: UUID, name: String, members: [String], coverMemberId: String? = nil) {
        self.id = id
        self.name = name
        self.members = members
        self.coverMemberId = coverMemberId
    }
}

/// A reading list, with the cover its reader chose. Ordered, which is its whole difference
/// from a collection.
public struct DocumentReadingList: Sendable, Equatable, Codable {
    public var id: UUID
    public var name: String
    public var entries: [String]
    public var coverMemberId: String?

    public init(id: UUID, name: String, entries: [String], coverMemberId: String? = nil) {
        self.id = id
        self.name = name
        self.entries = entries
        self.coverMemberId = coverMemberId
    }
}

/// The reading themes and the per-publication reader settings, which are one store.
///
/// A list of entries rather than the two keyed maps ``ShelfMemory`` holds, because those keys
/// are built from a scope's raw value and the two platforms spell a scope differently — so a
/// map carried verbatim would lose every per-series choice the moment it crossed. An entry
/// with no ``shelf`` is a scope's default.
public struct DocumentThemes: Sendable, Equatable, Codable {
    public var entries: [DocumentThemeEntry]
    public var customPalette: ReaderPalette?

    public init(entries: [DocumentThemeEntry] = [], customPalette: ReaderPalette? = nil) {
        self.entries = entries
        self.customPalette = customPalette
    }
}

/// One remembered reading setup: a scope's default, or one shelf's own choice.
public struct DocumentThemeEntry: Sendable, Equatable, Codable {
    public var scope: String
    public var shelf: String?
    public var settings: DocumentShelfSettings

    public init(scope: String, shelf: String?, settings: DocumentShelfSettings) {
        self.scope = scope
        self.shelf = shelf
        self.settings = settings
    }
}

/// One reading position, with the watermark deliberately left behind.
///
/// ``ReadingProgress/syncedPosition`` records what *this* device last exchanged with a
/// server. It is a fact about one device's conversation, not about the reader's library, and
/// carrying it would tell the importing device it had synchronised when it never had. An
/// imported record therefore arrives with no watermark, which is exactly the case
/// ``ProgressMerge`` was fixed to read correctly — task 1.4 is a prerequisite for this type.
public struct DocumentProgress: Sendable, Equatable, Codable {
    public var identity: DocumentIdentity
    public var position: DocumentPosition
    public var isFinished: Bool
    public var finishedAt: Date?
    public var updatedAt: Date

    public init(
        identity: DocumentIdentity,
        position: DocumentPosition,
        isFinished: Bool,
        finishedAt: Date?,
        updatedAt: Date
    ) {
        self.identity = identity
        self.position = position
        self.isFinished = isFinished
        self.finishedAt = finishedAt
        self.updatedAt = updatedAt
    }
}
