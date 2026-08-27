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
        /// The file could not be reached or could not be understood at all.
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
            return .opened(try await PublicationIndexer.index(fileAt: url))
        } catch let error as PublicationIndexer.IndexError {
            // Named, not generic. `local-library`: "the app names the format it detected
            // and states which formats it supports, rather than reporting a generic
            // failure". The reader chose this file, so they can tell a wrong pick from a
            // broken app only if the app says which it is.
            if case let .unsupported(format) = error {
                return .unsupported(detected: format)
            }
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
    static func remember(_ url: URL, in bookmarks: FolderBookmarks) -> Bool {
        (try? bookmarks.add(url)) != nil
    }
}
