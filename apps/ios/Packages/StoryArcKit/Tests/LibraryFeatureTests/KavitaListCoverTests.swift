import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

import Formats
import Kavita
@testable import LibraryFeature
import StoryArcCore

/// Tasks 6.4 and 5.1 of `cover-for-every-publication`: the write-back button is on the Kavita
/// reading-list screen, once a cover is chosen, and never on a list that is not the reader's.
/// Android's `KavitaListCoverTest` is the twin of this file.
struct KavitaListCoverTests {

    private func lists(promoted: Bool) throws -> [KavitaReadingList] {
        let json = #"[{"id":8,"title":"Crossover","promoted":\#(promoted)}]"#
        return try JSONDecoder().decode([KavitaReadingList].self, from: Data(json.utf8))
    }

    // MARK: The rules

    @Test("No button without a chosen cover")
    func noButtonWithoutACover() throws {
        let subject = KavitaListCover.writeSubject(
            listID: 8, hasChosen: false, lists: try lists(promoted: false)
        )

        #expect(subject == nil)
    }

    @Test("An owned list with a chosen cover asks the button")
    func ownedListAsksTheButton() throws {
        let subject = KavitaListCover.writeSubject(
            listID: 8, hasChosen: true, lists: try lists(promoted: false)
        )

        #expect(subject == .kavitaReadingList(id: 8, promoted: false))
    }

    @Test("A promoted list is handed to the one rule that refuses it")
    func promotedListIsRefusedByTheRule() throws {
        let subject = try #require(KavitaListCover.writeSubject(
            listID: 8, hasChosen: true, lists: try lists(promoted: true)
        ))

        #expect(subject == .kavitaReadingList(id: 8, promoted: true))
        #expect(CoverWriteBack.offer(for: subject) == .none)
    }

    @Test("Ownership the server never stated proves nothing")
    func unstatedOwnershipOffersNothing() throws {
        #expect(KavitaListCover.writeSubject(listID: 8, hasChosen: true, lists: nil) == nil)
        #expect(
            KavitaListCover.writeSubject(
                listID: 9, hasChosen: true, lists: try lists(promoted: false)
            ) == nil
        )
    }

    // MARK: The store

    private let source = UUID()

    private func temporaryStore() -> (CoverOverrideStore, URL) {
        let directory = URL.temporaryDirectory.appending(path: "list-cover-\(UUID().uuidString)")
        return (CoverOverrideStore(directory: directory), directory)
    }

    @Test("A source that is not a UUID has nowhere to keep a list cover")
    func unnamedSourceKeepsNothing() {
        #expect(KavitaListCover.publication(serverID: "kavita-open", listID: 8) == nil)
        #expect(KavitaListCover.publication(serverID: source.uuidString, listID: 8) != nil)
    }

    @Test("A chosen list cover is filed, and is not a chapter's cover")
    func listCoverIsFiledApart() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let list = try #require(KavitaListCover.publication(serverID: source.uuidString, listID: 8))
        let chapter = Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: source, remoteID: "chapter:8")
            ),
            format: .cbz,
            displayTitle: "",
            origin: .authoritative
        )

        let stored = await KavitaListCover.choose(try pngData(), as: list, in: store)

        #expect(stored)
        #expect(store.data(for: list) != nil, "The chosen cover was not filed for the list.")
        #expect(store.data(for: chapter) == nil, "A list's cover was filed under a chapter's key.")
    }

    @Test("A picture that cannot be decoded is not filed")
    func undecodablePictureIsNotFiled() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let list = try #require(KavitaListCover.publication(serverID: source.uuidString, listID: 8))

        let stored = await KavitaListCover.choose(Data("not a picture".utf8), as: list, in: store)

        #expect(!stored)
        #expect(store.data(for: list) == nil)
    }

    // MARK: The placement

    /// The feature's own sources, found from this file: this repository nests agent
    /// worktrees, and a walk that climbs looking for a known folder leaves the checkout.
    private func source(_ name: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        let path = directory.appendingPathComponent("Sources/LibraryFeature/\(name)").path
        let text = try #require(
            try? String(contentsOfFile: path, encoding: .utf8),
            "\(path) could not be read. A guard that cannot find what it guards passes for ever."
        )
        // Code only: a comment that names the view is not a place that draws it.
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    @Test("The reading-list screen places the cover controls, and the collection screen does not")
    func placedOnTheListScreenOnly() throws {
        let views = try source("KavitaShelfViews.swift")
        let split = try #require(views.range(of: "struct KavitaListView"))
        let collection = String(views[..<split.lowerBound])
        let list = String(views[split.lowerBound...])

        #expect(list.contains("KavitaListCoverControls("), "The list screen does not place the cover controls.")
        #expect(!collection.contains("KavitaListCoverControls("))
        #expect(!collection.contains(".coverWriteBack("))
    }

    @Test("The write-back confirmation is placed in one view, which is the list's cover controls")
    func confirmationIsPlacedOnce() throws {
        let names = try FileManager.default
            .contentsOfDirectory(
                atPath: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("Sources/LibraryFeature").path
            )
            .filter { $0.hasSuffix(".swift") }
        let placed = try names.filter { try source($0).contains(".coverWriteBack(") }

        #expect(placed.sorted() == ["KavitaListCover.swift"])
    }

    // MARK: The menu

    @Test("A list with no chosen cover offers choosing and nothing else")
    func menuWithNoCover() throws {
        #expect(
            KavitaListCover.menuRows(listID: 8, hasChosen: false, lists: try lists(promoted: false))
                == [[.choose]]
        )
    }

    @Test("An owned list with a chosen cover offers sending, and removal in a group of its own")
    func menuWithAChosenCover() throws {
        #expect(
            KavitaListCover.menuRows(listID: 8, hasChosen: true, lists: try lists(promoted: false))
                == [[.choose, .sendToServer], [.remove]]
        )
    }

    @Test("A promoted list never offers sending")
    func menuOnAPromotedList() throws {
        #expect(
            KavitaListCover.menuRows(listID: 8, hasChosen: true, lists: try lists(promoted: true))
                == [[.choose], [.remove]]
        )
    }

    private func pngData() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 12))
        let image = try #require(context.makeImage())
        let buffer = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            buffer, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return buffer as Data
    }
}
