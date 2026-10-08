import Foundation
import Testing

@testable import StoryArcCore

/// `library-portability` task 6.5: the import screen refuses a file by the size the file system
/// reports, before it reads a byte. Android's `LibraryDocumentCoderTest` asserts the same rows.
@Suite("A file is admitted or refused by its size alone")
struct LibraryDocumentAdmitsTests {

    @Test("A file at the limit is admitted")
    func atTheLimit() throws {
        try LibraryDocumentCoder.admits(byteCount: LibraryDocumentCoder.maximumBytes)
    }

    @Test("A file one byte over is refused by name, with both sizes")
    func oneOver() {
        let over = LibraryDocumentCoder.maximumBytes + 1

        #expect(
            throws: LibraryDocumentFailure.tooLarge(found: over, limit: LibraryDocumentCoder.maximumBytes)
        ) {
            try LibraryDocumentCoder.admits(byteCount: over)
        }
    }

    @Test("The limit is injectable, so a test need not allocate 64 MiB")
    func anInjectedLimit() {
        #expect(throws: LibraryDocumentFailure.tooLarge(found: 11, limit: 10)) {
            try LibraryDocumentCoder.admits(byteCount: 11, limit: 10)
        }
    }
}
