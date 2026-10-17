import AppKit
import Testing

/// Whether the snapshot references are to be written again rather than compared.
enum SnapshotRecord {
    static var isSet: Bool { ProcessInfo.processInfo.environment["STORYARC_SNAPSHOT_RECORD"] != nil }

    /// The major macOS version the references were drawn on, from `__Snapshots__/macos-version.txt`.
    static var referenceMajor: Int? {
        let file = MacSnapshot.referencesFolder.appending(path: "macos-version.txt")
        return (try? String(contentsOf: file, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static var runningMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

    /// Compared only on the macOS the references were drawn on: another version draws its own
    /// fonts and controls, so a comparison there says nothing about the change under test.
    static var canCompare: Bool { isSet || referenceMajor == runningMajor }
}

/// A window's drawing held against a reference image.
///
/// `native-experience`, *Snapshot tests hold the screen states*. The tests run inside the
/// sandboxed app, which can read its test bundle and write its container and nothing in the
/// checkout, so the references travel as a bundle resource: `Tests/__Snapshots__/` is
/// copied into the bundle by `project.yml`. A run that finds no reference, or one asked to
/// record with `TEST_RUNNER_STORYARC_SNAPSHOT_RECORD=1`, writes the image to the container's
/// `tmp/snapshots/record/` and fails; a run that finds a different image writes it to
/// `tmp/snapshots/failures/` beside the reference it was held against, and fails. Copying
/// the recorded images into `Tests/__Snapshots__/` makes them the references; a recording
/// also writes `macos-version.txt`, the major version they were drawn on, which is copied
/// with them. On any other major version the screen suite is skipped and says why.
///
/// The window is drawn in-process from its view tree at one pixel per point, so the image
/// does not depend on the display's scale. Materials are composited by the window server
/// and are absent: a snapshot holds layout, words, colours and states, and the capture
/// suite's frames hold the glass.
@MainActor
enum MacSnapshot {
    /// A pixel differs when a channel moves by more than this, out of 255.
    static let channelTolerance = 24
    /// The share of pixels that may differ, for a text caret or a blink caught mid-way.
    static let pixelTolerance = 0.0005

    static var container: URL {
        URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory).appending(path: "tmp/snapshots")
    }

    nonisolated static var referencesFolder: URL {
        TestFixtures.bundle.bundleURL.appending(path: "Contents/Resources/__Snapshots__", directoryHint: .isDirectory)
    }

    /// How many times a screen is drawn again, half a second apart, before a difference counts:
    /// a control still running its own animation (a segment's highlight sliding in) settles.
    /// Each retry marks the whole window for drawing first: the toolbar's segmented control was
    /// seen to keep a highlight drawn for the other appearance until something asked it again
    /// (wave 3, one screen in about one run of three).
    static let attempts = 6

    /// Holds `window` against the reference named `name`, recording an issue when it differs.
    static func assert(
        _ window: NSWindow, named name: String, sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        guard var image = draw(window) else {
            Issue.record("\(name): the window could not be drawn", sourceLocation: sourceLocation)
            return
        }
        let reference = referencesFolder.appending(path: "\(name).png")
        guard !SnapshotRecord.isSet,
              let source = CGImageSourceCreateWithURL(reference as CFURL, nil),
              let stored = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            let written = write(png(image), to: "record", name: name)
            let reason = SnapshotRecord.isSet ? "recorded" : "no reference"
            Issue.record("\(name): \(reason); the image is at \(written)", sourceLocation: sourceLocation)
            return
        }
        var difference = difference(image, stored)
        for _ in 1..<attempts where difference > pixelTolerance {
            try? await Task.sleep(for: .milliseconds(500))
            invalidate(window.contentView?.superview ?? window.contentView)
            guard let again = draw(window) else { break }
            image = again
            difference = self.difference(image, stored)
        }
        if difference > pixelTolerance {
            let written = write(png(image), to: "failures", name: name)
            let share = String(format: "%.3f%%", difference * 100)
            Issue.record("\(name): \(share) of pixels differ from the reference; the image is at \(written)",
                         sourceLocation: sourceLocation)
        }
    }

    /// Marks a view and everything under it for drawing again.
    private static func invalidate(_ view: NSView?) {
        guard let view else { return }
        view.needsDisplay = true
        view.layer?.setNeedsDisplay()
        for child in view.subviews { invalidate(child) }
    }

    /// The window's view tree, title bar and toolbar included, at one pixel per point.
    static func draw(_ window: NSWindow) -> CGImage? {
        window.displayIfNeeded()
        guard let view = window.contentView?.superview ?? window.contentView else { return nil }
        let bounds = view.bounds
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = bounds.size
        view.cacheDisplay(in: bounds, to: bitmap)
        return bitmap.cgImage
    }

    /// The share of pixels that differ by more than the channel tolerance; 1 when the sizes differ.
    static func difference(_ lhs: CGImage, _ rhs: CGImage) -> Double {
        guard lhs.width == rhs.width, lhs.height == rhs.height,
              let left = rgba(lhs), let right = rgba(rhs)
        else { return 1 }
        var differing = 0
        for pixel in stride(from: 0, to: left.count, by: 4) {
            let moved = (0..<4).contains { abs(Int(left[pixel + $0]) - Int(right[pixel + $0])) > channelTolerance }
            if moved { differing += 1 }
        }
        return Double(differing) / Double(lhs.width * lhs.height)
    }

    /// The image as 8-bit sRGB, so two images are compared in one colour space.
    private static func rgba(_ image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }

    private static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func write(_ png: Data?, to folder: String, name: String) -> String {
        guard let png else { return "nowhere (the image could not be encoded)" }
        let directory = container.appending(path: folder, directoryHint: .isDirectory)
        let file = directory.appending(path: "\(name).png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: file)
            try "\(SnapshotRecord.runningMajor)\n".write(
                to: directory.appending(path: "macos-version.txt"), atomically: true, encoding: .utf8
            )
        } catch {
            return "nowhere (\(error.localizedDescription))"
        }
        return file.path(percentEncoded: false)
    }
}
