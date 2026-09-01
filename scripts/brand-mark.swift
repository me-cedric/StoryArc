// The StoryArc mark: the designer's SVG, rendered everywhere it is needed.
//
// Run it:
//     swift scripts/brand-mark.swift --out <dir>          write every asset
//     swift scripts/brand-mark.swift --out <dir> --check  compare, write nothing
//
// **`docs/designs/brand/storyarc-mark.svg` is the source of truth**, and it is the file the
// designer supplied. This script parses it and renders it; it does not reconstruct it.
//
// An earlier version of this file *did* reconstruct the mark, from proportions measured out of
// raster crops, because the first artwork drop was raster only — a white plate with a speckled
// crop edge, the mark off-centre in its own canvas, gloss baked into every petal, and two
// renders that disagreed about where the gradient ended. Reconstructing was the right answer
// to that. It is the wrong answer to an SVG: the supplied paths carry 14-unit radii on the
// "square" corners and a different arc radius per tile — 137, 123, 114, 108 — and no
// reconstruction from a raster was going to recover those numbers.
//
// So the geometry is read, not authored. What this script still owns is everything the SVG
// cannot say by itself: which faces exist, what plate each sits on, how far the mark is inset
// for each platform's icon mask, and the fact that all of it must be byte-identical run to run
// so `--check` is a gate rather than a coin toss.
//
// **Why Swift and CoreGraphics.** There is no rasteriser on this machine — no ImageMagick, no
// `rsvg-convert`, no Pillow — and the mark needs real anti-aliasing and a real multi-stop
// gradient. CoreGraphics has both and ships with the OS this repository already builds Swift
// against. macOS-only for *writing*, which is the trade the audio fixtures already make: the
// output is committed, so nothing that reads it needs the tool.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Reading the SVG

struct Stop {
    let offset: Double
    let hex: String
}

/// Everything the generator needs out of the supplied file.
///
/// Deliberately not a general SVG parser. It understands exactly the document the designer
/// supplied — one `linearGradient` in `userSpaceOnUse`, six `path` elements — and it **fails
/// loudly** on anything else rather than rendering something plausible. A silent partial parse
/// produces an icon that looks nearly right, which is the worst outcome available.
struct Artwork {
    let viewBox: CGRect
    let gradientStart: CGPoint
    let gradientEnd: CGPoint
    let stops: [Stop]
    let paths: [String]

    init(svg text: String) throws {
        func attribute(_ name: String, in fragment: String) -> String? {
            guard let range = fragment.range(of: "\(name)=\"") else { return nil }
            let rest = fragment[range.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            return String(rest[..<end])
        }

        guard let box = attribute("viewBox", in: text) else { throw Failure.noViewBox }
        let numbers = box.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        guard numbers.count == 4 else { throw Failure.badViewBox(box) }
        viewBox = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])

        guard let open = text.range(of: "<linearGradient")?.upperBound,
              let close = text.range(of: "</linearGradient>")?.lowerBound
        else { throw Failure.noGradient }
        let gradientFragment = String(text[open..<close])

        guard attribute("gradientUnits", in: gradientFragment) == "userSpaceOnUse" else {
            throw Failure.gradientNotUserSpace
        }
        guard let x1 = attribute("x1", in: gradientFragment).flatMap(Double.init),
              let y1 = attribute("y1", in: gradientFragment).flatMap(Double.init),
              let x2 = attribute("x2", in: gradientFragment).flatMap(Double.init),
              let y2 = attribute("y2", in: gradientFragment).flatMap(Double.init)
        else { throw Failure.badGradientGeometry }
        gradientStart = CGPoint(x: x1, y: y1)
        gradientEnd = CGPoint(x: x2, y: y2)

        var found: [Stop] = []
        var cursor = gradientFragment.startIndex
        while let stopOpen = gradientFragment.range(
            of: "<stop", range: cursor..<gradientFragment.endIndex
        ) {
            let tail = gradientFragment[stopOpen.upperBound...]
            let stopClose = tail.firstIndex(of: ">") ?? tail.endIndex
            let fragment = String(tail[..<stopClose])
            guard let offset = attribute("offset", in: fragment).flatMap(Double.init),
                  let colour = attribute("stop-color", in: fragment)
            else { throw Failure.badStop(fragment) }
            found.append(Stop(offset: offset, hex: colour.uppercased()))
            cursor = stopClose
        }
        guard found.count >= 2 else { throw Failure.tooFewStops(found.count) }
        stops = found

