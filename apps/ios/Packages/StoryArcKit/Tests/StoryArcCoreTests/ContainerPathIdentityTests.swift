import Foundation
import Testing
@testable import StoryArcCore

/// Task 26.4: a reinstall moves the app container, and a position must not stay behind.
@Suite("A position survives a reinstall")
struct ContainerPathIdentityTests {

    private static let root = "/var/mobile/Containers/Data/Application"
    private let before = "\(root)/0B6E1F5C-2C2E-4C59-8E44-0D6C0A1E2B11/Documents/Tales"
    private let after = "\(root)/7F3A9D20-5B1C-4E7A-9F02-3C4D5E6F7A88/Documents/Tales"

    @Test("One place in two containers is one publication")
    func onePlaceInTwoContainersMatches() {
        let old = PublicationIdentity(normalizedPath: before)
        let new = PublicationIdentity(contentDigest: "folder", normalizedPath: after)
        #expect(new.matches(old))
        #expect(PublicationIdentity.containerRelativePath(after) == "Documents/Tales")
    }

    @Test("Two places outside a container stay two publications")
    func pathsOutsideAContainerDoNotMatch() {
        let one = PublicationIdentity(normalizedPath: "/books/A/Tales")
        let two = PublicationIdentity(normalizedPath: "/books/B/Tales")
        #expect(!one.matches(two))
        #expect(PublicationIdentity.containerRelativePath("/Containers/Data/Application/x/Tales") == nil)
    }

    @Test("A document with seven copies of one book merges to one record with the device's identity")
    func sevenCopiesBecomeOne() {
        let copies = (1...7).map { index in
            ReadingProgress(
                identity: PublicationIdentity(normalizedPath: before.replacingOccurrences(
                    of: "0B6E1F5C-2C2E-4C59-8E44-0D6C0A1E2B1", with: "0B6E1F5C-2C2E-4C59-8E44-0D6C0A1E2B\(index)"
                )),
                position: .listening(part: index, partCount: 9, offset: 10, of: 60),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index * 100))
            )
        }
        let document = LibraryExport.document(
            LibrarySnapshot(progress: copies), appVersion: "1", writtenAt: Date(timeIntervalSince1970: 900)
        )
        let mine = PublicationIdentity(contentDigest: "folder", normalizedPath: after)
        let local = LibrarySnapshot(progress: [
            ReadingProgress(
                identity: mine,
                position: .listening(part: 0, partCount: 9, offset: 0, of: 60),
                updatedAt: Date(timeIntervalSince1970: 50)
            ),
        ])

        let merged = LibrarySyncMerge.merging(document, into: local, device: "phone").snapshot.progress

        #expect(merged.count == 1)
        #expect(merged.first?.identity == mine)
        #expect(merged.first?.position == .listening(part: 7, partCount: 9, offset: 10, of: 60))
    }
}
