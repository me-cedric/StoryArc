import AppKit
import QuartzCore
import Testing

@testable import StoryArc

/// The budget library of tasks 5.9 and 5.10: `STORYARC_BUDGET=<count>` adds the folder of that
/// many publications `scripts/budget-library.py` made from the corpus to the app's library, so a
/// later launch with `-StoryArcBudgetProbe YES` times the cold launch over it; the walk also
/// scrolls the grid and resizes the window against the display's clock. `STORYARC_BUDGET=remove`
/// forgets the folders again. Off otherwise: it changes the app's own library.
/// `docs/delivery/desktop-budgets-macos.md` holds the numbers.
extension WindowWalks {
    @MainActor
    @Suite("Budget walk", .enabled(if: BudgetRequest.value != nil, "set TEST_RUNNER_STORYARC_BUDGET to measure"))
    struct BudgetWalkTests {
        @Test("The library of the asked size: laid down, scanned, scrolled and resized")
        func budget() async throws {
            let library = try await Walk.library()
            if BudgetRequest.value == "remove" { return Self.remove(from: library) }
            let count = try #require(BudgetRequest.value.flatMap(Int.init))
            let folder = try Self.layDown(count)
            // One budget folder at a time: the other size, or an earlier try, is forgotten first.
            for source in library.sources where source.url?.lastPathComponent.hasPrefix("budget-") == true
                && source.url?.lastPathComponent != folder.lastPathComponent {
                library.removeFolder(source)
            }
            let clock = ContinuousClock()
            let start = clock.now
            if !library.sources.contains(where: { $0.url?.standardizedFileURL == folder.standardizedFileURL }) {
                library.addFolder(folder)
            }
            let marker = "/\(folder.lastPathComponent)/"
            let held = await Walk.until(.seconds(BudgetRequest.wait)) {
                let mine = library.model.publications.count { $0.identity.normalizedPath?.contains(marker) == true }
                return mine >= count ? true : nil
            }
            if held != true {
                let paths = library.model.publications.prefix(3).map { $0.identity.normalizedPath ?? "-" }
                print("budget: \(library.model.publications.count) publications, scan \(library.model.scanState), "
                    + "sources \(library.sources.map(\.name)), refused \(library.refused.map(\.name)), sample \(paths)")
            }
            #expect(held == true, "the scan did not hold \(count) publications")
            let scanned = clock.now - start
            ConformanceLog.note("budget scan", "\(count) publications in \(scanned)", wave: 5)

            let window = try #require(NSApplication.shared.windows.first {
                $0.isVisible && $0.identifier?.rawValue.hasPrefix(LibraryWindow.id) == true
            })
            library.navigationRequest = .go(.library)
            await Walk.activate(window)
            await Walk.settle()
            let scroll = try #require(Self.largestScrollView(in: window.contentView), "no scroll view in the library")
            let scrolled = await FrameDriver.run(seconds: 3, on: window) { tick in
                let clip = scroll.contentView
                let room = (scroll.documentView?.frame.height ?? 0) - clip.bounds.height
                clip.setBoundsOrigin(NSPoint(x: 0, y: min(room, Double(tick) * 60)))
                scroll.reflectScrolledClipView(clip)
            }
            let shelf = library.model.publications.count
            ConformanceLog.note("budget scroll", "\(shelf) on the shelf; \(scrolled)", wave: 5)
            let frame = window.frame
            let resized = await FrameDriver.run(seconds: 2, on: window) { tick in
                let width = 900 + 500 * abs(sin(Double(tick) / 30))
                window.setFrame(NSRect(x: frame.minX, y: frame.minY, width: width, height: frame.height), display: true)
            }
            window.setFrame(frame, display: true)
            ConformanceLog.note("budget resize", "\(shelf) on the shelf; \(resized)", wave: 5)
        }

        /// `tmp/budget-library-<count>` in the container, which `scripts/budget-library.py` writes.
        private static func layDown(_ count: Int) throws -> URL {
            let folder = URL.temporaryDirectory.appending(path: "budget-library-\(count)", directoryHint: .isDirectory)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            let script = "python3 -I apps/desktop-macos/scripts/budget-library.py \(count)"
            try #require(files.count >= count, "run \(script) first")
            return folder
        }

        /// Forgets the budget folders. Their files stay: deleting them is the owner's step.
        private static func remove(from library: MacLibrary) {
            for source in library.sources where source.url?.lastPathComponent.hasPrefix("budget-") == true {
                library.removeFolder(source)
            }
        }

        private static func largestScrollView(in view: NSView?) -> NSScrollView? {
            guard let view else { return nil }
            let found = ([view as? NSScrollView].compactMap(\.self) + view.subviews.compactMap(largestScrollView))
            return found.max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
        }
    }
}

enum BudgetRequest {
    static var value: String? { ProcessInfo.processInfo.environment["STORYARC_BUDGET"] }
    /// How long the scan may take, in seconds: `STORYARC_BUDGET_WAIT`, ten minutes by default.
    static var wait: Int { ProcessInfo.processInfo.environment["STORYARC_BUDGET_WAIT"].flatMap(Int.init) ?? 600 }
}

/// Moves something once a display refresh and times the refreshes the main thread answered.
///
/// A `CADisplayLink` on the window's screen calls back on the main run loop. A step that keeps
/// the main thread past the next refresh (SwiftUI laying out cells, decoding covers) delays the
/// next callback, so the gaps between callbacks are the frame times a reader sees.
@MainActor
final class FrameDriver: NSObject {
    private var stamps: [CFTimeInterval] = []
    private var step: (Int) -> Void = { _ in }
    private var link: CADisplayLink?

    static func run(seconds: Double, on window: NSWindow, _ step: @escaping (Int) -> Void) async -> String {
        let driver = FrameDriver()
        driver.step = step
        driver.link = window.screen?.displayLink(target: driver, selector: #selector(tick(_:)))
        driver.link?.add(to: .main, forMode: .common)
        try? await Task.sleep(for: .seconds(seconds))
        driver.link?.invalidate()
        let hertz = window.screen?.maximumFramesPerSecond ?? 60
        return Self.summary(zip(driver.stamps.dropFirst(), driver.stamps).map { $0 - $1 }, hertz: hertz)
    }

    @objc private func tick(_ link: CADisplayLink) {
        stamps.append(link.timestamp)
        step(stamps.count)
    }

    static func summary(_ times: [Double], hertz: Int) -> String {
        let sorted = times.sorted()
        guard !sorted.isEmpty else { return "no frames" }
        let interval = 1.0 / Double(hertz)
        let missed = sorted.map { max(0, Int(($0 / interval).rounded()) - 1) }.reduce(0, +)
        let total = sorted.reduce(0, +)
        return String(
            format: "%d frames in %.2f s, %.0f fps, median %.1f ms, 95th %.1f ms, worst %.1f ms, "
                + "%d refreshes missed at %d Hz",
            sorted.count, total, Double(sorted.count) / total, sorted[sorted.count / 2] * 1000,
            sorted[sorted.count * 95 / 100] * 1000, sorted[sorted.count - 1] * 1000, missed, hertz
        )
    }
}