        // Scanned as `<path` elements, not as bare ` d="` attributes.
        //
        // The first version looked for the attribute alone, and the mutation matrix caught what
        // that costs: renaming an element to `<pathX` leaves its `d` in the document, so six
        // paths were still found and a *dropped tile* passed the check. An attribute is only a
        // path if it is on a path.
        var d: [String] = []
        var pathCursor = text.startIndex
        while let element = text.range(of: "<path", range: pathCursor..<text.endIndex) {
            // `<pathological>` is not `<path`: the next character has to end the tag name.
            let after = element.upperBound
            if after < text.endIndex, text[after].isLetter || text[after].isNumber {
                pathCursor = after
                continue
            }
            let tail = text[after...]
            let elementEnd = tail.firstIndex(of: ">") ?? tail.endIndex
            let fragment = String(tail[..<elementEnd])
            guard let value = attribute("d", in: fragment) else { throw Failure.pathWithoutData }
            d.append(value)
            pathCursor = elementEnd
        }
        guard !d.isEmpty else { throw Failure.noPaths }
        paths = d
    }

    enum Failure: Error, CustomStringConvertible {
        case noViewBox, badViewBox(String), noGradient, gradientNotUserSpace
        case badGradientGeometry, badStop(String), tooFewStops(Int), noPaths
        case pathWithoutData

        var description: String {
            switch self {
            case .noViewBox: return "the SVG declares no viewBox"
            case let .badViewBox(v): return "the viewBox is not four numbers: \(v)"
            case .noGradient:
                return "the SVG declares no linearGradient — the mark's fill is the brand arc"
            case .gradientNotUserSpace:
                return "the gradient is not gradientUnits=\"userSpaceOnUse\", so its "
                     + "coordinates cannot be mapped into the output space"
            case .badGradientGeometry: return "the gradient is missing one of x1/y1/x2/y2"
            case let .badStop(f): return "a stop is missing offset or stop-color: \(f)"
            case let .tooFewStops(n): return "the gradient has \(n) stop(s)"
            case .noPaths: return "the SVG declares no paths"
            case .pathWithoutData: return "a <path> element carries no d attribute"
            }
        }
    }
}

// MARK: - SVG path data to CGPath

/// The subset of the path grammar the supplied artwork uses, and nothing more.
///
/// `M A H V L Z`, absolute and relative. An unrecognised command throws rather than being
/// skipped: a path that silently drops a segment closes across the shape and fills a wedge
/// that was never in the design, and that is not obvious in a thumbnail.
struct PathParser {
    private let scanner: [Character]
    private var index: Int = 0
    private var current = CGPoint.zero
    private var subpathStart = CGPoint.zero
    let path = CGMutablePath()

    enum Failure: Error, CustomStringConvertible {
        case unknownCommand(Character, Int)
        case missingNumber(Character, Int)
        var description: String {
            switch self {
            case let .unknownCommand(c, i): return "unsupported path command '\(c)' at offset \(i)"
            case let .missingNumber(c, i):
                return "command '\(c)' at offset \(i) is missing a number"
            }
        }
    }

    init(_ d: String) throws {
        scanner = Array(d)
        try run()
    }

    private mutating func skipSeparators() {
        while index < scanner.count,
              scanner[index] == " " || scanner[index] == "," || scanner[index] == "\n" {
            index += 1
        }
    }

    private mutating func number(_ command: Character) throws -> Double {
        skipSeparators()
        var text = ""
        if index < scanner.count, scanner[index] == "-" || scanner[index] == "+" {
            text.append(scanner[index]); index += 1
        }
        while index < scanner.count, scanner[index].isNumber || scanner[index] == "." {
            text.append(scanner[index]); index += 1
        }
        guard let value = Double(text) else { throw Failure.missingNumber(command, index) }
        return value
    }

