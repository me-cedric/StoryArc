import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// One folder, two spellings, and the reconcile that has to survive both.
///
/// `/var` is a symbolic link to `/private/var` on macOS and on iOS. A security-scoped
/// bookmark resolves to the canonical `/private/var/…`; a publication's identity holds
/// `(path as NSString).standardizingPath`, which strips the `/private` prefix again. So the
/// same file reaches ``LibraryModel/forgetVanished(under:seen:partial:)`` as two strings that
/// never compare equal, and the walk's reconcile matches nothing on a bookmarked folder —
/// every book the reader deleted stays on the shelf, and opening one finds no file.
///
/// `LibraryScanner.normalized(_:)` names the same hazard for the resumed scan, and
/// ``LibraryModel/isAppStorage(_:)`` resolves both sides before comparing them. This suite
/// pins the third place that has to.
///
/// Real folders and the real corpus, for `LibraryShelfLifecycleTests`' reason: a spelling
/// defect asserted against a mock proves nothing about a directory a reader can revoke.
@Suite("Vanished under either path spelling")
@MainActor
struct VanishedSpellingTests {

    // MARK: - Places

    /// Walks up from this file to the committed fixture corpus.
    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let corpus = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: corpus.appending(path: "manifest.json").path) {
                return corpus
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found — expected packages/test-fixtures above \(#filePath)")
    }()

    private func temporary(_ prefix: String) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func copy(_ fixture: String, as name: String, into folder: URL) throws -> URL {
        let file = folder.appending(path: name)
        try FileManager.default.copyItem(at: Self.corpus.appending(path: "comics/\(fixture)"), to: file)
        return file
    }

    /// The same directory, spelled the way a resolved bookmark spells it.
    ///
    /// Composed rather than asked of `resolvingSymlinksInPath()`, which standardises after it
    /// resolves and hands back the `/var` spelling again — the one spelling this suite must
    /// not use. The existence check is the guard: it fails loudly if a future platform stops
    /// linking `/var`, rather than testing a path that is not the folder.
    private func canonical(_ folder: URL) throws -> URL {
        let canonical = URL(fileURLWithPath: "/private" + folder.path)
        try #require(FileManager.default.fileExists(atPath: canonical.path), """
            /var is not a symbolic link to /private/var on this host, so this suite cannot \
            build the spelling a resolved bookmark hands back.
            """)
        return canonical
    }

    /// A model whose cache and Documents folder are its own, so no test reaches the machine's.
    private func model(cacheIn directory: URL, documents: URL) -> LibraryModel {
        LibraryModel(documents: documents, cache: LibraryCache(directory: directory))
    }

    // MARK: - The bookmarked spelling

    @Test("A book that has gone is forgotten when the folder is spelled /private/var")
    func vanishedIsForgottenUnderTheCanonicalSpelling() async throws {
        let documents = try temporary("spelling-documents")
        let cache = try temporary("spelling-cache")
        defer {
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: cache)
        }
        try copy("single-page.cbz", as: "01.cbz", into: documents)
        let leaving = try copy("natural-sort.cbz", as: "02.cbz", into: documents)

        // What `FolderBookmarks.restore()` hands the model for a folder the reader picked.
        let bookmarked = try canonical(documents)
        let model = model(cacheIn: cache, documents: bookmarked)
        model.scan(bookmarked)
        await model.scanTask?.value
        try #require(model.publications.count == 2)

        try FileManager.default.removeItem(at: leaving)
        model.scan(bookmarked)
        await model.scanTask?.value

        #expect(model.publications.count == 1, """
            A publication whose file is gone stayed on the shelf because its stored location \
            is spelled /var and the folder it was found under is spelled /private/var. \
            `sources` removes a publication that is no longer present in the source.
            """)
    }

    @Test("A book that is still there survives the folder being spelled /private/var")
    func presentIsKeptUnderTheCanonicalSpelling() async throws {
        // The other direction of the same comparison, and the one that costs a reader their
        // library rather than a dead row: a fix that resolved only one side would make every
        // publication look as though it had left the folder.
        let documents = try temporary("kept-documents")
        let cache = try temporary("kept-cache")
        defer {
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: cache)
        }
        try copy("single-page.cbz", as: "01.cbz", into: documents)
        try copy("natural-sort.cbz", as: "02.cbz", into: documents)

        let bookmarked = try canonical(documents)
        let model = model(cacheIn: cache, documents: bookmarked)
        model.scan(bookmarked)
        await model.scanTask?.value
        try #require(model.publications.count == 2)

        model.scan(bookmarked)
        await model.scanTask?.value

        #expect(model.publications.count == 2, """
            A walk that found both books forgot one of them. What the walk saw is present, \
            whichever way its folder is spelled.
            """)
    }

    // MARK: - The plain spelling

    @Test("A book that has gone is still forgotten when the folder is spelled /var")
    func vanishedIsForgottenUnderThePlainSpelling() async throws {
        // The spelling every host test uses, pinned here so a fix for the canonical one
        // cannot quietly stop the reconcile working for the other.
        let documents = try temporary("plain-documents")
        let cache = try temporary("plain-cache")
        defer {
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: cache)
        }
        try copy("single-page.cbz", as: "01.cbz", into: documents)
        let leaving = try copy("natural-sort.cbz", as: "02.cbz", into: documents)

        let model = model(cacheIn: cache, documents: documents)
        model.scan(documents)
        await model.scanTask?.value
        try #require(model.publications.count == 2)

        try FileManager.default.removeItem(at: leaving)
        model.scan(documents)
        await model.scanTask?.value

        #expect(model.publications.count == 1, """
            A publication whose file is gone stayed on the shelf. `sources` removes a \
            publication that is no longer present in the source.
            """)
    }

    // MARK: - The neighbouring folder

    @Test("A book in a folder whose name merely starts with the scanned one is kept")
    func aSiblingFolderIsNotReadAsBeingInside() async throws {
        // The boundary the prefix comparison has to respect. `…/Comics` and `…/Comics2` are
        // two libraries, and a walk of the first must not decide the second's books have gone.
        let parent = try temporary("sibling-parent")
        let cache = try temporary("sibling-cache")
        defer {
            try? FileManager.default.removeItem(at: parent)
            try? FileManager.default.removeItem(at: cache)
        }
        let scanned = parent.appending(path: "Comics")
        let neighbour = parent.appending(path: "Comics2")
        try FileManager.default.createDirectory(at: scanned, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: neighbour, withIntermediateDirectories: true)
        try copy("single-page.cbz", as: "01.cbz", into: scanned)
        try copy("natural-sort.cbz", as: "02.cbz", into: neighbour)

        let model = model(cacheIn: cache, documents: parent)
        model.scan([scanned, neighbour])
        await model.scanTask?.value
        try #require(model.publications.count == 2)

        model.scan(scanned)
        await model.scanTask?.value

        #expect(model.publications.count == 2, """
            The book in the neighbouring folder was forgotten by a walk that never looked in \
            it. A folder name is a whole path component, not a string prefix.
            """)
    }
}
