@testable import EpubReaderFeature
import Foundation
import ReaderFeature
import StoryArcCore
import SwiftUI
import UIKit
import XCTest

@MainActor
final class ReaderCatalogueTests: XCTestCase {
    /// A comic of three painted pages, written to a folder of its own.
    private func comic() throws -> (Publication, URL) {
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
            pageCount: 3
        )
        return (publication, file)
    }

    func testCatalogue15ComicReaderChrome() throws {
        let (publication, file) = try comic()
        assertCatalogue("15-comic-reader-chrome", delay: 3) {
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
