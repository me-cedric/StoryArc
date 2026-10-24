@testable import EpubReaderFeature
import DesignSystem
import Foundation
import ReaderFeature
import StoryArcCore
import SwiftUI
import UIKit
import XCTest

@MainActor
final class ReaderCatalogueTests: XCTestCase {
    /// A comic of three painted pages, written to a folder of its own.
    private func comic(direction: ReadingDirection = .leftToRight) throws -> (Publication, URL) {
        let directory = URL.temporaryDirectory.appending(path: "snapshots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pages = (0..<3).map { index -> (name: String, data: Data) in
            let size = CGSize(width: 800, height: 1_200)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let png = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
                UIColor(hue: 0.08 + 0.1 * CGFloat(index), saturation: 0.25, brightness: 0.96, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor(hue: 0.55, saturation: 0.6, brightness: 0.55, alpha: 1).setFill()
                context.fill(CGRect(x: 60, y: 60, width: 680, height: 520))
                UIColor(hue: 0.02, saturation: 0.7, brightness: 0.75, alpha: 1).setFill()
                context.fill(CGRect(x: 60, y: 640, width: 330, height: 500))
                UIColor(hue: 0.13, saturation: 0.7, brightness: 0.85, alpha: 1).setFill()
                context.fill(CGRect(x: 410, y: 640, width: 330, height: 500))
            }
            return (name: "page\(index + 1).png", data: png)
        }
        let file = directory.appending(path: "Harrow County 004.cbz")
        try StoredZip.build(pages).write(to: file)
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: file.path),
            format: .cbz,
            displayTitle: "The Long Field",
            series: "Harrow County",
            number: "4",
            origin: .embedded,
            pageCount: 3,
            readingDirection: direction
        )
        return (publication, file)
    }

    func testCatalogue15ComicReaderChrome() throws {
        let (publication, file) = try comic()
        assertCatalogue("15-comic-reader-chrome", delay: 3) {
            ReaderView(publication: publication, url: file)
        }
    }

    // MARK: - iPhone Duo (`foldables-and-iphone-duo`)

    /// A fold down the middle of the open display, 12 points wide, in window coordinates.
    private let verticalFold = CGRect(x: 328.5, y: 0, width: 12, height: duoInner.height)

    /// 2.5: the closed device. The phone layout, nothing cut off at the narrower edge.
    ///
    /// The two glass buttons sit over the page's edge here, and their lens moves a few levels of
    /// colour from run to run over about 2 per cent of the screen. The rest is checked as usual.
    func testCatalogue15ComicReaderChromeDuoOuter() throws {
        let (publication, file) = try comic()
        assertCatalogue(
            "15-comic-reader-chrome-duo-outer", delay: 3, precision: 0.97, largest: false, size: duoOuter
        ) {
            ReaderView(publication: publication, url: file)
        }
    }

    /// 1.2: open flat, a lone page on the wider side of the fold, at that side's width. The halves
    /// tie, so the page takes the leading one.
    func testCatalogue15bReaderFoldInner() throws {
        let (publication, file) = try comic()
        assertCatalogue("15b-reader-fold-inner", delay: 3, largest: false, size: duoInner) {
            ReaderView(publication: publication, url: file)
                .environment(\.deviceFold, DeviceFold(division: verticalFold))
        }
    }

    /// 2.3: half open on a table. The page on the upper half, the controls on the lower half.
    func testCatalogue15cReaderTabletop() throws {
        let (publication, file) = try comic()
        let turned = CGSize(width: duoInner.height, height: duoInner.width)
        let fold = CGRect(x: 0, y: 328.5, width: turned.width, height: 12)
        assertCatalogue("15c-reader-tabletop", delay: 3, size: turned) {
            ReaderView(publication: publication, url: file)
                .environment(\.deviceFold, DeviceFold(division: fold, isHalfOpen: true))
        }
    }

    /// 1.3 and 2.4: held like a book, right to left. The spread is forced on, its gutter is on the
    /// fold, and page 1 is on the right.
    func testCatalogue15dReaderBookRtl() throws {
        let (publication, file) = try comic(direction: .rightToLeft)
        assertCatalogue("15d-reader-book-rtl", delay: 3, largest: false, size: duoInner) {
            ReaderView(publication: publication, url: file)
                .environment(\.deviceFold, DeviceFold(division: verticalFold, isHalfOpen: true))
        }
    }

    /// 2.6: Split View on the open display, on the left with the system's controls on the left
    /// edge, and on the right with none.
    func testCatalogue15eReaderSplitView() throws {
        let (publication, file) = try comic()
        let half = CGSize(width: 334, height: duoInner.height)
        assertCatalogue("15e-reader-split-left", delay: 3, largest: false, size: half) {
            ReaderView(publication: publication, url: file).safeAreaPadding(.leading, 24)
        }
        assertCatalogue("15f-reader-split-right", delay: 3, largest: false, size: half) {
            ReaderView(publication: publication, url: file)
        }
    }

    func testCatalogue16ThemeSheet() {
        let url = URL(fileURLWithPath: "/fixtures/salt-and-lantern.epub")
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: url.path),
            format: .epub,
            displayTitle: "Salt and Lantern",
            origin: .embedded
        )
        let model = EpubReaderModel(publication: publication, url: url)
        assertCatalogue("16-theme-sheet", delay: 3) {
            ThemeSheet(model: model)
        }
    }
}
