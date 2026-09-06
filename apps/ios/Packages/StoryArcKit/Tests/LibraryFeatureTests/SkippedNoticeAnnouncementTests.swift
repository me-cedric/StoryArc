import Foundation
import SwiftUI
import Testing

@testable import LibraryFeature

/// The notice is one stop for a screen reader, and the way to the list is a control with a name.
///
/// `library-browsing`'s *Announced without sight*: the notice "is announced once, naming the
/// publication where there is one and the count where there are several", and "the way to the
/// list is a control with a name, not the whole notice". `SkippedNotice.swift` applies
/// `.accessibilityElement(children: .combine)` to the sentence and its reason and gives the
/// list a `Button` of its own — and `named-failures-and-quieter-chrome` was archived with
/// nothing on this platform asserting either. Android's `SkippedNoticeTest` asks its
/// semantics tree the same two questions.
///
/// **The view's built value is read, not its source.** `SkippedNoticeTimerTests` reads the
/// file as text because what it asserts is an *absence* — no sleep, no second `@State` — and
/// a value tree cannot show a code path that is not there. What is asserted here is a
/// presence, and a regex would be satisfied by the modifier's name surviving in a comment,
/// which is the failure `SourceProgressNoteTests` records. A SwiftUI `body` is an eagerly
/// built value, and the combine modifier is in it: `.accessibilityElement(children: .combine)`
/// becomes a `ModifiedContent` whose modifier is an `AccessibilityContainerModifier` holding a
/// `Combine` behaviour, and a `Button` keeps its label and the label its `LocalizedStringKey`.
/// `Mirror` is the only way in without a simulator; the depth cap and the once-per-class rule
/// are the ones `SourceDetailSizeTests` uses.
///
/// Still short of VoiceOver: this proves the notice *asks* to be one element and that the
/// control has a name to announce, never what the platform makes of either. The audit under
/// `apps/ios/UITests` is the other half.
@MainActor
@Suite("The failure notice is announced once, and its list is a named control")
struct SkippedNoticeAnnouncementTests {

    /// One value in a built view, with what it holds.
    final class ViewNode {
        let value: Any
        let label: String?
        let typeName: String
        var children: [ViewNode] = []

        init(value: Any, label: String?) {
            self.value = value
            self.label = label
            typeName = String(describing: type(of: value))
        }

        /// This node and everything under it, depth first.
        var descendants: [ViewNode] { [self] + children.flatMap(\.descendants) }

        /// Every `String` under this node: verbatim text, localisation keys, format arguments.
        var strings: Set<String> { Set(descendants.compactMap { $0.value as? String }) }

        func child(labelled label: String) -> ViewNode? { children.first { $0.label == label } }
    }

    /// The built view as a tree. Depth is capped and class instances are visited once, because
    /// the tree holds bundles and key paths that refer back into it.
    static func tree(of root: Any) -> ViewNode {
        var seen: Set<ObjectIdentifier> = []
        func build(_ value: Any, label: String?, depth: Int) -> ViewNode {
            let node = ViewNode(value: value, label: label)
            guard depth < 40 else { return node }
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .class,
               !seen.insert(ObjectIdentifier(value as AnyObject)).inserted {
                return node
            }
            node.children = mirror.children.map { build($0.value, label: $0.label, depth: depth + 1) }
            return node
        }
        return build(root, label: nil, depth: 0)
    }

    /// The values carrying `.accessibilityElement(children: .combine)`.
    ///
    /// The modifier is an `AccessibilityContainerModifier`; which behaviour it carries is the
    /// type of the box inside it, `AccessibilityChildBehaviorBox<Combine>`. Matched by type
    /// name because SwiftUI gives the behaviour nothing public to compare against — and
    /// `.contain` or `.ignore` would name a different box, which is what makes this a test of
    /// *combine* rather than of any accessibility modifier at all.
    static func combinedElements(in tree: ViewNode) -> [ViewNode] {
        tree.descendants.filter { node in
            guard let modifier = node.child(labelled: "modifier"),
                  modifier.typeName == "AccessibilityContainerModifier" else { return false }
            return modifier.descendants.contains { $0.typeName == "AccessibilityChildBehaviorBox<Combine>" }
        }
    }

    /// What a combined element merges into one stop: the content the modifier is applied to.
    static func merged(_ element: ViewNode) -> ViewNode? { element.child(labelled: "content") }

    static func buttons(in tree: ViewNode) -> [ViewNode] {
        tree.descendants.filter { $0.typeName.hasPrefix("Button<") }
    }

    private static let sevenZip = SkippedPublications.Entry(
        name: "refused.cb7", reason: .unsupportedFormat("CB7")
    )
    private static let protected = SkippedPublications.Entry(
        name: "password-protected.cbz", reason: .archivePasswordProtected
    )

    /// The catalogue key the notice asks for on the 7-Zip's behalf, with its hole erased the
    /// way SwiftUI derives it from the interpolation in `SkipReasonWords.swift`.
    private static let sevenZipReasonKey = "library.skipped.reason.unsupported %@"
    private static let protectedReasonKey = "library.skipped.reason.archivePasswordProtected"

