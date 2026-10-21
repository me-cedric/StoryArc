// Draws the background of the StoryArc disk image window (design.md D6).
//
//   swift make-background.swift <outdir>
//   tiffutil -cathidpicheck <outdir>/bg.png <outdir>/bg@2x.png -out background.tiff
//
// The window is 660 x 400 points. dmg-settings.py puts the app at (180, 200) and the
// Applications link at (480, 200), Finder coordinates, origin top-left, icon size 128.
// The picture carries no text: Finder writes the two labels under the icons.
import AppKit

let width: CGFloat = 660
let height: CGFloat = 400
// Finder y 200 of 400 is also AppKit y 200, so the icon row needs no flip.
let rowY: CGFloat = 200
let appX: CGFloat = 180
let applicationsX: CGFloat = 480

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

let pink = 0xF566B8 as UInt32
let violet = 0xA855F7 as UInt32
let indigo = 0x5B4BF5 as UInt32
let accent = 0x8A4DF0 as UInt32

struct DrawError: Error {
    let what: String
}

func draw() {
    // A light surface with a faint cool tint at the bottom.
    NSGradient(colors: [rgb(0xFCFBFE), rgb(0xF4F2FB)])?
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

    // Soft brand glows in two corners keep the surface calm but not flat.
    NSGradient(colors: [rgb(pink, 0.10), rgb(pink, 0)])?
        .draw(fromCenter: NSPoint(x: 40, y: 380), radius: 0,
              toCenter: NSPoint(x: 40, y: 380), radius: 300, options: [])
    NSGradient(colors: [rgb(indigo, 0.09), rgb(indigo, 0)])?
        .draw(fromCenter: NSPoint(x: 640, y: 10), radius: 0,
              toCenter: NSPoint(x: 640, y: 10), radius: 320, options: [])

    // The brand arc: a wide, thin sweep under the label row, pink to violet to indigo.
    let arc = NSBezierPath()
    arc.move(to: NSPoint(x: -40, y: 40))
    arc.curve(to: NSPoint(x: 700, y: 40),
              controlPoint1: NSPoint(x: 160, y: 120), controlPoint2: NSPoint(x: 500, y: 120))
    for (lineWidth, alpha) in [(26.0, 0.05), (10.0, 0.08), (2.5, 0.28)] as [(CGFloat, CGFloat)] {
        guard let stroke = arc.copy() as? NSBezierPath else { continue }
        NSGraphicsContext.saveGraphicsState()
        stroke.lineWidth = lineWidth
        stroke.lineCapStyle = .round
        // Clip to the stroke outline, then fill the clip with the horizontal gradient.
        let outline = NSBezierPath(cgPath: stroke.cgPath.copy(
            strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10))
        outline.addClip()
        NSGradient(colors: [rgb(pink, alpha), rgb(violet, alpha), rgb(indigo, alpha)])?
            .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 0)
        NSGraphicsContext.restoreGraphicsState()
    }

    // The arrow from the app to Applications, between the 128-point icons with a margin.
    let start = appX + 64 + 30
    let end = applicationsX - 64 - 30
    let head: CGFloat = 11
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: start, y: rowY))
    arrow.line(to: NSPoint(x: end, y: rowY))
    arrow.move(to: NSPoint(x: end - head, y: rowY + head))
    arrow.line(to: NSPoint(x: end, y: rowY))
    arrow.line(to: NSPoint(x: end - head, y: rowY - head))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = rgb(accent, 0.25)
    shadow.shadowBlurRadius = 8
    shadow.shadowOffset = NSSize(width: 0, height: -2)
    shadow.set()
    rgb(accent, 0.85).setStroke()
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func render(scale: CGFloat, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { throw DrawError(what: "no bitmap at scale \(scale)") }
    // The point size sets the DPI (72 or 144) that tiffutil -cathidpicheck checks.
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw DrawError(what: "no PNG at scale \(scale)")
    }
    try png.write(to: url)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift make-background.swift <outdir>\n".utf8))
    exit(2)
}
let outdir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try render(scale: 1, to: outdir.appendingPathComponent("bg.png"))
try render(scale: 2, to: outdir.appendingPathComponent("bg@2x.png"))
