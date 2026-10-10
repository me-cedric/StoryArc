import Formats
@testable import LibraryFeature
import StoryArcCore
import SwiftUI
import XCTest

@testable import StoryArc

/// Screens whose words the other languages lengthen or reorder, drawn in that language.
///
/// The catalogue draws every screen in English. These draw the states that a French, German or
/// Spanish sentence can break: the page's provenance line, the skipped-file notice and the alert
/// for a file the app refuses. Each language entry has an English twin where a control is
/// needed, so a sentence that fits proves something.
///
/// `speaking(_:)` is the app's own switch, which sets the language of strings built outside a view
/// and the environment locale of the ones inside. It is set back in the same test.
@MainActor
final class LocalisedCatalogueTests: XCTestCase {
    private static let moment = Date(timeIntervalSince1970: 1_767_225_600)

    private static let attic = Source(
        id: UUID(uuidString: "5A1D0000-0000-4000-8000-0000000000A1") ?? UUID(),
        displayName: "Grenier", kind: .kavitaServer, state: .connected,
        lastSuccessfulSync: moment, locator: "https://kavita.example.test"
    )
    private static let cellar = Source(
        id: UUID(uuidString: "5A1D0000-0000-4000-8000-0000000000A2") ?? UUID(),
        displayName: "Cave", kind: .opdsCatalog, state: .connected,
        lastSuccessfulSync: moment, locator: "https://opds.example.test"
    )

    private func detailPage(
        _ slug: String,
        language: String,
        sources: [Source],
        home: Source?,
        hasFile: Bool,
        second: Source? = nil,
        index: Int = 0
    ) {
        let model = CatalogueLibrary.model()
        var publication = model.publications[index]
        // A copy on the device draws a Read button, which pushes the provenance line below the
        // first screen. Without the summary the line stays in view.
        if hasFile {
            let entry = CatalogueLibrary.entries[index]
            publication = Publication(
                identity: publication.identity, format: entry.format, displayTitle: entry.title,
                authors: [entry.author], origin: .embedded, pageCount: 48
            )
        }
        publication.sourceID = home?.id ?? Self.attic.id
        var rows = [publication]
        if let second {
            var other = publication
            other.sourceID = second.id
            rows.append(other)
        }
        model.publications = rows + model.publications.enumerated().filter { $0.offset != index }.map(\.element)
        model.registry = SourceRegistry(sources: sources)
        if !hasFile { model.locations.removeAll() }
        model.rebuild()
        let shown = publication
        assertSpoken(slug, language: language, delay: 2, largest: false) {
            NavigationStack {
                PublicationDetailView(publication: shown, model: model, onOpen: { _, _ in })
            }
        }
    }

    /// A title on a server that answers and holds no copy here.
    func testCatalogue19aProvenanceFrenchNotDownloaded() {
        detailPage(
            "19a-provenance-fr-not-downloaded", language: "fr",
            sources: [Self.attic], home: Self.attic, hasFile: false
        )
    }

    /// A title on a server that is stopped.
    func testCatalogue19bProvenanceFrenchServerStopped() {
        var stopped = Self.attic
        stopped.state = .unreachable(since: Self.moment)
        detailPage(
            "19b-provenance-fr-server-stopped", language: "fr",
            sources: [stopped], home: stopped, hasFile: false
        )
    }

    /// A title whose library was removed, with no copy kept.
    func testCatalogue19cProvenanceFrenchLibraryRemoved() {
        detailPage(
            "19c-provenance-fr-library-removed", language: "fr",
            sources: [], home: Self.attic, hasFile: false
        )
    }

    /// A title that a second library holds as well.
    func testCatalogue19dProvenanceFrenchSecondPlace() {
        detailPage(
            "19d-provenance-fr-second-place", language: "fr",
            sources: [Self.attic, Self.cellar], home: Self.attic, hasFile: true, second: Self.cellar,
            index: 9
        )
    }

    /// A page whose publication left the library while the route was still held: the stack
    /// answers with one sentence in an alert, and goes back to the shelf.
    func testCatalogue19eProvenanceFrenchGone() {
        let model = CatalogueLibrary.model()
        assertSpoken("19e-gone-fr", language: "fr", delay: 2, largest: false) {
            GoneScreen(model: model)
        }
    }

    private struct GoneScreen: View {
        let model: LibraryModel
        @State private var path = [PublicationRoute(publicationID: "no-longer-in-the-library")]

        var body: some View {
            NavigationStack(path: $path) {
                LibraryView(model: model)
                    .publicationPages(in: model, onOpen: { _, _ in })
            }
        }
    }

    /// One skipped file whose reason is the longest sentence, in the longest language.
    /// Spanish is 74 characters against 61 in English. The English twin is the control.
    func testCatalogue20aSkippedNoticeSpanish() {
        skippedNotice("20a-library-skipped-notice-es", language: "es")
    }

    func testCatalogue20bSkippedNoticeEnglishControl() {
        skippedNotice("20b-library-skipped-notice-en", language: "en")
    }

    private func skippedNotice(_ slug: String, language: String) {
        let one = SkippedPublications.Entry(name: "protected.aax", reason: .contentProtected)
        let model = CatalogueLibrary.model(skipped: [one])
        assertSpoken(slug, language: language, delay: 1.5, largest: true) { LibraryView(model: model) }
    }

    /// The alert for a file the app will not open: a `.txt` handed over by the Files app.
    func testCatalogue21aRefusedFileFrench() {
        refusedFile("21a-refused-file-fr", language: "fr")
    }

    func testCatalogue21bRefusedFileEnglishControl() {
        refusedFile("21b-refused-file-en", language: "en")
    }

    private func refusedFile(_ slug: String, language: String) {
        // No largest size: the alert's dim layer and its spring settle differently from run to run
        // at that size, and the unit test of the wording (`RefusedFileWordingTests`) holds the text.
        assertSpoken(slug, language: language, delay: 2, largest: false) { RefusedScreen() }
    }

    /// Draws a screen in one language, then puts the language back.
    ///
    /// The host app is running behind the tests, and its own root sets the language back to the
    /// device's whenever it redraws. A language set once, before the draw, is lost to that at an
    /// unpredictable moment, and the page then reads the sentence in English. The timeline asks for
    /// the content again every tenth of a second, and each ask sets the language first. The latch
    /// stops the asks when the draw ends, so a window that outlives the test cannot change the
    /// language of the next one.
    private func assertSpoken<Screen: View>(
        _ slug: String, language: String, delay: TimeInterval, largest: Bool,
        @ViewBuilder _ screen: @escaping () -> Screen
    ) {
        let latch = Latch()
        assertCatalogue(slug, delay: delay, largest: largest) {
            Speaking(tag: language, latch: latch, content: screen)
        }
        latch.isOn = false
        InterfaceLanguage.choose(nil)
    }

    private final class Latch {
        var isOn = true
    }

    private struct Speaking<Content: View>: View {
        let tag: String
        let latch: Latch
        @ViewBuilder let content: () -> Content

        var body: some View {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                if latch.isOn {
                    content().speaking(tag)
                } else {
                    content()
                }
            }
        }
    }

    private struct RefusedScreen: View {
        @State private var file: RefusedFile? = RefusedFile(name: "notes.txt", detected: nil)

        var body: some View {
            Color(.systemBackground).ignoresSafeArea().refusing($file)
        }
    }
}
