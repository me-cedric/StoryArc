public import Foundation

/// What an import is about to do, before it does any of it.
///
/// `library-portability` / *The reader sees what will happen first*: "the app states what it
/// will add, what it will merge, and what it will ask for a sign-in, before anything
/// changes". Counts and names rather than sentences, because the sentences are four
/// languages' business and this has to be the same value on both platforms.
///
/// Android's `LibraryImportPlan` carries the same fields.
public struct LibraryImportPlan: Sendable, Equatable {

    /// Sources the device does not have, by the name the document gives them.
    public var sourcesToAdd: [String]

    /// Sources that will arrive without their secret, by name.
    ///
    /// A subset of ``sourcesToAdd`` plus any already-known source whose secret this device
    /// lacks. `library-portability`: the source "is listed, marked as needing a sign-in, and
    /// reaching it asks for the secret once".
    public var sourcesNeedingSignIn: [String]

    /// Collections and reading lists the device does not have, by name.
    public var shelvesToAdd: [String]

    /// Shelves that exist on both sides, with how many members the import adds to each.
    ///
    /// `library-portability`: "their members are merged rather than one replacing the other,
    /// and the reader is told how many were added".
    public var shelvesToMerge: [ImportedShelf]

    /// Publications whose position the device does not hold yet.
    public var progressToAdd: Int

    /// Publications where both sides hold a position, so ``ProgressMerge`` decides.
    public var progressToMerge: Int

    /// Hosts that will gain a pinned certificate, and the source each pin arrives with.
    ///
    /// `library-portability`: "importing it does not silently change what the app trusts: the
    /// reader is told which source gained a pin and from where".
    public var certificatePinsToAdd: [CertificatePinNotice]

    /// Whether the document's settings differ from the device's.
    public var settingsWillChange: Bool

    /// Reading themes and per-publication reader settings the device does not hold.
    public var themeEntriesToAdd: Int

    /// Chosen covers the device does not hold, and that arrive as readable images.
    public var coversToAdd: Int

    public init(
        sourcesToAdd: [String] = [],
        sourcesNeedingSignIn: [String] = [],
        shelvesToAdd: [String] = [],
        shelvesToMerge: [ImportedShelf] = [],
        progressToAdd: Int = 0,
        progressToMerge: Int = 0,
        certificatePinsToAdd: [CertificatePinNotice] = [],
        settingsWillChange: Bool = false,
        themeEntriesToAdd: Int = 0,
        coversToAdd: Int = 0
    ) {
        self.sourcesToAdd = sourcesToAdd
        self.sourcesNeedingSignIn = sourcesNeedingSignIn
        self.shelvesToAdd = shelvesToAdd
        self.shelvesToMerge = shelvesToMerge
        self.progressToAdd = progressToAdd
        self.progressToMerge = progressToMerge
        self.certificatePinsToAdd = certificatePinsToAdd
        self.settingsWillChange = settingsWillChange
        self.themeEntriesToAdd = themeEntriesToAdd
        self.coversToAdd = coversToAdd
    }
}

/// One shelf that exists on both sides.
public struct ImportedShelf: Sendable, Equatable {
    public let name: String
    public let membersAdded: Int

    public init(name: String, membersAdded: Int) {
        self.name = name
        self.membersAdded = membersAdded
    }
}

/// One host about to gain a pinned certificate, and the source it arrived with.
public struct CertificatePinNotice: Sendable, Equatable {
    public let host: String

    /// The source in the document that points at this host, or `nil` when none does — a pin
    /// can outlive the source that accepted it, and a pin with no source is still a change to
    /// what the app trusts and still has to be named.
    public let sourceName: String?

    public init(host: String, sourceName: String?) {
        self.host = host
        self.sourceName = sourceName
    }
}
