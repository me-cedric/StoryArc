import Foundation
import Testing

@testable import Persistence
@testable import SettingsFeature
import StoryArcCore

/// `library-portability` tasks 2.4, 2.5 and 5.3: the export sheet, and what it hands the picker.
/// Android's `LibraryExportSheetTest` asserts the same rows.
@MainActor
@Suite("The export sheet says what a file is not, and seals only when asked")
struct LibraryExportSheetTests {

    private func sheet(_ model: LibraryExportModel, _ device: TransferDevice) -> LibraryExportSheet {
        LibraryExportSheet(model: model, transfer: device.transfer) {}
    }

    // MARK: What the sheet says

    @Test("The sheet says what the file is not: no publication files, no downloads, no cover cache")
    func theSheetSaysWhatTheFileIsNot() throws {
        let keys = lookups(in: sheet(LibraryExportModel(), try TransferDevice()))

        #expect(keys.contains("transfer.export.notWhat"), "the sheet looked up \(keys.sorted())")
        #expect(keys.contains("transfer.export.carries"))
        #expect(keys.contains("transfer.export.readable"))
    }

    @Test("The warning sits beside the switch before the reader turns it on")
    func theWarningIsAlwaysThere() throws {
        let off = lookups(in: sheet(LibraryExportModel(), try TransferDevice()))

        #expect(off.contains("transfer.export.passwords"))
        #expect(off.contains("transfer.export.passwords.warning"))
    }

    @Test("The passphrase is asked for twice only when the switch is on")
    func thePassphraseFieldsFollowTheSwitch() throws {
        let device = try TransferDevice()
        let model = LibraryExportModel()
        let off = lookups(in: sheet(model, device))
        model.includesPasswords = true
        let on = lookups(in: sheet(model, device))

        #expect(!off.contains("transfer.passphrase"))
        #expect(!off.contains("transfer.passphrase.again"))
        #expect(on.contains("transfer.passphrase"))
        #expect(on.contains("transfer.passphrase.again"))
        #expect(on.contains("transfer.export.passphrase.note"))
    }

    @Test("A mismatch and an empty value are each stated")
    func theProblemIsStated() throws {
        let device = try TransferDevice()
        let model = LibraryExportModel()
        model.includesPasswords = true
        #expect(lookups(in: sheet(model, device)).contains("transfer.export.problem.empty"))

        model.passphrase = "abc"
        model.confirmation = "abd"
        let keys = lookups(in: sheet(model, device))

        #expect(keys.contains("transfer.export.problem.mismatch"))
        #expect(!keys.contains("transfer.export.problem.empty"))
    }

    // MARK: What it hands the picker

    @Test("The switch is off by default, and a reader who does nothing can export")
    func offByDefault() {
        let model = LibraryExportModel()

        #expect(!model.includesPasswords)
        #expect(model.problem == nil)
        #expect(model.canExport)
    }

    @Test("With the switch on, an empty or mismatched pair cannot export")
    func theSwitchOnNeedsAMatchingPair() async throws {
        let device = try TransferDevice()
        let model = LibraryExportModel()
        model.includesPasswords = true

        #expect(model.problem == .empty)
        #expect(!model.canExport)
        model.passphrase = "one"
        model.confirmation = "two"
        #expect(model.problem == .mismatch)
        await model.prepare(with: device.transfer, appVersion: "10.14.0")
        #expect(model.file == nil)

        model.confirmation = "one"
        #expect(model.problem == nil)
        #expect(model.canExport)
    }

    @Test("The bytes the picker receives decode back to the library, with no secrets object")
    func theBytesDecodeBack() async throws {
        let device = try await TransferDevice().holding()
        let model = LibraryExportModel()

        await model.prepare(with: device.transfer, appVersion: "10.14.0")
        let bytes = try #require(model.file?.wrapper().regularFileContents)
        let document = try LibraryDocumentCoder.decode(bytes)

        #expect(document.secrets == nil)
        #expect(document.library.sources.map(\.displayName) == ["Comics NAS", "Kavita"])
        #expect(document.library.collections.map(\.name) == ["Image Comics"])
        #expect(!(String(bytes: bytes, encoding: .utf8) ?? "").contains("nas-password"))
    }

    @Test("What the picker writes is one regular file holding exactly the prepared bytes")
    func thePickerWritesOneFile() async throws {
        let device = try await TransferDevice().holding()
        let model = LibraryExportModel()

        await model.prepare(with: device.transfer, appVersion: "10.14.0")

        let file = try #require(model.file)
        #expect(file.wrapper().isRegularFile)
        #expect(file.wrapper().regularFileContents == file.data)
        // Closing the picker, with or without a file, lets the bytes go.
        model.pickerClosed()
        #expect(model.file == nil)
    }

    @Test("With the switch on the bytes carry sealed secrets and none in clear")
    func theBytesSealWhenAsked() async throws {
        let device = try await TransferDevice().holding()
        let model = LibraryExportModel()
        model.includesPasswords = true
        model.passphrase = "a long phrase"
        model.confirmation = "a long phrase"

        await model.prepare(with: device.transfer, appVersion: "10.14.0")
        let bytes = try #require(model.file?.wrapper().regularFileContents)
        let text = String(bytes: bytes, encoding: .utf8) ?? ""
        let block = try #require(try LibraryDocumentCoder.decode(bytes).secrets)

        #expect(!text.contains("nas-password"))
        #expect(!text.contains("kavita-key"))
        #expect(!text.contains("a long phrase"))
        #expect(try LibrarySecretSealer.open(block, passphrase: "a long phrase").count == 2)
    }

    @Test("The passphrase leaves memory with the sheet")
    func thePassphraseIsLetGo() async throws {
        let model = LibraryExportModel()
        model.includesPasswords = true
        model.passphrase = "one"
        model.confirmation = "one"

        model.clearSecrets()

        #expect(model.passphrase.isEmpty)
        #expect(model.confirmation.isEmpty)
        #expect(model.file == nil)
    }

    @Test("A file the picker could not write is stated on the sheet, and a closed picker says nothing")
    func aFailedWriteIsStated() async throws {
        let device = try await TransferDevice().holding()
        let model = LibraryExportModel()
        await model.prepare(with: device.transfer, appVersion: "10.14.0")

        #expect(!model.pickerFinished(.failure(CocoaError(.userCancelled))))
        #expect(model.phase == .editing)
        #expect(model.file == nil)

        #expect(!model.pickerFinished(.failure(CocoaError(.fileWriteOutOfSpace))))
        #expect(model.phase == .failed)
        #expect(lookups(in: sheet(model, device)).contains("transfer.export.failed"))

        #expect(model.pickerFinished(.success(URL(fileURLWithPath: "/tmp/library.json"))))
    }

    @Test("The picker offers a dated name")
    func theDefaultName() {
        let date = Date(timeIntervalSince1970: 1_767_225_845)

        #expect(LibraryFileDocument.defaultName(on: date).hasPrefix("StoryArc library 20"))
    }
}
