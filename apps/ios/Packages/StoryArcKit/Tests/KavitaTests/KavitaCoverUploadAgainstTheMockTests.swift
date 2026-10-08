import Foundation
import Testing

@testable import Kavita

/// The app's own cover upload, driven against the real `scripts/kavita-server.mjs`.
///
/// Task 5.3 of `cover-for-every-publication`. The shape of `Upload/reading-list` came from
/// documentation, and `KavitaCoverUploadTests` answers its own requests, which proves this
/// code sends what it means to and nothing about what a server does with it. This spawns the
/// mock, sends a picture through ``KavitaClient/uploadReadingListCover(_:image:)``, and asks
/// the list's own cover route for it back. The mock decodes the base64 and refuses what a
/// real server would, so the bytes that come back are the bytes that were chosen.
///
/// It proves the client against the mock and nothing more. A real Kavita is the owner's
/// check, and the device checklist carries it. Android's
/// `KavitaCoverUploadAgainstTheMockTest` is the twin of this file.
///
/// The same mock answers the sizes task 7.8 reads: a list entry's `fileSize` and a chapter's
/// `files[].bytes`, so a whole-shelf download can state its size before it starts.
///
/// Fails, and does not skip, when `node` cannot start: a guard that quietly stops running is
/// the failure this repository has been bitten by before.
@Suite("The real Kavita mock, through the app's own client", .serialized)
struct KavitaCoverUploadAgainstTheMockTests {

    /// A 1 x 1 PNG: the mock reads the type from the first bytes and keeps the rest whole.
    private func picture() throws -> Data {
        try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        ))
    }

    /// A mock that is running, and what to clean up when a test is done with it.
    private struct RunningMock {
        let client: KavitaClient
        let process: Process
        let corpus: URL

        func stop() {
            process.terminate()
            try? FileManager.default.removeItem(at: corpus)
        }
    }

    private func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<12 {
            directory.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("scripts/kavita-server.mjs").path
            ) { return directory }
        }
        throw MockError.rootNotFound
    }

    private enum MockError: Error {
        case rootNotFound
        case noBanner
    }

    /// Runs the mock on a port of its own and answers a client for it, with the process to stop.
    private func startMock() throws -> RunningMock {
        let root = try repositoryRoot()
        let corpus = URL.temporaryDirectory.appending(path: "kavita-upload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: corpus, withIntermediateDirectories: true)
        try Data("not a real publication".utf8).write(to: corpus.appending(path: "Tidal Reach 01.cbz"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "node", root.appendingPathComponent("scripts/kavita-server.mjs").path, corpus.path,
            "--port", "0",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        var text = ""
        var port: String?
        let pattern = /kavita mock: http:\/\/localhost:(\d+)/
        while port == nil {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty {
                process.terminate()
                throw MockError.noBanner
            }
            text += String(bytes: chunk, encoding: .utf8) ?? ""
            port = text.firstMatch(of: pattern).map { String($0.output.1) }
        }
        let bound = try #require(port)
        let address = try #require(
            KavitaAddress.from(base: "http://localhost:\(bound)", apiKey: "storyarc-test-key")
        )
        return RunningMock(client: KavitaClient(address: address), process: process, corpus: corpus)
    }

    @Test("A chosen cover is served back byte for byte, and the list says it is locked")
    func coverRoundTrip() async throws {
        let mock = try startMock()
        defer { mock.stop() }
        let client = mock.client
        let picture = try picture()
        let before = try await client.readingLists().first { $0.id == 1 }
        #expect(before?.coverImageLocked == false, "The list was locked before anything was sent.")

        try await client.uploadReadingListCover(1, image: picture)

        #expect(try await client.readingListCover(1) == picture)
        let after = try await client.readingLists().first { $0.id == 1 }
        #expect(after?.coverImageLocked == true)
        #expect(after?.promoted == false, "The mock calls a list nobody promoted promoted.")
    }

    @Test("Bytes that are not a picture are refused and the earlier cover stays")
    func notAPictureIsRefused() async throws {
        let mock = try startMock()
        defer { mock.stop() }
        let client = mock.client
        let picture = try picture()
        try await client.uploadReadingListCover(1, image: picture)

        await #expect(throws: (any Error).self) {
            try await client.uploadReadingListCover(1, image: Data("plain text, not an image".utf8))
        }

        #expect(try await client.readingListCover(1) == picture)
    }

    @Test("A list entry and a chapter state the size of their file")
    func sizesAreStated() async throws {
        let mock = try startMock()
        defer { mock.stop() }
        let client = mock.client

        let entries = try await client.readingListItems(1)
        let first = try #require(entries.first)
        // The corpus file holds 22 bytes, which is what the mock must state for it.
        #expect(first.fileSize == 22)
        #expect(first.pagesTotal > 0 && first.volumeId > 0 && first.libraryId > 0)

        let chapters = try await client.volumes(ofSeries: first.seriesId).flatMap(\.chapters)
        #expect(!chapters.isEmpty)
        #expect(chapters.allSatisfy { $0.fileBytes == 22 })
    }
}