    /// The notice's built body for one scan's refusals, dismissed or not.
    private static func notice(_ entries: [SkippedPublications.Entry], dismissed: Bool = false) -> ViewNode {
        var skipped = SkippedPublications().settling(entries)
        if dismissed { skipped = skipped.dismissing() }
        return tree(of: SkippedNotice(skipped: skipped, dismiss: {}).body)
    }

    @Test("One failure is one element, and it says the name and the reason together")
    func oneFailureIsOneStop() throws {
        let tree = Self.notice([Self.sevenZip])

        let elements = Self.combinedElements(in: tree)
        #expect(elements.count == 1, "expected one combined element, found \(elements.count)")
        let element = try #require(elements.first)
        let said = try #require(Self.merged(element)).strings

        // "naming the publication where there is one": the sentence, its argument and the
        // reason are all inside the one element. Unmerged, the reason is a second stop.
        #expect(
            said.contains { $0.hasPrefix("library.skipped.one ") },
            "the sentence is not in the merged element: \(said.sorted())"
        )
        #expect(said.contains(Self.sevenZip.name), "the publication's name is not in the merged element")
        // The reason's **key**, not its words: the notice draws `SkipReason.sentence`, so what
        // the built view holds is the catalogue key and its argument. A screen reader hears the
        // reader's own language, which is what `localization`'s *A publication skipped during a
        // scan* asks for — "a screen reader announces the same translated words the screen
        // shows" — and this is as close as a host test can stand to it.
        #expect(
            said.contains(Self.sevenZipReasonKey),
            "the reason is announced as a second stop, not with the name"
        )
    }

    @Test("Several failures are one element naming the count, with the reasons kept for the list")
    func severalIsOneStopNamingTheCount() throws {
        let tree = Self.notice([Self.sevenZip, Self.protected])

        let elements = Self.combinedElements(in: tree)
        #expect(elements.count == 1, "expected one combined element, found \(elements.count)")
        let element = try #require(elements.first)
        let said = try #require(Self.merged(element)).strings

        #expect(said.contains { $0.hasPrefix("library.skipped ") }, "the count is not in the merged element")
        // "the reasons are not merged": two files that failed differently say different
        // things, in the list, and the notice says neither.
        #expect(!said.contains(Self.sevenZipReasonKey))
        #expect(!said.contains(Self.protectedReasonKey))
        // The control for the two negatives: the walk still sees strings, elsewhere in the tree.
        #expect(tree.strings.contains("library.skipped.list"))
    }

    @Test("The way to the list is a button with a name, and not the notice itself")
    func theWayToTheListIsANamedControl() throws {
        let tree = Self.notice([Self.sevenZip])
        let buttons = Self.buttons(in: tree)

        #expect(
            buttons.contains { $0.strings.contains("library.skipped.list") },
            "no button is labelled with the list's name"
        )
        // Every control in the notice carries a name — `ViewThatFits` builds each of the two
        // twice, and none of the four is a glyph.
        for button in buttons {
            let named = button.strings.contains("library.skipped.list")
                || button.strings.contains("library.skipped.dismiss")
            #expect(named, "a control in the notice carries no name")
        }

        // "not the whole notice": no button encloses the announced element, the element holds
        // no button, and nothing else here is made tappable. A banner that is itself a button
        // is announced as one, and a reader who wanted to dismiss it opens a sheet instead.
        let element = try #require(Self.combinedElements(in: tree).first)
        #expect(
            !buttons.contains { button in button.descendants.contains { $0 === element } },
            "the announced notice is itself a button"
        )
        #expect(Self.buttons(in: element).isEmpty, "a control was merged into the announcement")
        #expect(
            !tree.descendants.contains { $0.typeName.contains("TapGesture") },
            "something in the notice carries a tap gesture"
        )
    }

    @Test("A dismissed notice keeps the named way back and announces nothing else")
    func dismissedKeepsTheWayBack() {
        let tree = Self.notice([Self.sevenZip], dismissed: true)

        // "the list remains reachable from the library", as the same named control — and the
        // count is not shown again, so there is nothing left to combine.
        #expect(Self.buttons(in: tree).contains { $0.strings.contains("library.skipped.list") })
        #expect(Self.combinedElements(in: tree).isEmpty)
        #expect(!Self.buttons(in: tree).contains { $0.strings.contains("library.skipped.dismiss") })
    }

    /// "It does not steal focus from the shelf" is an absence, so it is read from the source the
    /// way `SkippedNoticeTimerTests` reads the timer's: nothing here asks for accessibility
    /// focus. Weaker than the assertions above on purpose, and named as such.
    @Test("Nothing in the notice asks for focus")
    func nothingTakesFocus() {
        let code = LibraryFeatureSource.code(of: "Sources/LibraryFeature/SkippedNotice.swift")
        #expect(!code.contains("accessibilityFocused"))
        #expect(!code.contains("AccessibilityFocusState"))
    }
}
