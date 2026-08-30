import Foundation
import Testing

@testable import Formats

/// What a page's bytes say they are.
///
/// `publication-formats`: "a page in an unsupported codec displays a placeholder naming
/// the codec, and does not break pagination". The naming is what this covers, and the
/// cases are chosen for the ways a sniffer goes wrong: two families whose signature is
/// not at offset zero, one whose brand is the only difference from another, and a name
/// that lies about its contents.
///
/// Android's `PageCodecTest` asserts the same table, case for case.
@Suite("Page codecs")
struct PageCodecTests {

    /// A prefix long enough to sniff, padded so a short-array guard cannot pass by luck.
    private func prefix(_ bytes: [UInt8]) -> Data {
        Data(bytes + Array(repeating: 0, count: max(0, 16 - bytes.count)))
    }

    @Test("The fixed signatures are read from the head of the file")
    func fixedSignatures() {
        #expect(PageCodec.of(prefix([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
        #expect(PageCodec.of(prefix([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) == .png)
        #expect(PageCodec.of(prefix(Array("GIF89a".utf8))) == .gif)
        #expect(PageCodec.of(prefix(Array("BM".utf8))) == .bmp)
        #expect(PageCodec.of(prefix([0x49, 0x49, 0x2A, 0x00])) == .tiff)
        #expect(PageCodec.of(prefix([0x4D, 0x4D, 0x00, 0x2A])) == .tiff)
    }

    @Test("WebP is a RIFF container, so the four length bytes in the middle are skipped")
    func webpIgnoresTheChunkLength() {
        let riff = Array("RIFF".utf8) + [0x2A, 0x13, 0x00, 0x00] + Array("WEBP".utf8)
        #expect(PageCodec.of(prefix(riff)) == .webp)
        // A RIFF that is not WebP — a WAV, say — is not a page codec.
        let wave = Array("RIFF".utf8) + [0x2A, 0x13, 0x00, 0x00] + Array("WAVE".utf8)
        #expect(PageCodec.of(prefix(wave)) == nil)
    }

    @Test("AVIF and HEIC are the same container, told apart by the brand alone")
    func isoBaseMediaBrands() {
        func ftyp(_ brand: String) -> Data {
            prefix([0, 0, 0, 0x18] + Array("ftyp".utf8) + Array(brand.utf8))
        }
        #expect(PageCodec.of(ftyp("avif")) == .avif)
        #expect(PageCodec.of(ftyp("avis")) == .avif)
        #expect(PageCodec.of(ftyp("heic")) == .heic)
        #expect(PageCodec.of(ftyp("mif1")) == .heic)
        // A brand this app knows nothing about is not guessed at.
        #expect(PageCodec.of(ftyp("qt  ")) == nil)
    }

    @Test("JPEG XL is recognised in both of its two shapes")
    func jpegXL() {
        #expect(PageCodec.of(prefix([0xFF, 0x0A])) == .jpegXL)
        #expect(
            PageCodec.of(
                prefix([0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A])
            ) == .jpegXL
        )
    }

    @Test("Bytes that are not an image name nothing")
    func unrecognised() {
        #expect(PageCodec.of(prefix(Array("not an image at all".utf8))) == nil)
        #expect(PageCodec.of(Data()) == nil)
    }

    @Test("The name comes from the bytes, not from a file name that disagrees")
    func bytesBeatTheExtension() {
        let avif = prefix([0, 0, 0, 0x18] + Array("ftyp".utf8) + Array("avif".utf8))
        #expect(PageCodec.name(of: avif, path: "pages/001.jpg") == "AVIF")
    }

    @Test("With no bytes to read, the extension is the best that can be said")
    func extensionIsTheFallback() {
        #expect(PageCodec.name(of: nil, path: "pages/001.jxl") == "JPEG XL")
        #expect(PageCodec.name(of: nil, path: "pages/001.HEIF") == "HEIC")
    }

    @Test("A page nothing can be said about is named nothing, rather than guessed at")
    func nothingToSay() {
        #expect(PageCodec.name(of: nil, path: "pages/001") == nil)
        #expect(PageCodec.name(of: Data([0x00, 0x01]), path: "pages/001.xyz") == nil)
    }

    @Test("Every codec has a name a reader would recognise")
    func everyCodecIsNamed() {
        for codec in PageCodec.allCases {
            #expect(!codec.displayName.isEmpty, "\(codec)")
        }
    }
}