    private mutating func run() throws {
        var command: Character = " "
        while true {
            skipSeparators()
            guard index < scanner.count else { break }
            if scanner[index].isLetter {
                command = scanner[index]
                index += 1
            }
            let relative = command.isLowercase
            switch Character(command.uppercased()) {
            case "M":
                let x = try number(command), y = try number(command)
                current = relative ? CGPoint(x: current.x + x, y: current.y + y)
                                   : CGPoint(x: x, y: y)
                subpathStart = current
                path.move(to: current)
                // A repeated coordinate pair after `M` is an implicit `L`, per the grammar.
                command = relative ? "l" : "L"
            case "L":
                let x = try number(command), y = try number(command)
                current = relative ? CGPoint(x: current.x + x, y: current.y + y)
                                   : CGPoint(x: x, y: y)
                path.addLine(to: current)
            case "H":
                let x = try number(command)
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            case "V":
                let y = try number(command)
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            case "A":
                let rx = try number(command), ry = try number(command)
                let rotation = try number(command)
                let largeArc = try number(command) != 0
                let sweep = try number(command) != 0
                let x = try number(command), y = try number(command)
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y)
                                   : CGPoint(x: x, y: y)
                addArc(from: current, to: end, rx: rx, ry: ry,
                       rotation: rotation, largeArc: largeArc, sweep: sweep)
                current = end
            case "Z":
                path.closeSubpath()
                current = subpathStart
            default:
                throw Failure.unknownCommand(command, index)
            }
        }
    }

    /// SVG's endpoint-parameterised arc, as cubics.
    ///
    /// The conversion in the SVG specification's implementation notes, appendix F.6: recover
    /// the ellipse centre from the two endpoints, then split the sweep into segments of at most
    /// 90 degrees and approximate each with one cubic. CoreGraphics has `addArc` but only for
    /// circles, and the supplied artwork's corners are circular *by coincidence* — writing this
    /// against the general case means a designer can put an ellipse in the file later and
    /// nothing here needs to change.
    private func addArc(from start: CGPoint, to end: CGPoint,
                        rx rxIn: Double, ry ryIn: Double,
                        rotation: Double, largeArc: Bool, sweep: Bool) {
        if start == end { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 {
            path.addLine(to: end)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        // The endpoints in the ellipse's own frame.
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // Scale the radii up if they are too small to span the endpoints. The specification
        // requires this rather than treating it as an error.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = lambda.squareRoot()
            rx *= scale
            ry *= scale
        }

        // The centre.
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coefficient = denominator == 0 ? 0 : (numerator / denominator).squareRoot()
        if largeArc == sweep { coefficient = -coefficient }
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        // The angles.
        let theta1 = atan2((y1p - cyp) / ry, (x1p - cxp) / rx)
        var delta = atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx) - theta1
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        // At most 90 degrees per cubic, where the approximation stays well under a thousandth
        // of the radius.
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / Double(segments)
        let alpha = 4.0 / 3.0 * tan(step / 4)
        var theta = theta1
        for _ in 0..<segments {
            let next = theta + step
            func point(_ t: Double) -> CGPoint {
                let x = rx * cos(t), y = ry * sin(t)
                return CGPoint(x: cosPhi * x - sinPhi * y + cx,
                               y: sinPhi * x + cosPhi * y + cy)
            }
            func derivative(_ t: Double) -> CGPoint {
                let x = -rx * sin(t), y = ry * cos(t)
                return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
            }
            let p1 = point(theta), p2 = point(next)
            let d1 = derivative(theta), d2 = derivative(next)
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + alpha * d1.x, y: p1.y + alpha * d1.y),
                          control2: CGPoint(x: p2.x - alpha * d2.x, y: p2.y - alpha * d2.y))
            theta = next
        }
    }
}

// MARK: - The palette

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

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

/// The plates the faces sit on, and the accent the asset catalogue needs.
///
/// Every value is a design token. **The arc's own colours are not here** — they come from the
/// SVG, because the SVG is the mark's source of truth and a second copy of four hex values is
/// a second copy that will disagree once.
enum Palette {
    /// The designer's own icon plate, sampled from `ios-appicon-1024.png`: a near-black
    /// tinted **toward the brand's violet** — `oklch(20.8% 0.016 285)` — rather than the app's
    /// warm `dark.surfaceCanvas` at hue 70. Deliberate on their part, and honoured: the icon
    /// is brand territory and a violet-tinted plate under a violet-ending arc is a choice, not
    /// a mismatch. It becomes `brand.iconPlate` so it is a token rather than a magic hex.
    static let ink = Ink("#17171F")          // brand.iconPlate  oklch(20.8% 0.016 285)
    static let paper = Ink("#F8F6F4")        // light.surfaceCanvas
    static let bloom = Ink("#E7E3F5")        // a pale lavender plate, from the artwork's variants
    static let arcPlate = Ink("#5B4BF5")     // brand.arcEnd — the loud face's plate
    static let accent = Ink("#FF6B9D")       // brand.accent       oklch(72.4% 0.185 2)
    static let accentStrong = Ink("#DA497D") // brand.accentStrong oklch(62% 0.185 2)
    static let monoMark = Ink("#F8F6F4")
}

