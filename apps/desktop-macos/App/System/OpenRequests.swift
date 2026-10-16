import Foundation
import Formats
import StoryArcCore

/// A file handed over by Finder, a drop, the Dock or the command line, and what came of it.
///
/// A Mac-side copy of `apps/ios/App/OpenedFile.swift`'s outcome and indexing, carried here
/// until parent task 5.12 shares the shell code. The cases are the ones `local-library` and
/// `publication-formats` word refusals for; `RefusedFile` turns each into a sentence.
enum MacOpenedFile {
    enum Outcome: Sendable, Equatable {
        case opened(Publication)
        case unsupported(detected: String)
        case contentProtected
        case passwordProtected
        case damaged
        case solidArchive
        case unreadable
    }

    /// Indexes a handed-over file, holding its security scope for as long as that takes.
    static func index(_ url: URL) async -> Outcome {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return .unreadable }
        do {
            let publication = try await PublicationIndexer.index(fileAt: url)
            guard publication.isOpenable else { return .solidArchive }
            return .opened(publication)
        } catch let error as PublicationIndexer.IndexError {
            if case let .unsupported(format) = error { return .unsupported(detected: format) }
            if case .contentProtected = error { return .contentProtected }
            if case .archivePasswordProtected = error { return .passwordProtected }
            if case .archiveUnreadable = error { return .damaged }
            return .unreadable
        } catch {
            return .unreadable
        }
    }
}

/// A file the app would not open, named with the reason, for the library's
/// *What could not be opened* list.
struct RefusedFile: Identifiable, Sendable, Equatable {
    let name: String
    let outcome: MacOpenedFile.Outcome

    var id: String { name }

    /// Every format the app reads, as `local-library` asks the refusal to state.
    static let supported = "CBZ, CBR, CBT, EPUB, PDF"
}

/// How many files a drop opens at once, and what happens to the rest.
///
/// `desktop-experience`, *Dropping several files*: each opens in its own window up to a
/// limit the app names, and the rest are listed so the reader can open them from the
/// library. Task 2.18.
enum OpenBatch {
    static let windowLimit = 6

    struct Plan: Equatable, Sendable {
        let open: [URL]
        let listed: [URL]
    }

    static func plan(_ urls: [URL], limit: Int = windowLimit) -> Plan {
        Plan(open: Array(urls.prefix(limit)), listed: Array(urls.dropFirst(limit)))
    }

    /// Folders and files apart: a folder dropped on the library is offered as a source.
    static func split(_ urls: [URL]) -> (files: [URL], folders: [URL]) {
        var files: [URL] = []
        var folders: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            let path = url.path(percentEncoded: false)
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            if exists, isDirectory.boolValue { folders.append(url) } else { files.append(url) }
        }
        return (files, folders)
    }
}

/// The publications opened lately, for the Dock menu and the Go menu.
///
/// `desktop-experience`, *Recent items in the system's launcher*: newest first, and a file
/// that no longer exists drops out of the list without an error. File > Open Recent is the
/// system's own list through `NSDocumentController`; this is the app's, keyed by
/// publication so one book opened from two paths is one entry.
struct RecentPublications: Sendable {
    static let defaultsKey = "app.storyarc.mac.recentPublications"
    static let limit = 5

    // UserDefaults is documented as thread-safe; it is not marked Sendable in the SDK.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let fileExists: @Sendable (URL) -> Bool

    init(
        defaults: UserDefaults = .standard,
        fileExists: @escaping @Sendable (URL) -> Bool = {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }
    ) {
        self.defaults = defaults
        self.fileExists = fileExists
    }

    func note(_ target: ReaderTarget) {
        var all = stored().filter { $0 != target }
        all.insert(target, at: 0)
        write(Array(all.prefix(Self.limit)))
    }

    /// Newest first, with every entry whose file is gone left out silently.
    func listing() -> [ReaderTarget] {
        let present = stored().filter { fileExists($0.url) }
        if present.count != stored().count { write(present) }
        return present
    }

    func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func stored() -> [ReaderTarget] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let targets = try? JSONDecoder().decode([ReaderTarget].self, from: data)
        else { return [] }
        return targets
    }

    private func write(_ targets: [ReaderTarget]) {
        guard let data = try? JSONEncoder().encode(targets) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
