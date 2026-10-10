// Draws the two Play graphics that are not screenshots: the 512 x 512 icon and one
// 1024 x 500 feature graphic per language. They go into fastlane's Play layout under
// `.build/store/play/<locale>/images/`, beside the screenshots, and are never committed.
//
// CoreGraphics and CoreText, because this machine has no image tooling, and
// `brand-mark.swift` already renders the app icon this way.
//
// The tagline is read from `docs/designs/store/android/listing/<lang>.md`, the file that
// is pasted into the Play Console, so it cannot disagree with the listing.
//
// Usage: swift scripts/store-graphic.swift        (run from the repository root)

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The listing languages and the folder name Play gives each one.
let locales = ["en": "en-US", "de": "de-DE", "es": "es-ES", "fr": "fr-FR"]

/// The mark's gradient stops, as `docs/designs/brand/storyarc-mark.svg` declares them.
let brandStops = ["#FF6B9D", "#F566B8", "#A855F7", "#5B4BF5"]
/// The plate of the supplied lockup, and the field the wash is drawn on.
let brandInk = "#10101A"

func colour(_ hex: String, alpha: CGFloat = 1) -> CGColor {
    var value: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
    return CGColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha
    )
}

enum Failure: Error, CustomStringConvertible {
    case cannotRead(String)
    case cannotDraw
    case cannotEncode
    case noTagline(String)
    case unknownLocale(String)

    var description: String {
        switch self {
        case let .cannotRead(path): return "cannot read \(path)"
        case .cannotDraw: return "CoreGraphics gave no bitmap context"
        case .cannotEncode: return "the bitmap could not be encoded as a PNG"
        case let .noTagline(path): return "\(path) has no `## Feature graphic tagline` with a fenced value"
        case let .unknownLocale(file): return "\(file): add its language to `locales` in store-graphic.swift"
        }
    }
}

func loadPNG(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw Failure.cannotRead(path) }
    return image
}

/// An opaque canvas: Play flattens a transparent icon onto a background it does not name.
func canvas(_ width: Int, _ height: Int) throws -> CGContext {
    guard let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { throw Failure.cannotDraw }
    return context
}

func encodePNG(_ context: CGContext) throws -> Data {
    guard let image = context.makeImage(),
          let out = CFDataCreateMutable(nil, 0),
          let sink = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
    else { throw Failure.cannotEncode }
    CGImageDestinationAddImage(sink, image, nil)
    guard CGImageDestinationFinalize(sink) else { throw Failure.cannotEncode }
    return out as Data
}

func systemFont(_ size: CGFloat) -> CTFont {
    CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
}

/// One line centred on `x`, shrunk until it fits `maxWidth`: German runs a third wider.
func drawCentredLine(_ context: CGContext, _ text: String, x: CGFloat, baseline: CGFloat, size: CGFloat, maxWidth: CGFloat, tint: CGColor) {
    var points = size
    func line() -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: systemFont(points),
            kCTForegroundColorAttributeName as NSAttributedString.Key: tint,
        ]))
    }
    var drawn = line()
    while CTLineGetTypographicBounds(drawn, nil, nil, nil) > maxWidth, points > 12 {
        points -= 1
        drawn = line()
    }
    let width = CTLineGetTypographicBounds(drawn, nil, nil, nil)
    context.textPosition = CGPoint(x: x - CGFloat(width) / 2, y: baseline)
    CTLineDraw(drawn, context)
}

/// Play's icon slot: 512 x 512, at most 1 MB, opaque.
func renderIcon(supplied: CGImage) throws -> Data {
    let context = try canvas(512, 512)
    context.setFillColor(colour(brandInk))
    context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
    context.draw(supplied, in: CGRect(x: 0, y: 0, width: 512, height: 512))
    return try encodePNG(context)
}

/// Play's feature graphic: 1024 x 500. Play crops it differently on different surfaces, so
/// the lockup and the tagline sit in the middle. No cover art: a graphic with somebody
/// else's covers appears to offer those comics.
func renderFeatureGraphic(lockup: CGImage, tagline: String) throws -> Data {
    let width: CGFloat = 1024
    let height: CGFloat = 500
    let context = try canvas(Int(width), Int(height))
    context.setFillColor(colour(brandInk))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let space = CGColorSpaceCreateDeviceRGB()
    let washColours = brandStops.reversed().map { colour($0, alpha: 0.30) } as CFArray
    if let wash = CGGradient(colorsSpace: space, colors: washColours, locations: [0, 0.4, 0.72, 1]) {
        context.drawLinearGradient(wash, start: .zero, end: CGPoint(x: width, y: height), options: [])
    }
    let glowColours = [colour("#A855F7", alpha: 0.42), colour("#A855F7", alpha: 0)] as CFArray
    if let glow = CGGradient(colorsSpace: space, colors: glowColours, locations: [0, 1]) {
        let centre = CGPoint(x: width / 2, y: height * 0.62)
        context.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: width * 0.42, options: [])
    }

    let lockupWidth = width * 0.52
    let lockupHeight = lockupWidth * CGFloat(lockup.height) / CGFloat(lockup.width)
    context.draw(lockup, in: CGRect(x: (width - lockupWidth) / 2, y: height - 108 - lockupHeight, width: lockupWidth, height: lockupHeight))
    drawCentredLine(context, tagline, x: width / 2, baseline: 118, size: 34, maxWidth: width * 0.78, tint: colour("#FFFFFF", alpha: 0.88))
    return try encodePNG(context)
}

/// The first fenced value under `## Feature graphic tagline`.
func tagline(in markdown: String, from path: String) throws -> String {
    guard let heading = markdown.range(of: "## Feature graphic tagline") else { throw Failure.noTagline(path) }
    let rest = markdown[heading.upperBound...]
    guard let open = rest.range(of: "```"), let close = rest[open.upperBound...].range(of: "```") else {
        throw Failure.noTagline(path)
    }
    let value = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { throw Failure.noTagline(path) }
    return value
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let listing = root.appending(path: "docs/designs/store/android/listing")
let out = root.appending(path: ".build/store/play")

do {
    let icon = try renderIcon(supplied: try loadPNG(root.appending(path: "docs/designs/brand/supplied/app-icons/android-playstore-512.png").path))
    let lockup = try loadPNG(root.appending(path: "docs/designs/brand/supplied/lockups/storyarc-lockup-dark.png").path)
    let files = try FileManager.default.contentsOfDirectory(atPath: listing.path).filter { $0.hasSuffix(".md") }.sorted()
    if files.isEmpty { throw Failure.cannotRead(listing.path) }
    for file in files {
        guard let store = locales[String(file.dropLast(3))] else { throw Failure.unknownLocale(file) }
        let path = listing.appending(path: file).path
        let feature = try renderFeatureGraphic(lockup: lockup, tagline: try tagline(in: String(contentsOfFile: path, encoding: .utf8), from: path))
        let images = out.appending(path: "\(store)/images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try feature.write(to: images.appending(path: "featureGraphic.png"))
        try icon.write(to: images.appending(path: "icon.png"))
        print("  \(store)/images: featureGraphic.png \(feature.count) bytes, icon.png \(icon.count) bytes")
    }
    print("store graphics: \(files.count) language(s) under \(out.path)")
} catch {
    FileHandle.standardError.write(Data("store graphic: \(error)\n".utf8))
    exit(1)
}
