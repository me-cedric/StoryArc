import AppKit
import StoryArcCore
import Testing

@testable import StoryArc

/// The curl's shader library in the built app, and the menu that offers it. Task 5.1.
@Suite("Curl on the Mac")
struct MacCurlTests {
    @Test("The app carries the compiled shader library, and it holds the phone's pageCurl")
    func shaderLibrary() throws {
        let bundle = try #require(MacCurlShader.bundle, "StoryArcKit_ReaderFeature.bundle is not in the app")
        let library = try #require(bundle.url(forResource: "default", withExtension: "metallib"))
        #expect(MacCurlShader.isPresent)
        #expect(try Data(contentsOf: library).range(of: Data("pageCurl".utf8)) != nil)
    }

    @Test("The transition menu offers Curl and says nothing is missing")
    func offered() {
        let choices = TransitionChoices(
            chosen: .pageCurl, axis: .horizontal, reduceMotion: false, canCurl: MacCurlShader.isPresent
        )
        let curl = TransitionMenu.rows(choices).first { $0.mode == .pageCurl }
        #expect(curl?.reasonKey == nil)
        #expect(TransitionMenu.absentCurlKey(choices) == nil)
        #expect(choices.effective == .pageCurl)
    }

    @Test("The sheet that turns is the page's own rectangle, centred in the window")
    func sheetIsThePage() throws {
        let page = try #require(CGContext(
            data: nil, width: 200, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage())
        let sheet = MacCurlLayer.fitted(page, in: CGSize(width: 1000, height: 600))
        #expect(sheet == CGRect(x: 300, y: 0, width: 400, height: 600))
    }
}

extension WindowWalks {
    /// The curl driven inside the app over a fixture comic: three key turns each run the
    /// phone's shader from a flat page to a turned one, the page moves one at a time, and the
    /// frame times of each settle are written for the record. Task 5.1.
    @MainActor
    @Suite("Curl walk")
    struct CurlWalkTests {
        @Test(
            "Each key turn in Curl is drawn by the shader, frame by frame, and lands one page on",
            // An Xcode without the Metal toolchain (the CI runner's 26.6) builds no shader library,
            // and then the curl is absent by design; the absence has its own tests.
            .enabled(if: MacCurlShader.isPresent, "this build carries no compiled shader library"),
            .enabled(if: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "Reduce Motion is on")
        )
        func keyTurnsCurl() async throws {
            let library = try await Walk.fixtureLibrary()
            let publication = try #require(Walk.publication(named: "natural-sort", in: library))
            let target = try #require(library.target(for: publication))
            try Walk.open(target)
            let window = try #require(await Walk.until { Walk.readerWindows(for: target).first })
            let state = try #require(await Walk.until { ReaderStates.shared.state(for: target) })
            _ = await Walk.until { state.model.pages.isEmpty ? nil : true }
            await Walk.activate(window)
            let chosen = state.model.settings.transition
            defer { state.choose(chosen) }
            state.spreadMode = .single
            state.go(to: 0)
            state.choose(.pageCurl)
            #expect(state.choices.effective == .pageCurl)
            MacCurlProbe.shared.reset()

            for turn in 1...3 {
                _ = await Walk.until { state.model.displayImage(at: turn) != nil ? true : nil }
                let before = state.curlRequest?.serial ?? 0
                Walk.press("\u{F703}", keyCode: KeyCode.rightArrow, in: window)
                if turn == 2, CaptureRequest.isSet { try await Self.captureMidTurn(window) }
                #expect(await Walk.until { (state.curlRequest?.serial ?? 0) > before ? true : nil } == true)
                #expect(await Walk.until { MacCurlProbe.shared.settles.count == turn ? true : nil } == true)
                #expect(await Walk.until { state.model.currentIndex == turn ? true : nil } == true)
            }
            let times = MacCurlProbe.shared.settles.flatMap(\.self).sorted()
            #expect(times.count > 10, "the curl drew \(times.count) frames in three turns")
            let median = times.isEmpty ? 0 : times[times.count / 2] * 1000
            let worst = (times.last ?? 0) * 1000
            let ninetyFifth = times.isEmpty ? 0 : times[times.count * 95 / 100] * 1000
            let hertz = window.screen?.maximumFramesPerSecond ?? 60
            let interval = 1.0 / Double(hertz)
            let missed = times.map { Int(($0 / interval).rounded()) - 1 }.reduce(0, +)
            ConformanceLog.note("curl frames", String(
                format: "%d frames in 3 settles of %.2f s, median %.1f ms, 95th %.1f ms, worst %.1f ms, "
                    + "%d refreshes missed, display %d Hz",
                times.count, CurlTurn.settleDuration, median, ninetyFifth, worst, missed, hertz
            ), wave: 5)
            await Walk.close([window])
        }

        /// The window half way through a settle, from the window server, for the wave 5 frames.
        private static func captureMidTurn(_ window: NSWindow) async throws {
            try await Task.sleep(for: .milliseconds(140))
            let image = try #require(WindowImage.fromWindowServer(window), "the window server gave no image")
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: try Walk.captureFolder("wave5").appending(path: "reader-curl-mid-turn.png"))
        }
    }
}
