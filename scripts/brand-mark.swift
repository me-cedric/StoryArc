// The StoryArc mark, authored once and emitted three ways.
//
// Run it:
//     swift scripts/brand-mark.swift --out <dir>          write every asset
//     swift scripts/brand-mark.swift --out <dir> --check  compare, write nothing
//
// **Why this file exists at all.** The brand artwork arrived as raster crops from a larger
// composite: the "transparent" icon carries a white plate with a speckled crop edge, the mark
// sits off-centre in its own canvas, gloss and bevels are baked into every petal, and two
// renders of the same idea disagree about where the gradient ends. They are a design, not an
// asset. See `docs/designs/brand/source/README.md`.
//
// The mark is describable — six tiles on a grid, each a rectangle with one corner cut by an
// arc, the lower-left one carrying a bookmark notch — so it is described here and generated,
// rather than traced. That is also what lets one definition feed the iOS rasters, the Android
// vector drawable and the docs' SVG: three hand-maintained copies of one shape is three
// chances to drift.
//
// **Why Swift and CoreGraphics.** There is no rasteriser on this machine — no ImageMagick, no
// `rsvg-convert`, no Pillow — and the mark needs real anti-aliasing and a real linear
// gradient. CoreGraphics has both and ships with the OS this repository already builds Swift
// against. Two runs produce byte-identical PNGs, which is the property that matters when the
// output is committed and gated.
//
// macOS-only for *writing*, and that is the trade the audio fixtures already make: the output
// is committed, so nothing that reads it needs the tool, and `--check` compares committed
// bytes rather than re-rendering.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry

/// Which corner of a tile the arc cuts away.
///
/// The arc's centre is the *opposite* corner, so a tile with `.topLeading` cut has straight
/// edges along its trailing and bottom sides and a curve sweeping toward the top-left. The
/// arrangement of these six choices is the whole reason the grid reads as an `S`.
enum Cut {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

/// One tile of the mark, in a y-down unit space where the mark's box is 0…1 on both axes.
///
/// A rectangle rather than a square: the mark is 4:5, and forcing square tiles would either
/// leave gutters or distort the grid. The arc is elliptical for the same reason — it spans a
/// fraction of the tile's own width and height, so it stays a *corner* rather than becoming a
/// circle inscribed in a non-square box.
struct Tile {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var cut: Cut
    /// A ribbon notch cut up from the bottom edge, as a fraction of a row. The bookmark.
    var notch: Double = 0
    /// The height the arc is measured against.
    ///
    /// The shared row height, not `height`. The bookmark's tile is taller because its tail
    /// hangs below the grid, and scaling its arc off its own height gave it a visibly bigger
    /// curve than its five neighbours — the tiles stopped looking like one set.
    var arcHeight: Double = 0
}

/// The mark.
///
/// Proportions measured from the supplied artwork on 2026-09-01: the mark occupies 528×660 of
/// a 1024 canvas, so **4:5**, and the gap between tiles is about 3.5% of its width. The
/// bookmark tile is measurably taller than the other five — 230 against ~185 — because its
/// tail hangs below the grid, and that is a design feature rather than render noise, so it is
/// kept.
///
/// The radius is a fraction of the tile rather than a length, so it survives any output size.
/// The supplied renders imply somewhere between 0.6 and a full quarter-arc; their own fill
/// ratios scatter from 0.67 to 0.83 for tiles that should be congruent, so the value here was
/// chosen by rendering and comparing rather than by fitting a curve to noise.
struct Mark {
    static let aspect = 4.0 / 5.0
    static let gap = 0.026
    /// How much of a tile the arc eats, per axis.
    ///
    /// Measured against the supplied renders by eye rather than by formula, because their own
    /// fill ratios scatter from 0.67 to 0.83 for tiles that should be congruent. At 0.62 the
    /// tiles read as rectangles with a chamfer; at 0.78 they read as the leaves the artwork
    /// draws.
    static let radius = 0.78
    /// How far the bookmark's tail hangs below its row, as a fraction of a row.
    static let tail = 0.28
    /// How deep the bookmark's notch cuts, as a fraction of the bookmark tile's height.
    static let notch = 0.30

