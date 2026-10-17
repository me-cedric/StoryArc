import Darwin
import Foundation
import StoryArcCore

/// A defaults suite of its own for one test, removed when the test ends.
struct ScratchDefaults {
    let defaults: UserDefaults
    let name: String

    init(prefix: String) throws {
        name = "\(prefix)\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: name) else { throw ScratchError.noSuite(name) }
        defaults = suite
    }

    func remove() {
        defaults.removePersistentDomain(forName: name)
    }

    enum ScratchError: Error { case noSuite(String) }
}

/// Files the tests read, from the test bundle rather than from the checkout.
///
/// `project.yml` copies `packages/test-fixtures/comics` and the app's entitlements file into
/// the bundle. A test hosted in the sandboxed app that opens a path under `~/Documents`
/// waits on a privacy prompt, so nothing here names a path in the repository.
enum TestFixtures {
    private final class Marker {}

    static var bundle: Bundle { Bundle(for: Marker.self) }

    /// `packages/test-fixtures/comics`, as copied into the bundle.
    static var comics: URL {
        bundle.bundleURL.appending(path: "Contents/Resources/comics", directoryHint: .isDirectory)
    }

    /// `App/StoryArcMac.entitlements`, as copied into the bundle.
    static var entitlements: URL {
        bundle.bundleURL.appending(path: "Contents/Resources/StoryArcMac.entitlements")
    }

    /// One comic fixture, copied to a fresh temporary folder the test owns.
    ///
    /// A reader writes progress and covers next to nothing, but a test that renames or
    /// deletes must never touch the bundle, so it works on a copy.
    static func copy(_ name: String) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: name)
        try FileManager.default.copyItem(at: comics.appending(path: name), to: target)
        return target
    }

    /// 2020-01-01 at noon UTC: the date the first comic by name arrived. Noon, so the day is
    /// the same in every time zone.
    static let firstArrival = Date(timeIntervalSince1970: 1_577_880_000)

    /// `comics`, copied to `folder` afresh, each copy carrying ``arrival(at:)`` for its place.
    ///
    /// A checkout gives every fixture the day it was cloned, and a copy the moment it was made,
    /// and *Recently added* sorts by the second: the order Home draws would follow whichever
    /// file the copy reached first. Each copy is given its own fixed date instead, so every
    /// machine draws the same shelf. The folder is replaced rather than reused because the
    /// container outlives the run and could hold an older fixture set.
    static func layDownComics(at folder: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: folder.path(percentEncoded: false)) { try manager.removeItem(at: folder) }
        try manager.copyItem(at: comics, to: folder)
        let names = try manager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            .filter { !$0.hasPrefix(".") }
            .sorted()
        for (index, name) in names.enumerated() {
            try pin(folder.appending(path: name), to: arrival(at: index))
        }
    }

    /// The fixed date of the comic at `index` in name order: a day after the one before it.
    static func arrival(at index: Int) -> Date {
        firstArrival.addingTimeInterval(TimeInterval(index) * 86_400)
    }

    /// Sets a file's creation, modification and date added to `date`.
    ///
    /// The library reads the date added first, and the Finder's date added is not one of
    /// `FileManager`'s attributes: it is set with `setattrlist`.
    private static func pin(_ file: URL, to date: Date) throws {
        let path = file.path(percentEncoded: false)
        try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: path)
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_ADDEDTIME)
        var time = timespec(tv_sec: Int(date.timeIntervalSince1970), tv_nsec: 0)
        guard setattrlist(path, &list, &time, MemoryLayout<timespec>.size, 0) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

/// Publications for the pure tests, each with a stable path identity.
enum TestPublications {
    static func make(_ index: Int, series: String? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/\(index).cbz"),
            format: .cbz,
            displayTitle: "Title \(index)",
            series: series,
            number: series == nil ? nil : "\(index)",
            origin: .inferred,
            pageCount: 24
        )
    }

    /// One whose identity is its name, for tests that speak in names rather than numbers.
    static func named(_ name: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/\(name).cbz"),
            format: .cbz,
            displayTitle: name,
            origin: .inferred,
            pageCount: 24
        )
    }
}
