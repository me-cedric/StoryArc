import Foundation
import Testing

import StoryArcCore
@testable import LibraryFeature

/// Task 15.6: two count sentences had no plural form in the catalog, so a count of one read
/// with a plural noun -- "1 titles" -- in every language this app ships.
///
/// English is the assertion, not French: `swift test` on this host resolves `String(localized:
/// locale:)` against the *system's* preferred language, not the explicit `locale:` argument --
/// measured here by printing `Locale.storyArc.identifier` next to the resolved sentence while
/// `InterfaceLanguage` was pinned to French, which still came back English. The compiled
/// `fr.lproj/Localizable.strings` has the right words (`plutil`, by hand), so this is a
/// characteristic of the host running the test, not of the catalog or the code under test, and
/// `ios-strings.mjs` is what the project already uses to check every language resolves.
/// What *is* provable on this host, and is this suite's job, is that the right plural
/// *category* is chosen for the count -- "title" for one, "titles" for several -- which is
/// the part `String(describing:)` on `Text` showed working in `PromoteEntriesTextTests`.
@Suite("Plural wording")
struct PluralWordingTests {

    @Test("A sync-conflict count of one reads the singular noun")
    func syncConflictCountOfOneIsSingular() {
        let one = String(localized: "sync.conflict.body \(1)", bundle: .module)
        let many = String(localized: "sync.conflict.body \(2)", bundle: .module)

        #expect(one.hasPrefix("1 title moved"), "read: \(one)")
        #expect(many.hasPrefix("2 titles moved"), "read: \(many)")
        #expect(one != many)
    }
}