    static var tiles: [Tile] {
        let columnWidth = (1.0 - gap) / 2
        // Three rows in the unit height, and the bottom row is `tail` taller than the others
        // so the bookmark hangs. Solving for the shared row height:
        //   3h + 2·gap + tail·h = 1
        let rowHeight = (1.0 - 2 * gap) / (3 + tail)
        let bottomHeight = rowHeight * (1 + tail)

        let left = 0.0
        let right = columnWidth + gap
        let row0 = 0.0
        let row1 = rowHeight + gap
        let row2 = 2 * (rowHeight + gap)

        return [
            // Top row: the arc sweeps out of the top-left, then out of the bottom-right —
            // which is what starts the S's upper bowl.
            Tile(x: left,  y: row0, width: columnWidth, height: rowHeight,
                 cut: .topLeading, arcHeight: rowHeight),
            Tile(x: right, y: row0, width: columnWidth, height: rowHeight,
                 cut: .bottomTrailing, arcHeight: rowHeight),
            // Middle row: the mirror of the top, which turns the bowl back.
            Tile(x: left,  y: row1, width: columnWidth, height: rowHeight,
                 cut: .bottomLeading, arcHeight: rowHeight),
            Tile(x: right, y: row1, width: columnWidth, height: rowHeight,
                 cut: .topTrailing, arcHeight: rowHeight),
            // Bottom row: the bookmark, and the tile that closes the lower bowl.
            Tile(x: left,  y: row2, width: columnWidth, height: bottomHeight,
                 cut: .topLeading, notch: notch, arcHeight: rowHeight),
            Tile(x: right, y: row2, width: columnWidth, height: rowHeight,
                 cut: .bottomTrailing, arcHeight: rowHeight),
        ]
    }
}

/// A tile's outline as a sequence of moves, in the same y-down unit space.
///
/// Emitted as an abstract list rather than straight into a `CGPath`, because the same outline
/// has to become an SVG `d` attribute and an Android `pathData` string, and three
/// hand-written copies of one outline is exactly what this file exists to avoid.
enum Segment {
    case move(Double, Double)
    case line(Double, Double)
    /// A cubic, because both SVG and Android's vector drawable take cubics and neither takes
    /// an ellipse arc in a form CoreGraphics also produces identically.
    case curve(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double)
    case close
}

/// The magic number that makes a cubic approximate a quarter ellipse.
///
/// 4/3·(√2 − 1). Standard, and worth naming rather than inlining: a reader who sees 0.5523
/// unexplained cannot tell it from a tweak somebody liked the look of.
let kappa = 4.0 / 3.0 * (sqrt(2.0) - 1.0)

func outline(_ tile: Tile) -> [Segment] {
    let x0 = tile.x, y0 = tile.y
    let x1 = tile.x + tile.width, y1 = tile.y + tile.height
    let rx = tile.width * Mark.radius
    let ry = (tile.arcHeight > 0 ? tile.arcHeight : tile.height) * Mark.radius

    // Walk the rectangle clockwise from the corner *after* the cut one, so the arc is always
    // the last thing drawn before closing. Each branch names its own corners rather than
    // sharing a rotated helper: four explicit paths are longer and are readable at a glance,
    // and this outline is the one thing in the file that must be right.
    var segments: [Segment] = []
    switch tile.cut {
    case .topLeading:
        segments = [
            .move(x0 + rx, y0),
            .line(x1, y0),
            .line(x1, y1),
            .line(x0, y1),
            .line(x0, y0 + ry),
            .curve(c1x: x0, c1y: y0 + ry - ry * kappa,
                   c2x: x0 + rx - rx * kappa, c2y: y0,
                   x: x0 + rx, y: y0),
        ]
    case .topTrailing:
        segments = [
            .move(x0, y0),
            .line(x1 - rx, y0),
            .curve(c1x: x1 - rx + rx * kappa, c1y: y0,
                   c2x: x1, c2y: y0 + ry - ry * kappa,
                   x: x1, y: y0 + ry),
            .line(x1, y1),
            .line(x0, y1),
        ]
    case .bottomLeading:
        segments = [
            .move(x0, y0),
            .line(x1, y0),
            .line(x1, y1),
            .line(x0 + rx, y1),
            .curve(c1x: x0 + rx - rx * kappa, c1y: y1,
                   c2x: x0, c2y: y1 - ry + ry * kappa,
                   x: x0, y: y1 - ry),
        ]
    case .bottomTrailing:
        segments = [
            .move(x0, y0),
            .line(x1, y0),
            .line(x1, y1 - ry),
            .curve(c1x: x1, c1y: y1 - ry + ry * kappa,
                   c2x: x1 - rx + rx * kappa, c2y: y1,
                   x: x1 - rx, y: y1),
            .line(x0, y1),
        ]
    }

    // The bookmark. The **whole** bottom edge becomes two diagonals meeting at a point — a
    // ribbon end, which is what the artwork draws and what a bookmark actually looks like.
    //
    // The first version cut a narrow slot with vertical walls instead, and it read as a flag
    // with a bite taken out of it. Replacing the edge rather than subtracting a second shape
    // keeps the tile one closed path and one fill.
    if tile.notch > 0 {
        let depth = (tile.arcHeight > 0 ? tile.arcHeight : tile.height) * tile.notch
        let mid = x0 + tile.width / 2
        if let index = segments.lastIndex(where: {
            if case let .line(lx, ly) = $0 { return ly == y1 && lx == x0 }
            return false
        }) {
            segments.replaceSubrange(index...index, with: [
                .line(mid, y1 - depth),
                .line(x0, y1),
            ])
        }
    }

    segments.append(.close)
    return segments
}

// MARK: - The palette

/// A colour as the tokens define it: sRGB, and named by the token it comes from.
struct Ink {
    let red: Double, green: Double, blue: Double
    let hex: String

