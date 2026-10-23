import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import LibraryFeature

/// A server cover is decoded no larger than the cell it fills, and off the main actor. Four
/// cells decoded every cover whole with `UIImage(data:)`; this is the decoder they share.
@Suite("Remote cover")
struct RemoteCoverTests {
    @Test("A picture larger than the cell comes back bounded to the cell")
    func bounded() async throws {
        let image = try #require(await RemoteCover.decoded(try pngData(width: 400, height: 600), maxPixelSize: 200))
        #expect(image.height == 200)
        #expect(image.width <= 200)
    }

    @Test("A picture that already fits keeps its size")
    func fits() async throws {
        let image = try #require(await RemoteCover.decoded(try pngData(width: 40, height: 60), maxPixelSize: 200))
        #expect(image.width == 40)
        #expect(image.height == 60)
    }

    @Test("Bytes that are not a picture are nil rather than a throw")
    func notAPicture() async {
        #expect(await RemoteCover.decoded(Data(), maxPixelSize: 200) == nil)
        #expect(await RemoteCover.decoded(Data("not a picture".utf8), maxPixelSize: 200) == nil)
    }

    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let buffer = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            buffer, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return buffer as Data
    }
}
