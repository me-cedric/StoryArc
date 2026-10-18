import Foundation
import Testing

@testable import StoryArc

/// The bundled reading faces reach the renderer (`ebook-reader`, *Bundled typefaces*).
@Suite("EPUB fonts")
struct EpubFontsTests {
    @Test("The stylesheet names every bundled family, and each face it names is served from the shared package")
    func servedFaces() throws {
        for family in ["Literata", "Source Serif 4", "EB Garamond", "Bitter", "Atkinson Hyperlegible"] {
            #expect(EpubFonts.css.contains("font-family:\"\(family)\""), "\(family) is not declared")
        }
        let files = EpubFonts.css.matches(of: /url\("([^"]+)"\)/).map { String($0.1) }
        #expect(files.count == 12)
        for file in files {
            let face = try #require(EpubFonts.resource(at: EpubFonts.folder + file), "\(file) is not served")
            #expect(face.mimeType == "font/ttf" && !face.data.isEmpty)
        }
        #expect(EpubFonts.resource(at: EpubFonts.sheet)?.mimeType == "text/css")
        #expect(EpubFonts.resource(at: EpubFonts.folder + "none.ttf") == nil)
        #expect(EpubFonts.resource(at: "OEBPS/ch1.xhtml") == nil)
    }

    @Test("A chapter links the stylesheet before its head closes; any other resource is left alone")
    func linksChapters() {
        let chapter = Data("<html><head><title>One</title></HEAD><body/></html>".utf8)
        let data = EpubFonts.linking(chapter, mimeType: "application/xhtml+xml", sheet: "x:/f.css")
        let linked = String(bytes: data, encoding: .utf8) ?? ""
        #expect(linked.contains("<link rel=\"stylesheet storyarc-fonts\" type=\"text/css\" href=\"x:/f.css\"/></HEAD>"))
        // Not `rel='stylesheet'` exactly, so the toolkit still gives an unstyled chapter its default stylesheet.
        #expect(!linked.contains("rel=\"stylesheet\""))
        let style = Data("p{}".utf8)
        #expect(EpubFonts.linking(style, mimeType: "text/css", sheet: "x:/f.css") == style)
    }
}
