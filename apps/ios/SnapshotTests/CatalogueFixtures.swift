import CoreGraphics
import Foundation
import UIKit

@testable import LibraryFeature
import StoryArcCore

/// The library every catalogue screen draws: twelve titles, three of them part-read, one
/// finished, with covers painted here so no file, corpus or network is needed.
@MainActor
enum CatalogueLibrary {
    struct Entry {
        let title: String
        let author: String
        let format: PublicationFormat
        let hue: CGFloat
        var series: String?
        var number: String?
        var progress: Double?
    }

    private static func entry(
        _ title: String, _ author: String, _ format: PublicationFormat, hue: CGFloat,
        series: String? = nil, number: String? = nil, progress: Double? = nil
    ) -> Entry {
        Entry(
            title: title, author: author, format: format, hue: hue,
            series: series, number: number, progress: progress
        )
    }

    static let entries: [Entry] = [
        entry("The Long Field", "Cullen Bunn", .cbz, hue: 0.02, series: "Harrow County", number: "4", progress: 0.62),
        entry("Salt and Lantern", "Mara Ellison", .epub, hue: 0.55, progress: 0.31),
        entry("Night Ferry", "Ines Okafor", .cbz, hue: 0.72, series: "Harbour Lights", number: "1"),
        entry("Night Ferry", "Ines Okafor", .cbz, hue: 0.74, series: "Harbour Lights", number: "2"),
        entry("A Field Guide to Fog", "T. Rowan", .pdf, hue: 0.12, progress: 0.08),
        entry("The Cartographer's Daughter", "Lena Voss", .m4b, hue: 0.40),
        entry("Paper Moons", "Yuki Hara", .cbz, hue: 0.90, series: "Paper Moons", number: "1", progress: 1),
        entry("Brass Season", "Dov Lindqvist", .cbr, hue: 0.08, series: "Brass Season", number: "3"),
        entry("Quiet Engines", "Priya Nair", .epub, hue: 0.62),
        entry("Apple Orchard Blues", "June Calder", .cbz, hue: 0.28),
        entry("Zephyr", "Omar Haddad", .cb7, hue: 0.50, series: "Zephyr", number: "7"),
        entry("#1 Fan", "Sam Ito", .cbz, hue: 0.17),
    ]

    /// Twenty-six titles, one per letter, for the shelf that grows an A to Z rail.
    static let alphabet: [Entry] = {
        let words = [
            "Atlas", "Brass", "Cinder", "Dune", "Ember", "Fathom", "Garden", "Harbour", "Ink", "Juniper",
            "Kestrel", "Lantern", "Marrow", "Nettle", "Orchard", "Paper", "Quill", "Ridge", "Salt", "Thistle",
            "Umber", "Vesper", "Willow", "Xylem", "Yarrow", "Zephyr",
        ]
        return words.enumerated().map { index, word in
            entry(
                "\(word) Season", "Fixture Author", index.isMultiple(of: 3) ? .epub : .cbz,
                hue: CGFloat(index) / 26, progress: index == 4 ? 0.4 : nil
            )
        }
    }()

    static let now = Date(timeIntervalSince1970: 1_767_225_600)

    static func publication(_ entry: Entry, index: Int) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/fixtures/\(index)-\(entry.title).\(entry.format.rawValue)"),
            format: entry.format,
            displayTitle: entry.title,
            series: entry.series,
            number: entry.number,
            authors: [entry.author],
            publisher: "Fixture Press",
            year: 2024,
            language: "en",
            summary: "A short fixture summary that runs to two lines, so the publication page shows how a "
                + "description wraps under the title block and before the actions.",
            genres: ["Fiction"],
            origin: .embedded,
            pageCount: entry.format.isPagedImages ? 48 : nil,
            addedAt: now.addingTimeInterval(-Double(index) * 86_400)
        )
    }

    static var publications: [Publication] {
        entries.enumerated().map { publication($0.element, index: $0.offset) }
    }

    /// An empty file that exists, so a publication is readable on this device without a corpus.
    static func presentFile(named name: String) -> URL {
        let folder = URL.temporaryDirectory.appending(path: "catalogue-fixtures", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: name)
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: Data())
        }
        return file
    }

    /// A model holding the fixture shelf, with covers drawn for every entry when asked.
    static func model(
        entries chosen: [Entry]? = nil,
        withCovers: Bool = true,
        layout: LibraryLayout = .grid
    ) -> LibraryModel {
        let used = chosen ?? entries
        let model = LibraryModel()
        // A folder in the model is what stops `restoreFolders()` scanning the host's own
        // Documents, which would replace the fixtures a moment after they are drawn.
        model.folders = [URL(fileURLWithPath: "/fixtures")]
        let list = used.enumerated().map { publication($0.element, index: $0.offset) }
        model.publications = list
        for (index, entry) in used.enumerated() {
            let publication = list[index]
            model.locations[publication.id] = presentFile(named: "\(index)-\(entry.title).\(entry.format.rawValue)")
            if withCovers { model.covers[publication.id] = CatalogueCover.image(for: entry.title, hue: entry.hue) }
            if let fraction = entry.progress {
                model.progress[publication.id] = ReadingProgress(
                    identity: publication.identity,
                    position: .page(index: Int(fraction * 48), of: 48),
                    isFinished: fraction >= 1,
                    finishedAt: fraction >= 1 ? now : nil,
                    updatedAt: now.addingTimeInterval(-Double(index) * 3_600)
                )
            }
        }
        model.layout = layout
        model.rebuild()
        return model
    }
}

/// A cover painted from a hue: a two-stop gradient, a sun and a ridge. No lettering, so the
/// title the screen draws is the only title in the picture.
enum CatalogueCover {
    @MainActor
    static func image(for title: String, hue: CGFloat) -> CGImage {
        let size = CGSize(width: 400, height: 600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let picture = renderer.image { context in
            let top = UIColor(hue: hue, saturation: 0.45, brightness: 0.92, alpha: 1)
            let bottom = UIColor(hue: hue, saturation: 0.70, brightness: 0.45, alpha: 1)
            let colours = [top.cgColor, bottom.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: []
                )
            }
            UIColor.white.withAlphaComponent(0.85).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 230, y: 90, width: 110, height: 110))
            UIColor(hue: hue, saturation: 0.75, brightness: 0.28, alpha: 1).setFill()
            let ridge = UIBezierPath()
            ridge.move(to: CGPoint(x: 0, y: 600))
            ridge.addLine(to: CGPoint(x: 0, y: 380))
            ridge.addLine(to: CGPoint(x: 120, y: 280))
            ridge.addLine(to: CGPoint(x: 230, y: 360))
            ridge.addLine(to: CGPoint(x: 330, y: 250))
            ridge.addLine(to: CGPoint(x: 400, y: 320))
            ridge.addLine(to: CGPoint(x: 400, y: 600))
            ridge.close()
            ridge.fill()
        }
        guard let image = picture.cgImage else { preconditionFailure("A painted cover has a bitmap.") }
        return image
    }
}