/// One face of the mark. Faces, not marks: a reader who picks any of them is still holding
/// StoryArc, which is the constraint that keeps this a chooser and not a costume box.
struct Face {
    let id: String
    let name: String
    let plate: Ink?
    /// A single colour instead of the arc. Android's themed-icon layer needs one — it retints
    /// that layer, and a gradient tinted flat loses the mark's internal divisions.
    let flat: Ink?

    static let all: [Face] = [
        Face(id: "ink", name: "Ink", plate: Palette.ink, flat: nil),
        Face(id: "paper", name: "Paper", plate: Palette.paper, flat: nil),
        Face(id: "bloom", name: "Bloom", plate: Palette.bloom, flat: nil),
        Face(id: "arc", name: "Arc", plate: Palette.arcPlate, flat: nil),
        Face(id: "mono", name: "Mono", plate: Palette.ink, flat: Palette.monoMark),
        Face(id: "bare", name: "Bare", plate: nil, flat: nil),
    ]
}

// MARK: - Rendering

/// Where the mark sits inside a square icon, as a fraction of the side.
///
/// iOS and Android disagree and both are right. An iOS icon is drawn to its own edge, so the
/// mark is inset for optical balance. An Android adaptive icon's foreground is masked to a
/// shape the launcher chooses and only the middle 66/108 is guaranteed visible, so its mark
/// has to be smaller.
enum Inset {
    /// Measured off the designer's own `ios-appicon-1024.png`: their mark spans 0.564 of the
    /// side, so the inset is (1 − 0.564)/2. Matching it rather than choosing one keeps the
    /// composition theirs — and the measurement also confirmed the parse, because the
    /// rendered aspect came out at 0.796 against the viewBox's 0.794.
    static let ios = 0.218
    static let android = 0.28
    static let bare = 0.04
}

/// The transform that fits the artwork's viewBox into a square output, centred, y-down.
func fit(_ viewBox: CGRect, into side: Double, inset: Double) -> CGAffineTransform {
    let available = side * (1 - 2 * inset)
    let scale = min(available / viewBox.width, available / viewBox.height)
    let width = viewBox.width * scale, height = viewBox.height * scale
    return CGAffineTransform(translationX: (side - width) / 2, y: (side - height) / 2)
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -viewBox.minX, y: -viewBox.minY)
}

/// y-down artwork into CoreGraphics' y-up bitmap.
func flipped(_ side: Double) -> CGAffineTransform {
    CGAffineTransform(translationX: 0, y: side).scaledBy(x: 1, y: -1)
}

