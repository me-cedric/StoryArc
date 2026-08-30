import Testing

@testable import Formats

/// Pure ordering logic. Android's `PageOrderingTest` asserts the same cases —
/// this is the layer most likely to drift between two implementations, so it is
/// the layer held to the same table on both.
@Suite("Page ordering")
struct PageOrderingTests {
    @Test("page10 sorts after page9, not after page1")
    func naturalSort() {
        let paths = ["page1.png", "page10.png", "page2.png", "page9.png", "page11.png"]

        let ordered = PageOrdering.pages(from: paths).map(\.path)

        #expect(ordered == ["page1.png", "page2.png", "page9.png", "page10.png", "page11.png"])
    }

    @Test("Chapter directories order naturally by full path")
    func nestedPaths() {
        let paths = ["ch10/p1.png", "ch2/p1.png", "ch1/p10.png", "ch1/p2.png", "ch1/p1.png"]

        let ordered = PageOrdering.pages(from: paths).map(\.path)

        #expect(ordered == ["ch1/p1.png", "ch1/p2.png", "ch1/p10.png", "ch2/p1.png", "ch10/p1.png"])
    }

    @Test("Leading zeros do not change the value but keep the order total")
    func leadingZeros() {
        let ordered = PageOrdering.pages(from: ["p007.png", "p7.png", "p8.png"]).map(\.path)

        // 7 == 7, so the shorter run wins the tie. What matters is that the
        // order is deterministic and 8 still comes last.
        #expect(ordered == ["p7.png", "p007.png", "p8.png"])
    }

    @Test("A digit sorts before a letter")
    func digitsBeforeLetters() {
        #expect(PageOrdering.naturalCompare("p1.png", "pa.png"))
        #expect(!PageOrdering.naturalCompare("pa.png", "p1.png"))
    }

    @Test("Ordering is case-insensitive but not locale-dependent")
    func caseInsensitive() {
        let ordered = PageOrdering.pages(from: ["B.png", "a.png", "C.png"]).map(\.path)

        #expect(ordered == ["a.png", "B.png", "C.png"])
    }

    @Test("Very large page numbers do not overflow into a wrong order")
    func largeNumbers() {
        let ordered = PageOrdering.pages(from: ["p99999999999.png", "p2.png"]).map(\.path)

        #expect(ordered == ["p2.png", "p99999999999.png"])
    }

    @Test("A digit run longer than any integer type still orders correctly")
    func runsBeyondIntegerRange() {
        // The reason both platforms compare digits rather than parsing them: a
        // 40-digit run has no integer representation on either side.
        let long = "p" + String(repeating: "9", count: 40) + ".png"
        let longer = "p1" + String(repeating: "0", count: 40) + ".png"

        let ordered = PageOrdering.pages(from: [longer, long]).map(\.path)

        #expect(ordered == [long, longer])
    }
}

@Suite("Page exclusion")
struct PageExclusionTests {
    @Test("ComicInfo.xml is never a page")
    func excludesComicInfo() {
        #expect(!PageOrdering.isPage(path: "ComicInfo.xml"))
        #expect(!PageOrdering.isPage(path: "comicinfo.xml"))
    }

    @Test("macOS resource forks are excluded, or every page would be counted twice")
    func excludesResourceForks() {
        #expect(!PageOrdering.isPage(path: "__MACOSX/._page1.png"))
        #expect(!PageOrdering.isPage(path: "._page1.png"))
    }

    @Test("OS cruft is excluded")
    func excludesOSCruft() {
        #expect(!PageOrdering.isPage(path: "Thumbs.db"))
        #expect(!PageOrdering.isPage(path: ".DS_Store"))
        #expect(!PageOrdering.isPage(path: "notes.txt"))
    }

    @Test("Directory entries are not pages")
    func excludesDirectories() {
        #expect(!PageOrdering.isPage(path: "chapter1/"))
    }

    @Test("Every supported image codec is accepted, in any case")
    func acceptsImages() {
        for ext in ["jpg", "JPEG", "png", "WebP", "avif", "gif", "heic", "heif", "bmp", "tiff"] {
            #expect(PageOrdering.isPage(path: "page.\(ext)"), "rejected .\(ext)")
        }
    }

    @Test("A codec neither platform decodes is still a page, so it can be refused by name")
    func acceptsAnUndecodableCodec() {
        // `publication-formats` requires an unsupported codec to show "a placeholder
        // naming the codec" without breaking pagination. A page excluded from the list
        // is a page nobody can be told about, so it stays in and the reader names it.
        #expect(PageOrdering.isPage(path: "page.jxl"))
        #expect(PageCodec.name(of: nil, path: "page.jxl") == "JPEG XL")
    }
}
