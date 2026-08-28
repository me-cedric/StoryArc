import Foundation
import Testing

@testable import StoryArcCore

/// Somewhere for a fixture download to have come from. The address is never dialled.
private func remote(_ name: String) -> URL {
    URL(fileURLWithPath: "/fixtures").appending(path: name)
}

@Suite("Reordering the download queue")
struct DownloadReorderTests {
    private func queued(_ ids: String...) -> DownloadLibrary {
        DownloadLibrary(downloads: ids.map {
            Download(id: $0, title: $0, remote: remote($0), mediaType: "x")
        })
    }

    @Test("moves one place later")
    func later() {
        #expect(queued("a", "b", "c").moving("a", later: true).downloads.map(\.id) == ["b", "a", "c"])
    }

    @Test("moves one place earlier")
    func earlier() {
        #expect(queued("a", "b", "c").moving("c", later: false).downloads.map(\.id) == ["a", "c", "b"])
    }

    @Test("will not move past either end")
    func bounded() {
        let library = queued("a", "b")
        #expect(library.moving("a", later: false).downloads.map(\.id) == ["a", "b"])
        #expect(library.moving("b", later: true).downloads.map(\.id) == ["a", "b"])
    }

    @Test("leaves a running download where it is")
    func skipsRunning() {
        let library = DownloadLibrary(downloads: [
            Download(id: "a", title: "a", remote: remote("a"), mediaType: "x", state: .running),
            Download(id: "b", title: "b", remote: remote("b"), mediaType: "x"),
            Download(id: "c", title: "c", remote: remote("c"), mediaType: "x"),
        ])
        // "b" is the first *queued* one, so it cannot go earlier even though "a" is above it.
        #expect(library.moving("b", later: false).downloads.map(\.id) == ["a", "b", "c"])
        #expect(library.moving("b", later: true).downloads.map(\.id) == ["a", "c", "b"])
    }
}
