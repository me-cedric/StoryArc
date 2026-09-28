import Foundation
import Testing
import UIKit

import StoryArcCore
@testable import EpubReaderFeature

@MainActor
@Suite("Brightness states the value that is in force")
struct BrightnessValueTests {

    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(
                atPath: candidate.appending(path: "manifest.json").path
            ) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    private func model() -> EpubReaderModel {
        let url = Self.corpus.appending(path: "ebooks/fixture.epub")
        return EpubReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: url.path),
                format: .epub,
                displayTitle: "fixture.epub",
                origin: .embedded
            ),
            url: url,
            preferences: nil
        )
    }

    @Test("Once the reader has moved the slider, the stated value is exactly what they set")
    func statesTheReadersOwnChoice() {
        let reader = model()
        reader.brightness = 0.75

        #expect(
            ThemeAxesSheet.brightnessInForce(reader) == 0.75,
            """
            The stated value ignored the reader's own choice. Before this, the label read \
            `model.brightness ?? 0.5`, so it said 50% even after the reader had set 75%.
            """
        )
    }

    @Test(
        "Before the reader has moved the slider, the stated value is the device's own",
        arguments: [0.1, 0.37, 0.9]
    )
    func statesTheDeviceLevelUntilTouched(deviceLevel: Double) {
        let reader = model()
        #expect(reader.brightness == nil, "no move yet")

        #expect(
            ThemeAxesSheet.brightnessInForce(reader, device: deviceLevel) == deviceLevel,
            """
            The stated value ignored the device's own level and fell back to a hardcoded \
            constant instead. The thumb has always read the device's level \
            (`ThemeAxisSliders.swift`'s slider `get:`); the label read a hardcoded 0.5, so the \
            two disagreed on every device whose brightness was not exactly 50%. Tested at \
            three device levels, none of them 50%, so a reintroduced `?? 0.5` cannot pass by \
            coincidence of the simulator's own brightness.
            """
        )
    }

    @Test("The real device is the default, so production code asks for nothing special")
    func theRealScreenIsTheDefault() {
        let reader = model()

        #expect(
            ThemeAxesSheet.brightnessInForce(reader) == Double(UIScreen.main.brightness),
            """
            Omitting `device:` must still read the real screen, which is what every call site \
            in `ThemeAxisSliders.swift` does.
            """
        )
    }
}
