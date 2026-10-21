// Makes the macOS app icon from the iOS one (shared-release-train, task 3.3).
//
//   swift make-icon.swift <ios AppIcon-1024.png> <out.png>
//
// The iOS artwork is a full-bleed square that iOS masks. A Mac icon carries its own shape:
// the rounded square of the macOS grid, 824 of 1024 points with a 185-point corner, centred,
// with a soft shadow. The sizes of AppIcon.appiconset come from this one file through sips.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let art = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: swift make-icon.swift <AppIcon-1024.png> <out.png>\n".utf8))
    exit(1)
}
let canvas = 1024, body: CGFloat = 824, radius: CGFloat = 185
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { exit(1) }
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let frame = NSRect(x: (1024 - body) / 2, y: (1024 - body) / 2 + 10, width: body, height: body)
let shape = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 20
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()
shape.addClip()
art.draw(in: frame)
NSGraphicsContext.current = nil
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
