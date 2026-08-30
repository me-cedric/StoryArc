internal import Foundation

internal import StoryArcCore

/// Where one publication lives, and whether it can be opened right now.
///
/// The seam, as a value. `library-browsing` presents a folder, a share, a catalogue and a
/// server as one library and takes origin off the shelf entirely; that only works because
/// origin is *here*, on one line, on the one screen a reader is on when they ask "where is
/// this from?".
///
/// A projection rather than a stored field, and a pure one: `publication-detail` requires
/// the line to be "computed with no network call", because a line that needs a round trip
/// to draw is a line that is blank on a train. Everything it reads — the download store's
/// answer, the file's presence, the registry's own copy of the source — is already on the
/// device by the time the page is composed.
///
/// What it may never say is as much of the requirement as what it says. No protocol, no
/// transport, no server product, no path, no URL, no identifier: a library is named by the
/// name the reader gave it, and nothing else about it reaches this line. That is why
/// ``Home/library(name:)`` carries a display name and not a ``Source``.
struct PublicationProvenance: Equatable, Sendable {
    /// Where the copy this page will open actually is.
    enum Home: Equatable, Sendable {
        /// The app holds the bytes, or the file sits in the app's own storage.
        case thisDevice
        /// A library the reader added, by the name they gave it.
        case library(name: String)
        /// Found where the system handed it over, belonging to no library the reader set up.
        case unattributed
    }

    /// Whether the reader can act on it now, which is the other half of the one line.
    enum Availability: Equatable, Sendable {
        /// On the device, so no network is involved at all.
        case offline
        /// Reachable and openable as things stand.
        case now
        /// Its library is answering; the bytes are not here yet.
        case notHere
        /// Its library is not answering, so nothing can be fetched from it.
        case notAnswering
    }

    let home: Home
    let availability: Availability

    /// A library that also holds this publication, when naming one adds something.
    ///
    /// `publication-detail`: when the library holds the same publication in more than one
    /// place, the line "names the one this page will open, and says the publication is also
    /// available elsewhere". The copy this page opens is always the one on the device when
    /// there is one — that is the copy that survives a flight — so the *other* place is the
    /// library it was downloaded from, which the registry still knows by name.
    ///
    /// `nil` when there is no second place, and deliberately `nil` when the source has been
    /// removed: naming a library that no longer exists is the failure this field is most
    /// likely to produce, and `PublicationProvenanceTests` is what stops it.
    let alsoIn: String?

    /// The whole answer for one publication.
    ///
    /// - Parameters:
    ///   - isOnDevice: whether the app's own download store holds it. ``LibraryModel``
    ///     answers this with a path comparison, so it costs nothing to ask here.
    ///   - hasFile: whether the library can currently place a file for it. A folder that
    ///     has been unmounted answers `false` while its rows are still on the shelf, which
    ///     is exactly the case that must not read as "readable now".
    ///   - source: the source the registry still holds for it, or `nil` when the
    ///     publication is unattributed *or* its source has been removed. The two are
    ///     treated alike on purpose: neither is a library the reader can be sent to.
    static func of(
        _ publication: Publication,
        isOnDevice: Bool,
        hasFile: Bool,
        source: Source?
    ) -> PublicationProvenance {
        // The download store's copy wins the question of *where*, whatever else is true.
        // `offline-downloads` promises a download stays readable when its source is
        // removed, and a line that went on naming the removed server would contradict the
        // promise on the same screen that makes it.
        if isOnDevice {
            return PublicationProvenance(
                home: .thisDevice,
                availability: .offline,
                alsoIn: source?.displayName
            )
        }

        guard let source else {
            // A file in the app's own storage is on this device even though nothing
            // downloaded it — an import, or the folder the app itself owns. It reads as
            // being here, because it is.
            return hasFile
                ? PublicationProvenance(home: .thisDevice, availability: .offline, alsoIn: nil)
                : PublicationProvenance(home: .unattributed, availability: .notHere, alsoIn: nil)
        }

        return PublicationProvenance(
            home: .library(name: source.displayName),
            availability: availability(hasFile: hasFile, state: source.state),
            alsoIn: nil
        )
    }

    /// What the second clause says for a publication held in a library.
    ///
    /// A present file beats a connection state: a picked folder is "connected" in the sense
    /// the registry means and its publications are readable whether or not anything is
    /// reachable, and a server's cached chapter that has already been fetched is readable
    /// while the server is away. Only when there is no file does the connection decide
    /// between *not here yet* and *not answering*, which are different problems with
    /// different next steps.
    private static func availability(
        hasFile: Bool,
        state: SourceConnectionState
    ) -> Availability {
        if hasFile { return .now }
        if case .unreachable = state { return .notAnswering }
        return .notHere
    }
}
