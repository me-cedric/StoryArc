import Foundation

import Formats
import Persistence
import StoryArcCore

/// A publication the system handed to the app, and what to do with it.
///
/// `local-library` requires StoryArc to "open a supported publication handed to it by the
/// system without requiring the user to configure a source first". `Info.plist` already
/// declares the app as a handler for six formats, so the system offers it and hands the
/// file over. Nothing was listening, so every one of those files was dropped — the app
/// opened its library and said nothing at all.
///
/// Kept out of `StoryArcApp` because opening a handed-over file is three separate jobs:
/// reaching a file outside the sandbox, deciding what it is, and saying so when it is
/// nothing StoryArc reads.
enum OpenedFile {

    /// What came of a file the system handed over.
    enum Outcome: Sendable {
        case opened(Publication)
        /// The format was recognised and StoryArc does not read it.
        case unsupported(detected: String)
        /// The format is one StoryArc reads, and this file is locked by the store that
        /// sold it. `publication-formats` requires this refusal to be "distinct from an
        /// unsupported container", so it is a case rather than a different string in the
        /// one above — those two words are the only thing a reader can act on.
        case contentProtected
        /// The archive asked for a password. Its own case, distinct from ``damaged``, so
        /// the sentence never asks for one — StoryArc does not manage archive passwords.
        case passwordProtected
        /// A format StoryArc reads, and this particular file is damaged beyond recovery.
        /// Distinct from ``unsupported`` on purpose: the sentence must not list the
        /// formats StoryArc reads or suggest a conversion, because neither would help.
        case damaged
        /// A comic that uses solid compression. The container is supported and every
        /// header parsed; no decoder with an OSI-approved licence reads one at all, local
        /// or remote, so the archive is refused before the reader opens it rather than
        /// after.
        case solidArchive
        /// The file could not be reached, or is not anything StoryArc recognises at all.
        case unreadable
    }

    /// Indexes a handed-over file, holding its security scope for as long as that takes.
    ///
    /// A URL from another app points outside the sandbox. Reading it needs the scope
    /// started and stopped around the read, and `Info.plist` sets
    /// `LSSupportsOpeningDocumentsInPlace` so the file stays where its owner put it
    /// rather than being copied into an Inbox.
    static func index(_ url: URL) async -> Outcome {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let publication = try await PublicationIndexer.index(fileAt: url)
            // A solid RAR4 opens as a *record* rather than throwing — the library lists it
            // and says why. Open-in has no library row to show it in, so the refusal has
            // to happen here, before the reader is sent to a page it cannot render.
            guard publication.isOpenable else { return .solidArchive }
            return .opened(publication)
        } catch let error as PublicationIndexer.IndexError {
            // Named, not generic. `local-library`: "the app names the format it detected
            // and states which formats it supports, rather than reporting a generic
            // failure". The reader chose this file, so they can tell a wrong pick from a
            // broken app only if the app says which it is.
            if case let .unsupported(format) = error {
                return .unsupported(detected: format)
            }
            if case .contentProtected = error { return .contentProtected }
            if case .archivePasswordProtected = error { return .passwordProtected }
            if case .archiveUnreadable = error { return .damaged }
            return .unreadable
        } catch {
            return .unreadable
        }
    }

    /// Remembers a handed-over file, so it survives the app being closed.
    ///
    /// A bookmark to the file itself rather than a copy of it. `local-library` has a
    /// separate requirement for imported copies, and this is the cheaper half of the
    /// promise: the reader keeps the file where it is and StoryArc can reach it again.
    ///
    /// The file, not the folder above it. A grant on a document says nothing about its
    /// directory — a share sheet may hand over a file whose parent this app is not entitled
    /// to read, or which has no reachable parent at all — so bookmarking the containing
    /// folder would fail on the cases this exists for. ``FolderBookmarks`` keeps the two
    /// kinds of place apart, and the library puts a remembered file on the shelf as one
    /// publication rather than as a library to walk.
    ///
    /// Inside its own security scope. ``index(_:)`` stops the scope it started, and a
    /// bookmark made outside the scope of a URL another app owns is refused — which is what
    /// happened here: the call returned `false` and the file was quietly not remembered.
    static func remember(_ url: URL, in bookmarks: FolderBookmarks) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return (try? bookmarks.add(url)) != nil
    }
}
