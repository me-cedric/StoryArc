import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import StoryArcCore

/// The folder the app writes and the widget reads, asserted against the same table as
/// Android's `ReadingSnapshotStoreTest`. Add a case here, add it there.
@Suite("Reading snapshot store")
struct ReadingSnapshotStoreTests {

    private let store = ReadingSnapshotStore(
        folder: FileManager.default.temporaryDirectory.appending(path: "snapshot-\(UUID().uuidString)")
    )

    private func snapshot(_ title: String, percent: Int? = 10) -> ReadingSnapshot {
        ReadingSnapshot(publicationID: "path:/library/\(title)", title: title, series: nil, percentRead: percent)
    }

    private let jpeg = Data([0xFF, 0xD8, 0xFF])

    @Test("An empty folder holds no snapshot")
    func emptyFolder() {
        #expect(store.read() == nil)
    }

    @Test("A written snapshot and its cover are read back")
    func writeThenRead() async throws {
        let bone = snapshot("Bone 1")
        #expect(try await store.write(bone) { jpeg })
        #expect(store.read() == bone)
        let cover = try #require(store.cover(of: bone))
        #expect(try Data(contentsOf: cover) == jpeg)
    }

    @Test("The same snapshot again changes nothing and decodes no cover")
    func unchangedWritesNothing() async throws {
        let bone = snapshot("Bone 1")
        try await store.write(bone) { jpeg }
        let asked = Asked()
        #expect(try await store.write(bone) { await asked.mark(); return jpeg } == false)
        #expect(await asked.count < 1)
    }

    @Test("A new percent is written, and keeps the cover")
    func newPercent() async throws {
        try await store.write(snapshot("Bone 1", percent: 10)) { jpeg }
        let further = snapshot("Bone 1", percent: 11)
        #expect(try await store.write(further) { nil })
        #expect(store.read() == further)
        #expect(store.cover(of: further) != nil)
    }

    @Test("Another book removes the previous cover, and shows none until its own is written")
    func staleCoverGoes() async throws {
        let bone = snapshot("Bone 1")
        try await store.write(bone) { jpeg }
        let saga = snapshot("Saga 1")
        try await store.write(saga) { nil }

        #expect(store.read() == saga)
        #expect(store.cover(of: saga) == nil)
        #expect(store.cover(of: bone) == nil)
    }

    @Test("No book to continue clears the snapshot and the cover")
    func clearRemovesAll() async throws {
        let bone = snapshot("Bone 1")
        try await store.write(bone) { jpeg }
        #expect(try await store.write(nil) { jpeg })
        #expect(store.read() == nil)
        #expect(store.cover(of: bone) == nil)
        #expect(try await store.write(nil) { jpeg } == false)
    }

    @Test("A stored cover is no longer than the widget needs, and a small one is not enlarged")
    func coverIsWidgetSized() throws {
        func stored(width: Int, height: Int) throws -> CGImage {
            let context = try #require(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ))
            let image = try #require(context.makeImage())
            let jpeg = try #require(ReadingSnapshotStore.coverJPEG(image))
            let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
            return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }
        let screenWide = try stored(width: 1206, height: 1809)
        #expect(screenWide.height == ReadingSnapshot.coverPixels)
        #expect(screenWide.width < screenWide.height)
        let small = try stored(width: 32, height: 48)
        #expect(small.width == 32 && small.height == 48)
    }

    @Test("A record another version wrote is not shown")
    func otherVersionIsNotShown() throws {
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try Data(#"{"version":0,"publicationID":"a","title":"Bone 1"}"#.utf8)
            .write(to: store.folder.appending(path: ReadingSnapshotStore.snapshotFile))
        #expect(store.read() == nil)
    }
}

private actor Asked {
    private(set) var count = 0
    func mark() { count += 1 }
}
