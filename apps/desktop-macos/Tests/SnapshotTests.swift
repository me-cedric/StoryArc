import AppKit
import Testing

@testable import StoryArc

extension WindowWalks {
    /// `native-experience`, *Snapshot tests hold the screen states*: every screen of the Mac's
    /// catalogue over the fixture library, light and dark at the default text size and light
    /// at the largest, held against `Tests/__Snapshots__/<screen>.<light|dark|largest>.png`.
    ///
    /// The references are drawn with the system's fonts and controls on the major macOS version
    /// `__Snapshots__/macos-version.txt` names; on another one the screen test is skipped and
    /// says so, until they are recorded again on it.
    @MainActor
    @Suite("Snapshots")
    struct SnapshotTests {
        @Test(
            "Every catalogue screen matches its reference in light, dark and the largest text",
            .enabled(if: SnapshotRecord.canCompare, "the references were drawn on another major version of macOS"),
            .enabled(Comment(rawValue: AppActivation.refusal)) {
                await AppActivation.activate() || AppActivation.isRequired
            }
        )
        func catalogue() async throws {
            let (library, reading) = try await MacCatalogue.prepare()
            // The notice of what a scan could not open is drawn as its dismissed link, which is
            // where any earlier walk that dismissed it leaves it; the banner has no way back.
            library.model.dismissSkipped()
            defer {
                NSApplication.shared.appearance = nil
                MacSettings.shared.textSize = .default
            }
            for suffix in ["light", "dark", "largest"] {
                NSApplication.shared.appearance = NSAppearance(named: suffix == "dark" ? .darkAqua : .aqua)
                MacSettings.shared.textSize = suffix == "largest" ? .largest : .default
                try await MacCatalogue.walk(library: library, reading: reading) { screen, window in
                    await MacSnapshot.assert(window, named: "\(screen).\(suffix)")
                }
            }
            if !AppActivation.notHeld.isEmpty {
                print("snapshots not held, the app was not in front: \(AppActivation.notHeld.joined(separator: ", "))")
            }
        }

        @Test("The fixture comics are laid down on fixed dates, a day apart in name order, every time")
        func fixtureDates() throws {
            let folder = URL.temporaryDirectory
                .appending(path: "dates-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: folder) }
            // Twice: the second lays the folder down over the first, as a run does over the last.
            try TestFixtures.layDownComics(at: folder)
            try TestFixtures.layDownComics(at: folder)
            let names = try FileManager.default
                .contentsOfDirectory(atPath: folder.path(percentEncoded: false))
                .sorted()
            #expect(names.count > 20)
            for (index, name) in names.enumerated() {
                let values = try folder.appending(path: name).resourceValues(
                    forKeys: [.addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey]
                )
                let expected = TestFixtures.arrival(at: index)
                #expect(values.addedToDirectoryDate == expected, "\(name) was added on \(String(describing: values))")
                #expect(values.creationDate == expected, "\(name)")
                #expect(values.contentModificationDate == expected, "\(name)")
            }
        }

        @Test("A changed image is caught and an identical one passes")
        func comparison() throws {
            let plain = try #require(Self.image(changing: 0))
            let small = try #require(Self.image(changing: 2))
            let large = try #require(Self.image(changing: 400))
            #expect(MacSnapshot.difference(plain, plain) == 0)
            #expect(MacSnapshot.difference(plain, small) <= MacSnapshot.pixelTolerance)
            #expect(MacSnapshot.difference(plain, large) > MacSnapshot.pixelTolerance)
        }

        /// A 100 by 100 white image with its first `count` pixels black.
        private static func image(changing count: Int) -> CGImage? {
            var bytes = [UInt8](repeating: 255, count: 100 * 100 * 4)
            for pixel in 0..<count { bytes.replaceSubrange(pixel * 4..<pixel * 4 + 3, with: [0, 0, 0]) }
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let provider = CGDataProvider(data: Data(bytes) as CFData)
            else { return nil }
            return CGImage(
                width: 100, height: 100, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 400, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent
            )
        }
    }
}
