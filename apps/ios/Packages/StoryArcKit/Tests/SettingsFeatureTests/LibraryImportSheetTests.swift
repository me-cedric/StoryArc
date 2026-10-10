import Foundation
import Testing

@testable import Persistence
@testable import SettingsFeature
import StoryArcCore

/// `library-portability` tasks 3.1, 5.4 and 6.8: the import flow, from the picked file to what
/// the reader is told. Android's `LibraryImportSheetTest` asserts the same rows.
@MainActor
@Suite("The import sheet states what will happen, and nothing changes until the reader agrees")
struct LibraryImportSheetTests {

    private struct Vector: Decodable {
        let passphrase: String
        let secrets: LibrarySecrets
    }

    private func vector() throws -> Vector {
        var directory = URL(filePath: #filePath)
        while directory.pathComponents.count > 1 {
            directory.deleteLastPathComponent()
            let file = directory.appending(path: "packages/test-fixtures/library/sealed-secrets.json")
            if let data = try? Data(contentsOf: file) {
                return try JSONDecoder().decode(Vector.self, from: data)
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    /// A file a picker would hand over: the library, sealed by the committed vector or not.
    private func pickedFile(sealed: Bool, version: Int = 1) throws -> URL {
        let document = LibraryExport.document(
            TransferDevice.library,
            appVersion: "10.14.0",
            writtenAt: Date(timeIntervalSince1970: 1_767_225_845),
            secrets: sealed ? try vector().secrets : nil
        )
        let text = (String(bytes: try LibraryDocumentCoder.encode(document), encoding: .utf8) ?? "")
            .replacing("\"formatVersion\" : 1", with: "\"formatVersion\" : \(version)")
        return try TransferDevice.file(holding: Data(text.utf8))
    }

    private func sheet(_ model: LibraryImportModel, _ device: TransferDevice) -> LibraryImportSheet {
        LibraryImportSheet(model: model, transfer: device.transfer, onImported: { _ in }, onClose: {})
    }

    // MARK: Nothing changes first

    @Test("Reading a file plans the import and changes nothing")
    func readingChangesNothing() async throws {
        let device = try TransferDevice()
        let before = try await device.archive.snapshot()
        let model = LibraryImportModel()

        await model.load(try pickedFile(sealed: true), with: device.transfer)

        guard case let .preview(preview) = model.phase else {
            Issue.record("expected a preview, got \(model.phase)")
            return
        }
        #expect(preview.plan.sourcesToAdd == ["Comics NAS", "Kavita"])
        #expect(try await device.archive.snapshot() == before)
        #expect(device.secrets.contents.isEmpty)
    }

    @Test("Confirming imports, tells the app once, and reports what it did")
    func confirmingImports() async throws {
        let device = try TransferDevice()
        let model = LibraryImportModel()
        await model.load(try pickedFile(sealed: false), with: device.transfer)
        var told: [LibraryImportOutcome] = []

        await model.confirm(transfer: device.transfer, skippingSecrets: false) { told.append($0) }

        guard case let .done(outcome) = model.phase else {
            Issue.record("expected done, got \(model.phase)")
            return
        }
        #expect(told == [outcome])
        #expect(try await device.archive.snapshot().sources.sources.map(\.displayName) == ["Comics NAS", "Kavita"])
        #expect(outcome.sourcesNeedingSignIn == ["Comics NAS", "Kavita"])
    }

    // MARK: What the preview draws (6.8)

    @Test("The sheet draws the plan's lines, the pin notice among them")
    func theSheetDrawsThePlansLines() async throws {
        let device = try TransferDevice()
        let model = LibraryImportModel()
        await model.load(try pickedFile(sealed: false), with: device.transfer)

        guard case let .preview(preview) = model.phase else {
            Issue.record("expected a preview, got \(model.phase)")
            return
        }
        let lists = values(of: ImportPreviewList.self, in: sheet(model, device))

        #expect(lists.map(\.lines) == [preview.plan.previewLines])
        #expect(lists.first?.lines.contains(.certificatePins(
            [CertificatePinNotice(host: "nas.local", sourceName: "Comics NAS")]
        )) == true)
    }

    @Test("A shelf that exists on both sides is in the plan with the members the import adds")
    func aMergedShelfIsInThePlan() async throws {
        let shelf = PublicationCollection(name: "Image Comics", members: ["path:/a.cbz"])
        let device = try await TransferDevice().holding(LibrarySnapshot(shelves: Shelves(collections: [shelf])))
        var carried = TransferDevice.library
        carried.shelves = Shelves(collections: [
            PublicationCollection(id: shelf.id, name: "Image Comics", members: ["path:/a.cbz", "path:/b.cbz"]),
        ])
        let document = LibraryExport.document(
            carried, appVersion: "10.14.0", writtenAt: Date(timeIntervalSince1970: 1_767_225_845)
        )
        let file = try TransferDevice.file(holding: try LibraryDocumentCoder.encode(document))
        let model = LibraryImportModel()

        await model.load(file, with: device.transfer)

        guard case let .preview(preview) = model.phase else {
            Issue.record("expected a preview, got \(model.phase)")
            return
        }
        let lists = values(of: ImportPreviewList.self, in: sheet(model, device))
        let merged = ImportedShelf(name: "Image Comics", membersAdded: 1)
        #expect(preview.plan.shelvesToMerge == [merged])
        #expect(lists.first?.lines.contains(.shelvesMerged([merged])) == true)
    }

    // MARK: A refusal is by name

    @Test("A newer version is refused by name on the screen, and the device is unchanged")
    func aNewerVersionIsRefusedByName() async throws {
        let device = try TransferDevice()
        let before = try await device.archive.snapshot()
        let model = LibraryImportModel()

        await model.load(try pickedFile(sealed: false, version: 9), with: device.transfer)

        #expect(model.phase == .refused(.document(.newerThanThisApp(found: 9, understood: 1))))
        let keys = lookups(in: sheet(model, device))
        #expect(keys.contains("transfer.refused.title"))
        #expect(keys.contains("transfer.refused.newer %lld %lld"), "the screen looked up \(keys.sorted())")
        #expect(try await device.archive.snapshot() == before)
    }

    @Test("A file that is not a library file is refused by name")
    func notALibraryFile() async throws {
        let device = try TransferDevice()
        let model = LibraryImportModel()

        await model.load(try TransferDevice.file(holding: Data("hello".utf8)), with: device.transfer)

        #expect(model.phase == .refused(.document(.notALibraryDocument)))
        #expect(lookups(in: sheet(model, device)).contains("transfer.refused.notADocument"))
    }

    @Test("A file over the limit is refused from its size, before it is read")
    func anOversizedFileIsNotRead() async throws {
        let device = try TransferDevice()
        let model = LibraryImportModel()
        // A file the process may not read, with a size over the limit. Had the screen tried to
        // read it, the answer would be "unopened"; it asks the size first.
        let url = try TransferDevice.file(holding: Data())
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(LibraryDocumentCoder.maximumBytes + 1))
        try handle.close()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path())
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path()) }

        await model.load(url, with: device.transfer)

        #expect(model.phase == .refused(.document(.tooLarge(
            found: LibraryDocumentCoder.maximumBytes + 1,
            limit: LibraryDocumentCoder.maximumBytes
        ))))
        #expect(lookups(in: sheet(model, device)).contains("transfer.refused.tooLarge %@ %@"))
    }

    @Test("A file that cannot be opened says so and changes nothing")
    func anUnopenableFile() async throws {
        let device = try TransferDevice()
        let model = LibraryImportModel()

        await model.load(URL(filePath: "/nonexistent/library.json"), with: device.transfer)

        #expect(model.phase == .refused(.unopened))
    }

    // MARK: The passphrase (5.4)

    @Test("A document with secrets asks for the passphrase, and one without does not")
    func thePromptFollowsTheDocument() async throws {
        let device = try TransferDevice()
        let sealed = LibraryImportModel()
        let plain = LibraryImportModel()
        await sealed.load(try pickedFile(sealed: true), with: device.transfer)
        await plain.load(try pickedFile(sealed: false), with: device.transfer)

        let sealedKeys = lookups(in: sheet(sealed, device))
        let plainKeys = lookups(in: sheet(plain, device))

        #expect(sealedKeys.contains("transfer.import.secrets"))
        #expect(sealedKeys.contains("transfer.passphrase"))
        #expect(sealedKeys.contains("transfer.import.withoutSecrets"))
        #expect(!plainKeys.contains("transfer.passphrase"))
        #expect(!plainKeys.contains("transfer.import.secrets"))
    }

    @Test("A wrong passphrase is stated and the reader may try again")
    func aWrongPassphraseMayBeRetried() async throws {
        let device = try TransferDevice()
        let before = try await device.archive.snapshot()
        let model = LibraryImportModel()
        await model.load(try pickedFile(sealed: true), with: device.transfer)

        model.passphrase = "not it"
        await model.confirm(transfer: device.transfer, skippingSecrets: false) { _ in }

        guard case .preview = model.phase else {
            Issue.record("expected the preview again, got \(model.phase)")
            return
        }
        #expect(model.passphraseRefused)
        #expect(lookups(in: sheet(model, device)).contains("transfer.import.wrong"))
        #expect(try await device.archive.snapshot() == before)

        model.passphrase = try vector().passphrase
        await model.confirm(transfer: device.transfer, skippingSecrets: false) { _ in }

        guard case let .done(outcome) = model.phase else {
            Issue.record("expected done, got \(model.phase)")
            return
        }
        #expect(outcome.secretsWritten == 2)
        #expect(device.secrets.contents.count == 2)
        #expect(model.passphrase.isEmpty)
    }

    @Test("Skipping imports the rest and the result names the sources that need a sign-in")
    func skippingNamesTheSignIns() async throws {
        let device = try TransferDevice()
        let model = LibraryImportModel()
        await model.load(try pickedFile(sealed: true), with: device.transfer)

        await model.confirm(transfer: device.transfer, skippingSecrets: true) { _ in }

        guard case let .done(outcome) = model.phase else {
            Issue.record("expected done, got \(model.phase)")
            return
        }
        #expect(outcome.sourcesNeedingSignIn == ["Comics NAS", "Kavita"])
        #expect(device.secrets.contents.isEmpty)
        let keys = lookups(in: sheet(model, device))
        #expect(keys.contains("transfer.done.signIn %lld"))
    }

    // MARK: Conflicts, once

    @Test("A position both devices moved is named once, with both positions")
    func aConflictNamesBothPositions() async throws {
        let identity = PublicationIdentity(contentDigest: "d1", normalizedPath: "/a.cbz")
        var carried = TransferDevice.library
        carried.progress = [
            ReadingProgress(
                identity: identity,
                position: .page(index: 12, of: 40),
                updatedAt: Date(timeIntervalSince1970: 1_767_100_000)
            ),
        ]
        let device = try await TransferDevice().holding(
            LibrarySnapshot(progress: [
                ReadingProgress(
                    identity: identity,
                    position: .page(index: 30, of: 40),
                    updatedAt: Date(timeIntervalSince1970: 1_767_200_000),
                    syncedPosition: .page(index: 1, of: 40)
                ),
            ])
        )
        let document = LibraryExport.document(
            carried, appVersion: "10.14.0", writtenAt: Date(timeIntervalSince1970: 1_767_225_845)
        )
        let model = LibraryImportModel()
        let file = try TransferDevice.file(holding: try LibraryDocumentCoder.encode(document))
        await model.load(file, with: device.transfer)

        await model.confirm(transfer: device.transfer, skippingSecrets: true) { _ in }

        guard case let .done(outcome) = model.phase else {
            Issue.record("expected done, got \(model.phase)")
            return
        }
        let conflict = try #require(outcome.conflicts.first)
        #expect(outcome.conflicts.count == 1)
        let keys = lookups(in: sheet(model, device))
        #expect(keys.contains("transfer.done.conflict.one %@ %@"), "the screen looked up \(keys.sorted())")
        #expect(ConflictWords.kept(conflict) != ConflictWords.setAside(conflict))
    }

    @Test("A position is worded as a page where the count is known and a percentage otherwise")
    func positionWords() {
        // The numbers, not the language: the sentence around them is the catalogue's.
        let page = ConflictWords.label(.page(index: 11, of: 40))
        #expect(page.contains("12") && page.contains("40"))
        let percent = ConflictWords.label(.reflowable(progression: 0.375, locator: "{}"))
        #expect(percent.contains("38") && !percent.contains("40"))
    }

    /// Task 26.7: the words took the device language, not the one chosen in the app.
    @Test("A position reads in French on an English device")
    func positionWordsFollowTheChosenLanguage() {
        #expect(ConflictWords.label(.page(index: 11, of: 40)) == "Page 12 of 40")
        InterfaceLanguage.$scoped.withValue("fr") {
            #expect(ConflictWords.label(.page(index: 11, of: 40)) == "Page 12 sur 40")
        }
    }
}