    init(_ hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(s, radix: 16) ?? 0
        red = Double((v >> 16) & 0xFF) / 255
        green = Double((v >> 8) & 0xFF) / 255
        blue = Double(v & 0xFF) / 255
        self.hex = "#" + s.uppercased()
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

/// The brand arc, and the plates the faces are drawn on.
///
/// Every value here is a design token, and the hex is the one the token build generates —
/// this file does not invent a colour. `arcStart` and `arcEnd` are the two ends of the brand
/// gradient measured from the supplied artwork; the plates are existing surface tokens.
enum Palette {
    static let arcStart = Ink("#F662A0")   // brand.accent      oklch(70% 0.19 357)
    static let arcEnd = Ink("#7C4AED")     // brand.arcEnd      oklch(56% 0.23 291)
    static let accentStrong = Ink("#D94788")  // brand.accentStrong  oklch(62% 0.19 357)
    static let ink = Ink("#0F0D0B")        // dark.surfaceCanvas
    static let paper = Ink("#F8F6F4")      // light.surfaceCanvas
    static let bloom = Ink("#E7E3F5")      // a pale lavender plate, from the artwork's third variant
}

/// One face of the mark. Faces, not marks: a reader who picks any of them is still holding
/// StoryArc, which is the constraint that keeps this a chooser and not a costume box.
struct Face {
    let id: String
    let name: String
    let plate: Ink?
    /// A single-colour mark instead of the gradient. Android's themed-icon layer needs one,
    /// and a reader who wants it quiet gets the same art.
    let flat: Ink?

    static let all: [Face] = [
        Face(id: "ink", name: "Ink", plate: Palette.ink, flat: nil),
        Face(id: "paper", name: "Paper", plate: Palette.paper, flat: nil),
        Face(id: "bloom", name: "Bloom", plate: Palette.bloom, flat: nil),
        Face(id: "arc", name: "Arc", plate: Palette.arcEnd, flat: nil),
        Face(id: "mono", name: "Mono", plate: Palette.ink, flat: Palette.paper),
        // No plate at all: the mark alone, for the docs and for Android's foreground layer,
        // which is composited over its own background.
        Face(id: "bare", name: "Bare", plate: nil, flat: nil),
    ]
}

// MARK: - Rendering

/// Where the mark sits inside a square icon, as a fraction of the icon's side.
///
/// iOS and Android disagree about this and both are right. An iOS icon is drawn to its own
/// edge, so the mark is inset for optical balance. An Android adaptive icon's foreground is
/// masked to a shape the launcher chooses and only the middle 66/108 is guaranteed visible,
/// so its mark has to be smaller. One number per platform, named, rather than a magic inset
/// at each call site.
enum Inset {
    static let ios = 0.20
    static let android = 0.30
    static let bare = 0.06
}

func markRect(in side: Double, inset: Double) -> CGRect {
    let available = side * (1 - 2 * inset)
    // Fit the 4:5 box inside the available square, centred.
    let height = available
    let width = height * Mark.aspect
    return CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height)
}

/// The outline in output coordinates, y-down.
func placed(_ tile: Tile, in rect: CGRect) -> [Segment] {
    outline(tile).map { segment in
        func px(_ v: Double) -> Double { rect.minX + v * rect.width }
        func py(_ v: Double) -> Double { rect.minY + v * rect.height }
        switch segment {
        case let .move(x, y): return .move(px(x), py(y))
        case let .line(x, y): return .line(px(x), py(y))
        case let .curve(c1x, c1y, c2x, c2y, x, y):
            return .curve(c1x: px(c1x), c1y: py(c1y), c2x: px(c2x), c2y: py(c2y), x: px(x), y: py(y))
        case .close: return .close
        }
    }
}

func cgPath(_ segments: [Segment], flippingIn height: Double) -> CGPath {
    // CoreGraphics' bitmap context is y-up and the geometry is y-down, so every y is flipped
    // here rather than in the geometry — the SVG and the Android drawable both want y-down,
    // so the odd one out converts.
    let path = CGMutablePath()
    func y(_ v: Double) -> Double { height - v }
    for segment in segments {
        switch segment {
        case let .move(x, yy): path.move(to: CGPoint(x: x, y: y(yy)))
        case let .line(x, yy): path.addLine(to: CGPoint(x: x, y: y(yy)))
        case let .curve(c1x, c1y, c2x, c2y, x, yy):
            path.addCurve(to: CGPoint(x: x, y: y(yy)),
                          control1: CGPoint(x: c1x, y: y(c1y)),
                          control2: CGPoint(x: c2x, y: y(c2y)))
        case .close: path.closeSubpath()
        }
    }
    return path
}

func renderPNG(face: Face, side: Int, inset: Double) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("could not make a bitmap context") }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let s = Double(side)
    if let plate = face.plate {
        // Square, not rounded: both platforms apply their own mask, and a rounded plate baked
        // into the art shows as a double corner under iOS's squircle.
        ctx.setFillColor(plate.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    }

    let rect = markRect(in: s, inset: inset)
    let combined = CGMutablePath()
    for tile in Mark.tiles {
        combined.addPath(cgPath(placed(tile, in: rect), flippingIn: s))
    }

    ctx.saveGState()
    ctx.addPath(combined)
    ctx.clip()
    if let flat = face.flat {
        ctx.setFillColor(flat.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    } else {
        // The arc runs corner to corner across the mark's own box rather than the icon's, so
        // every face shows the same span of the gradient whatever its inset.
        let gradient = CGGradient(colorsSpace: space,
                                  colors: [Palette.arcStart.cgColor, Palette.arcEnd.cgColor] as CFArray,
                                  locations: [0, 1])!
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: rect.minX, y: s - rect.minY),
                               end: CGPoint(x: rect.maxX, y: s - rect.maxY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { fatalError("could not make an image") }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not make a PNG destination") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write the PNG") }
    return data as Data
}

// MARK: - Vector output

func number(_ v: Double) -> String {
    // Three decimals: enough for a 1024 px render to be sub-pixel, few enough that the files
    // are diffable and stable.
    let r = (v * 1000).rounded() / 1000
    return r == r.rounded() ? String(Int(r)) : String(format: "%g", r)
}

func pathData(_ segments: [Segment]) -> String {
    var out: [String] = []
    for segment in segments {
        switch segment {
        case let .move(x, y): out.append("M\(number(x)),\(number(y))")
        case let .line(x, y): out.append("L\(number(x)),\(number(y))")
        case let .curve(c1x, c1y, c2x, c2y, x, y):
            out.append("C\(number(c1x)),\(number(c1y)) \(number(c2x)),\(number(c2y)) \(number(x)),\(number(y))")
        case .close: out.append("Z")
        }
    }
    return out.joined(separator: " ")
}

func svg() -> String {
    // A 400×500 viewBox, so the mark's own 4:5 box is the whole document and a consumer can
    // place it without unpicking an inset.
    let rect = CGRect(x: 0, y: 0, width: 400, height: 500)
    let paths = Mark.tiles.map { pathData(placed($0, in: rect)) }
    var out = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 500" width="400" height="500" role="img" aria-label="StoryArc">
      <!-- Generated by scripts/brand-mark.swift. Do not edit: change the geometry there. -->
      <title>StoryArc</title>
      <defs>
        <linearGradient id="arc" x1="0" y1="0" x2="400" y2="500" gradientUnits="userSpaceOnUse">
          <stop offset="0" stop-color="\(Palette.arcStart.hex)"/>
          <stop offset="1" stop-color="\(Palette.arcEnd.hex)"/>
        </linearGradient>
      </defs>

    """
    for path in paths {
        out += "  <path fill=\"url(#arc)\" d=\"\(path)\"/>\n"
    }
    out += "</svg>\n"
    return out
}

func androidVector(flat: Bool) -> String {
    // 108dp viewport with the mark at the Android inset, which is what an adaptive icon's
    // foreground layer is measured in. A vector rather than a raster because that is what the
    // platform actually wants, and because a themed icon retints it.
    let side = 108.0
    let rect = markRect(in: side, inset: Inset.android)
    let paths = Mark.tiles.map { pathData(placed($0, in: rect)) }
    var out = """
    <?xml version="1.0" encoding="utf-8"?>
    <!-- Generated by scripts/brand-mark.swift. Do not edit: change the geometry there. -->
    <vector xmlns:android="http://schemas.android.com/apk/res/android"
        android:width="108dp"
        android:height="108dp"
        android:viewportWidth="108"
        android:viewportHeight="108">

    """
    for path in paths {
        if flat {
            out += "    <path android:fillColor=\"#FFFFFFFF\" android:pathData=\"\(path)\" />\n"
        } else {
            out += """
                <path android:pathData="\(path)">
                    <aapt:attr name="android:fillColor">
                        <gradient
                            android:startX="\(number(rect.minX))" android:startY="\(number(rect.minY))"
                            android:endX="\(number(rect.maxX))" android:endY="\(number(rect.maxY))"
                            android:type="linear">
                            <item android:offset="0" android:color="\(Palette.arcStart.hex)" />
                            <item android:offset="1" android:color="\(Palette.arcEnd.hex)" />
                        </gradient>
                    </aapt:attr>
                </path>

            """
        }
    }
    out += "</vector>\n"
    // The gradient form needs the aapt namespace on the root; the flat one does not.
    if !flat {
        out = out.replacingOccurrences(
            of: "<vector xmlns:android=\"http://schemas.android.com/apk/res/android\"",
            with: "<vector xmlns:android=\"http://schemas.android.com/apk/res/android\"\n    xmlns:aapt=\"http://schemas.android.com/aapt\""
        )
    }
    return out
}

// MARK: - Driver

let arguments = CommandLine.arguments
func flag(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: "--\(name)"), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}
let checking = arguments.contains("--check")
guard let outRoot = flag("out") else {
    FileHandle.standardError.write(Data("Usage: swift scripts/brand-mark.swift --out <dir> [--check]\n".utf8))
    exit(2)
}

/// An app-icon set holding one 1024 image, which is the only size a modern catalogue needs.
func appIconContents(_ file: String) -> String {
    """
    {
      "images" : [
        {
          "filename" : "\(file)",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        }
      ],
      "info" : { "author" : "storyarc-brand-mark", "version" : 1 }
    }

    """
}

/// The accent colour, as the asset catalogue wants it.
///
/// Generated rather than hand-edited because it is the *same* value as the token, and a hex
/// typed twice is a hex that will disagree once. Light takes `accentStrong`, which is the
/// token that exists precisely because the lighter accent fails on paper.
func accentColorContents() -> String {
    func entry(_ ink: Ink, dark: Bool) -> String {
        let hex = ink.hex.dropFirst()
        let r = hex.prefix(2), g = hex.dropFirst(2).prefix(2), b = hex.suffix(2)
        let appearance = dark
            ? "      \"appearances\" : [ { \"appearance\" : \"luminosity\", \"value\" : \"dark\" } ],\n"
            : ""
        return """
            {
        \(appearance)      "color" : {
                "color-space" : "srgb",
                "components" : { "alpha" : "1.000", "blue" : "0x\(b)", "green" : "0x\(g)", "red" : "0x\(r)" }
              },
              "idiom" : "universal"
            }
        """
    }
    return """
    {
      "colors" : [
    \(entry(Palette.accentStrong, dark: false)),
    \(entry(Palette.arcStart, dark: true))
      ],
      "info" : { "author" : "storyarc-brand-mark", "version" : 1 }
    }

    """
}

// Where each asset belongs, repo-relative. Final locations rather than a staging tree: a copy
// step between "generated" and "used" is a place for the two to drift, which is the whole
// thing this file exists to prevent.
let catalogue = "apps/ios/App/Resources/Assets.xcassets"
let androidRes = "apps/android/app/src/main/res"

var written: [(String, Data)] = []

// iOS: the primary set is `AppIcon`; the rest are siblings named for their face, which is
// what `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` refers to them by.
for face in Face.all where face.id != "bare" {
    let setName = face.id == "ink" ? "AppIcon" : "AppIcon-\(face.name)"
    let file = "\(setName)-1024.png"
    written.append(("\(catalogue)/\(setName).appiconset/\(file)",
                    renderPNG(face: face, side: 1024, inset: Inset.ios)))
    written.append(("\(catalogue)/\(setName).appiconset/Contents.json",
                    Data(appIconContents(file).utf8)))
}
written.append(("\(catalogue)/AccentColor.colorset/Contents.json",
                Data(accentColorContents().utf8)))

// Android: vectors, because that is what an adaptive icon's layers actually want, and
// because a themed icon retints the monochrome one.
written.append(("\(androidRes)/drawable/ic_launcher_foreground.xml",
                Data(androidVector(flat: false).utf8)))
written.append(("\(androidRes)/drawable/ic_launcher_monochrome.xml",
                Data(androidVector(flat: true).utf8)))

// The docs, and anything else that wants the mark without a plate.
written.append(("docs/designs/brand/storyarc-mark.svg", Data(svg().utf8)))
written.append(("docs/designs/brand/storyarc-mark-1024.png",
                renderPNG(face: Face.all.first { $0.id == "bare" }!, side: 1024, inset: Inset.bare)))

var stale: [String] = []
for (relative, data) in written {
    let url = URL(fileURLWithPath: outRoot).appending(path: relative)
    if checking {
        let existing = try? Data(contentsOf: url)
        if existing != data { stale.append(relative) }
    } else {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

if checking {
    if stale.isEmpty {
        print("brand mark: \(written.count) asset(s) current.")
    } else {
        FileHandle.standardError.write(Data((
            "brand mark is stale: \(stale.joined(separator: ", "))\n"
            + "Run `pnpm brand:build` and commit the result.\n").utf8))
        exit(1)
    }
} else {
    for (relative, data) in written {
        print(String(format: "  %7d  %@", data.count, relative))
    }
    print("brand mark: wrote \(written.count) asset(s).")
}
