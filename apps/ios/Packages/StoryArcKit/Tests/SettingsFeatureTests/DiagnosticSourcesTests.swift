import Foundation
import Persistence
import StoryArcCore
import Testing

@testable import SettingsFeature

/// The diagnostic export's source section is a count, and never a list.
///
/// `sources` forbids a secret reaching "preferences, logs, crash reports, backups, or
/// exported diagnostics", and the export is the one thing here a reader hands to a stranger.
/// Three of a source's fields are exactly what must not travel: the display name, because a
/// reader names a server after the machine and so it *is* the hostname; the locator, because
/// it is a URL and a URL is where an embedded credential survives; and the credential
/// reference, because it is a handle into the platform secure store.
///
/// The registry below is built to be caught. Every one of its strings is distinctive, so an
/// assertion that the report does not contain them fails the moment anything derived from a
/// source is appended to the section.
///
/// Android's `DiagnosticSourcesTest` asserts the same cases, case for case.
@Suite("Diagnostic sources")
struct DiagnosticSourcesTests {

    private let hostname = "comics.attic.example.net"
    private let locator = "https://reader:s3cr3t@comics.attic.example.net/opds/v1.2/root.xml"
    private let credentialReference = "app.storyarc.credential.kavita-9f3ab1"

    private var registry: SourceRegistry {
        SourceRegistry()
            .adding(Source(
                displayName: hostname,
                kind: .opdsCatalog,
                credentialReference: credentialReference,
                locator: locator
            ))
            .adding(Source(displayName: "Attic NAS", kind: .networkShare, locator: "smb://10.0.0.4/comics"))
            .adding(Source(displayName: "Downloads", kind: .localFolder, locator: "Downloads"))
    }

    // MARK: - The section itself

    @Test("The source section is a heading and a count, and nothing else")
    func sectionIsAHeadingAndACount() {
        let lines = Diagnostic.sourceLines(in: registry)

        // Two lines, whatever the registry holds. A list would grow with it, which is the
        // shape this assertion exists to refuse.
        #expect(lines == ["[Sources]", "configured = 3"])
    }

    @Test("The section does not grow when the registry does")
    func sectionDoesNotGrowWithTheRegistry() {
        let one = Diagnostic.sourceLines(in: SourceRegistry().adding(
            Source(displayName: hostname, kind: .kavitaServer, locator: locator)
        ))
        let many = Diagnostic.sourceLines(in: registry)

        #expect(one.count == many.count)
        #expect(one.count == 2)
    }

    @Test("The count is the real one, not a literal")
    func countIsReal() {
        // It was `configured = 0` on both platforms, which is a count in shape and a
        // falsehood in fact: a reader with four servers filed a report saying they had none.
        #expect(Diagnostic.sourceLines(in: SourceRegistry()) == ["[Sources]", "configured = 0"])
        #expect(Diagnostic.sourceLines(in: registry).last == "configured = 3")
    }

    // MARK: - What must not travel

    @Test("No source name reaches the section")
    func sectionCarriesNoName() {
        let section = Diagnostic.sourceLines(in: registry).joined(separator: "\n")

        #expect(!section.contains(hostname))
        #expect(!section.contains("Attic NAS"))
    }

    @Test("No locator and no credential reference reaches the section")
    func sectionCarriesNoLocatorOrCredential() {
        let section = Diagnostic.sourceLines(in: registry).joined(separator: "\n")

        #expect(!section.contains(locator))
        #expect(!section.contains(credentialReference))
        #expect(!section.contains("smb://10.0.0.4/comics"))
    }

    // MARK: - The whole report, not just the section

    @Test("No source value reaches the report at all")
    func reportCarriesNoSourceValue() {
        // The section is where a leak would come from, and the report is where it would
        // matter, so the assertion is made against the text the reader actually shares.
        let report = self.report()

        for secret in [hostname, locator, credentialReference, "Attic NAS", "s3cr3t"] {
            #expect(!report.contains(secret), "\(secret) reached the report")
        }
    }

    @Test("The report still says how many sources there are")
    func reportStatesTheCount() {
        // The refusals above are worth nothing if the section can satisfy them by being
        // absent: a maintainer reading the report has to be able to tell a reader with no
        // sources from a reader with three.
        let report = self.report()

        #expect(report.contains("[Sources]"))
        #expect(report.contains("configured = 3"))
    }

    private func report() -> String {
        Diagnostic.text(
            settings: AppSettings(),
            readerStore: ReaderPreferences(defaults: defaults()),
            historyBytes: 1_024,
            cacheBytes: 2_048,
            sources: registry
        )
    }

    /// A store of its own, so nothing here reads or writes what the app or another test uses.
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "diagnostic-sources-\(UUID().uuidString)") ?? .standard
    }
}