func renderPNG(_ artwork: Artwork, face: Face, side: Int, inset: Double) -> Data {
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

    let transform = fit(artwork.viewBox, into: s, inset: inset).concatenating(flipped(s))
    let combined = CGMutablePath()
    for d in artwork.paths {
        guard let parsed = try? PathParser(d) else { fatalError("could not parse a path") }
        combined.addPath(parsed.path, transform: transform)
    }

    ctx.saveGState()
    ctx.addPath(combined)
    ctx.clip()
    if let flat = face.flat {
        ctx.setFillColor(flat.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    } else {
        // The designer's own stops and their own gradient vector, mapped through the same
        // transform as the paths — so the arc lands across the mark exactly where the SVG puts
        // it, at every size and inset.
        let colours = artwork.stops.map { Ink($0.hex).cgColor } as CFArray
        let locations = artwork.stops.map { CGFloat($0.offset) }
        let gradient = CGGradient(colorsSpace: space, colors: colours, locations: locations)!
        ctx.drawLinearGradient(gradient,
                               start: artwork.gradientStart.applying(transform),
                               end: artwork.gradientEnd.applying(transform),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { fatalError("could not make an image") }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil
    ) else { fatalError("could not make a PNG destination") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write the PNG") }
    return data as Data
}

// MARK: - Android vector output

func number(_ v: Double) -> String {
    let r = (v * 1000).rounded() / 1000
    return r == r.rounded() ? String(Int(r)) : String(format: "%g", r)
}

/// The adaptive icon's layers, as vector drawables.
///
/// The path data is the designer's, **verbatim**, wrapped in a `<group>` that scales and
/// translates it into the 108dp viewport. Re-emitting the geometry would mean converting the
/// arcs to cubics and hoping two renderers agree; a transform on the original leaves the
/// numbers alone.
func androidVector(_ artwork: Artwork, flat: Bool) -> String {
    let side = 108.0
    let available = side * (1 - 2 * Inset.android)
    let scale = min(available / artwork.viewBox.width, available / artwork.viewBox.height)
    let width = artwork.viewBox.width * scale, height = artwork.viewBox.height * scale
    let translateX = (side - width) / 2 - artwork.viewBox.minX * scale
    let translateY = (side - height) / 2 - artwork.viewBox.minY * scale
    let aapt = flat ? "" : "\n    xmlns:aapt=\"http://schemas.android.com/aapt\""

    var out = """
    <?xml version="1.0" encoding="utf-8"?>
    <!-- Generated by scripts/brand-mark.swift from docs/designs/brand/storyarc-mark.svg.
         Do not edit: change the SVG. The path data below is the designer's, verbatim. -->
    <vector xmlns:android="http://schemas.android.com/apk/res/android"\(aapt)
        android:width="108dp"
        android:height="108dp"
        android:viewportWidth="108"
        android:viewportHeight="108">
        <group
            android:scaleX="\(number(scale))"
            android:scaleY="\(number(scale))"
            android:translateX="\(number(translateX))"
            android:translateY="\(number(translateY))">

    """
    for d in artwork.paths {
        if flat {
            out += "        <path android:fillColor=\"\(Palette.monoMark.hex)\" "
                 + "android:pathData=\"\(d)\" />\n"
        } else {
            let items = artwork.stops.map {
                "                        <item android:offset=\"\(number($0.offset))\" "
                + "android:color=\"\($0.hex)\" />"
            }.joined(separator: "\n")
            out += """
                    <path android:pathData="\(d)">
                        <aapt:attr name="android:fillColor">
                            <gradient
                                android:startX="\(number(artwork.gradientStart.x))"
                                android:startY="\(number(artwork.gradientStart.y))"
                                android:endX="\(number(artwork.gradientEnd.x))"
                                android:endY="\(number(artwork.gradientEnd.y))"
                                android:type="linear">
            \(items)
                            </gradient>
                        </aapt:attr>
                    </path>

            """
        }
    }
    out += "    </group>\n</vector>\n"
    return out
}

// MARK: - Asset catalogue metadata

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
/// Generated because it is the *same* value as the token, and a hex typed twice is a hex that
/// will disagree once. Light takes `accentStrong`, the token that exists precisely because the
/// lighter accent fails on paper.
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
    \(entry(Palette.accent, dark: true))
      ],
      "info" : { "author" : "storyarc-brand-mark", "version" : 1 }
    }

    """
}

// MARK: - Verifying the parse

/// What a wrong parse looks like, and how to fail on it.
///
/// `--check` compares committed bytes, so it catches an asset that *changed*. It cannot catch a
/// parse that silently lost a segment — and that failure is invisible in a thumbnail, because a
/// path missing one arc closes across itself and fills a wedge that looks like part of the
/// design.
///
/// **The previous version of this file verified reconstructed geometry**, with parameter bands
/// for a radius and a gap this script no longer owns. Those checks went with the
/// reconstruction. What is worth checking now is that the artwork was read faithfully.
enum ParseProblem: CustomStringConvertible {
    case wrongPathCount(Int)
    case boundsDisagree(CGRect, CGRect)
    case pathNotClosed(Int)
    case emptyPath(Int)
    case stopsUnsorted([Double])
    case stopOutOfRange(Double)

    var description: String {
        switch self {
        case let .wrongPathCount(n):
            return "the artwork has \(n) paths; the mark is six tiles"
        case let .boundsDisagree(parsed, declared):
            return "the parsed paths span \(parsed) but the viewBox declares \(declared) — a "
                 + "segment was probably dropped, which fills a wedge that was never designed"
        case let .pathNotClosed(i):
            return "path \(i) is not closed, so its fill is implementation-defined"
        case let .emptyPath(i):
            return "path \(i) parsed to nothing"
        case let .stopsUnsorted(o):
            return "the gradient's stops are not in order: \(o)"
        case let .stopOutOfRange(o):
            return "a gradient stop is at \(o), outside 0 to 1"
        }
    }
}

func verify(_ artwork: Artwork) -> [ParseProblem] {
    var problems: [ParseProblem] = []

    if artwork.paths.count != 6 { problems.append(.wrongPathCount(artwork.paths.count)) }

    var union = CGRect.null
    for (i, d) in artwork.paths.enumerated() {
        guard let parsed = try? PathParser(d) else { problems.append(.emptyPath(i)); continue }
        if parsed.path.isEmpty { problems.append(.emptyPath(i)); continue }
        if !d.uppercased().contains("Z") { problems.append(.pathNotClosed(i)) }
        union = union.union(parsed.path.boundingBoxOfPath)
    }

    // Within a unit of the declared box on every side. The tolerance is for the cubic
    // approximation of the arcs, which is accurate to far less than a pixel at any output size
    // but is not exact at the control points.
    let declared = artwork.viewBox
    if abs(union.minX - declared.minX) > 1 || abs(union.minY - declared.minY) > 1
        || abs(union.maxX - declared.maxX) > 1 || abs(union.maxY - declared.maxY) > 1 {
        problems.append(.boundsDisagree(union.integral, declared))
    }

    let offsets = artwork.stops.map(\.offset)
    if offsets != offsets.sorted() { problems.append(.stopsUnsorted(offsets)) }
    for offset in offsets where offset < 0 || offset > 1 {
        problems.append(.stopOutOfRange(offset))
    }

    return problems
}

// MARK: - Driver

let arguments = CommandLine.arguments
func flag(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: "--\(name)"), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}
let checking = arguments.contains("--check")
guard let outRoot = flag("out") else {
    FileHandle.standardError.write(Data(
        "Usage: swift scripts/brand-mark.swift --out <dir> [--check]\n".utf8))
    exit(2)
}

let sourcePath = URL(fileURLWithPath: outRoot)
    .appending(path: "docs/designs/brand/storyarc-mark.svg")
guard let svgText = try? String(contentsOf: sourcePath, encoding: .utf8) else {
    FileHandle.standardError.write(Data((
        "cannot read the mark at \(sourcePath.path)\n"
        + "That file is the source of truth — this script renders it and does not "
        + "reconstruct it.\n").utf8))
    exit(1)
}

let artwork: Artwork
do {
    artwork = try Artwork(svg: svgText)
} catch let failure as Artwork.Failure {
    FileHandle.standardError.write(Data("the mark's SVG could not be read: \(failure)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("the mark's SVG could not be read: \(error)\n".utf8))
    exit(1)
}

// Always, in both modes, before anything is written or compared. A generator that can write a
// wrong mark is worse than one that cannot run: the wrong mark gets committed and then gated
// as correct.
let problems = verify(artwork)
if !problems.isEmpty {
    FileHandle.standardError.write(Data((
        "the mark's artwork did not verify:\n" + problems.map { "  - \($0)\n" }.joined()).utf8))
    exit(1)
}

let catalogue = "apps/ios/App/Resources/Assets.xcassets"
let androidRes = "apps/android/app/src/main/res"

var written: [(String, Data)] = []
for face in Face.all where face.id != "bare" {
    let setName = face.id == "ink" ? "AppIcon" : "AppIcon-\(face.name)"
    let file = "\(setName)-1024.png"
    written.append(("\(catalogue)/\(setName).appiconset/\(file)",
                    renderPNG(artwork, face: face, side: 1024, inset: Inset.ios)))
    written.append(("\(catalogue)/\(setName).appiconset/Contents.json",
                    Data(appIconContents(file).utf8)))
}
written.append(("\(catalogue)/AccentColor.colorset/Contents.json",
                Data(accentColorContents().utf8)))
written.append(("\(androidRes)/drawable/ic_launcher_foreground.xml",
                Data(androidVector(artwork, flat: false).utf8)))
written.append(("\(androidRes)/drawable/ic_launcher_monochrome.xml",
                Data(androidVector(artwork, flat: true).utf8)))
written.append(("docs/designs/brand/storyarc-mark-1024.png",
                renderPNG(artwork, face: Face.all.first { $0.id == "bare" }!,
                          side: 1024, inset: Inset.bare)))

var stale: [String] = []
for (relative, data) in written {
    let url = URL(fileURLWithPath: outRoot).appending(path: relative)
    if checking {
        if (try? Data(contentsOf: url)) != data { stale.append(relative) }
    } else {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

if checking {
    if stale.isEmpty {
        print("brand mark: \(written.count) asset(s) current, from the designer's "
              + "\(artwork.paths.count) paths and \(artwork.stops.count) gradient stops.")
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
    print("brand mark: wrote \(written.count) asset(s) from the designer's "
          + "\(artwork.paths.count) paths.")
}
