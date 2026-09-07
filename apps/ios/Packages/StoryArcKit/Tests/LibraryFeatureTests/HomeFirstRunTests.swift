import Foundation
import SwiftUI
import Testing

@testable import LibraryFeature

import StoryArcCore

/// Home with nothing added draws the state that names the four kinds of place.
///
/// `sources`, *Adding the first source*: a user who opens the app with no source configured
/// is shown "an empty state naming the four source types with a one-line explanation of
/// each". The shelf obeyed it. Home drew `HomeEmpty` — one sentence and two buttons, naming
/// no kind at all — on the screen the app opens on, which is where a reader with nothing
/// configured actually lands. ``EmptyLibraryView``'s own comment already said Home *is* this
/// state, so the code and the screen disagreed.
///
/// **Home's own value tree is walked**, the reflection walk ``SourceKindsAreNamedTests``
/// documents: a guard that read the source text would pass on a `HomeEmpty` renamed, and a
/// screenshot proves a layout rather than a branch.
///
/// The chain from there is `EmptyLibraryView` → ``AddSourceMenu`` → the eight keys.
/// ``SourceKindsAreNamedTests`` holds the last link and this holds the first two, so the
/// naming is asserted once and reached from both destinations that draw it.
@MainActor
@Suite("Home with nothing added draws the state that names the four kinds")
struct HomeFirstRunTests {

    /// The first value of a type anywhere in a view's tree, or `nil`.
    ///
    /// Stored properties only, and a `body` is never asked of a value found here: `Text` and
    /// the other primitives answer that question by trapping.
    private static func find<T>(_ wanted: T.Type, in value: Any, depth: Int = 0) -> T? {
        guard depth < 40 else { return nil }
        if let found = value as? T { return found }
        for child in Mirror(reflecting: value).children {
            if let found = find(wanted, in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func home(_ model: LibraryModel) -> HomeScreen { HomeScreen(model: model) }

    @Test("A reader who has added nothing gets the library's own empty state")
    func homeDrawsTheEmptyState() throws {
        _ = try #require(
            Self.find(EmptyLibraryView.self, in: Self.home(LibraryModel()).body),
            "Home with no publications drew something other than EmptyLibraryView"
        )
    }

    /// The link the walk above cannot cross, asserted on the type instead.
    ///
    /// ``View/reachableAtEveryTextSize()`` wraps the state in a `GeometryReader`, whose
    /// content is a closure — `Mirror` sees a function and stops. The generic type of the
    /// body is the same structural fact from the other side: it records every view the state
    /// is built from, and it changes the moment the menu is taken out.
    @Test("That state carries the menu that names the four kinds")
    func theEmptyStateCarriesTheMenu() {
        let drawn = String(describing: type(of: EmptyLibraryView().body))
        #expect(drawn.contains("AddSourceMenu"), "the empty state is built from \(drawn)")
        // The primary action `sources` asks for, which naming the four must not cost: one
        // action that opens a comic with nothing to configure first.
        #expect(drawn.contains("Button"), "the empty state is built from \(drawn)")
    }

    /// The other half of the claim.
    ///
    /// A suite that only ever looked at an empty model would pass on a Home that drew the
    /// empty state over a full library.
    @Test("A library with something in it draws no empty state")
    func afullShelfIsNotEmpty() {
        let model = LibraryModel()
        model.publications = [
            Publication(
                identity: PublicationIdentity(normalizedPath: "/Saga/1.cbz"),
                format: .cbz,
                displayTitle: "Saga #1",
                series: "Saga",
                number: "1",
                origin: .inferred
            )
        ]
        #expect(Self.find(EmptyLibraryView.self, in: Self.home(model).body) == nil)
        // And the walk still reaches Home's contents on that model, so the line above is a
        // branch that was taken rather than a walk that found nothing.
        #expect(Self.find(LibraryModel.self, in: Self.home(model).body) != nil)
    }
}
