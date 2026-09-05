import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature
@testable import StoryArcCore

/// A `ForEach` with its rows built, the way SwiftUI would build them.
///
/// A `body` is eager everywhere except here: `ForEach` stores its `content` closure and builds
/// a row only when the platform asks for one. The chooser's five rows come from one, so a walk
/// over the value tree has to call it. `data` and `content` are both public, and this
/// extension is the whole of the trick.
private protocol RowBuilding {
    func builtRows() -> [Any]
}

extension ForEach: RowBuilding {
    func builtRows() -> [Any] { data.map { content($0) } }
}

/// Each icon option is one element, announced by name and by whether it is in use.
///
/// `settings-and-about`'s *Announced without sight*: an option "is announced by name and by
/// whether it is the one in use, and never as an unlabelled image", and "the tile itself is
/// decorative to assistive technology". `AppIconSettings.swift` applies
/// `.accessibilityElement(children: .combine)` and `.accessibilityAddTraits` to each row and
/// `.accessibilityHidden(true)` to each tile — and `brand-identity-and-app-icons` was archived
/// with nothing reading the row's traits. Android's `SettingsSemanticsTest` asks the same of
/// its `selectableRow`.
///
/// **The view's built value is read, not its source**, for the reason `SourceDetailSizeTests`
/// gives: a regex is satisfied by a modifier's name in a comment. The row is a `Button` under
/// an `AccessibilityContainerModifier` carrying `Combine`, then an
/// `AccessibilityAttachmentModifier` whose `TraitsKey` entry holds SwiftUI's own trait bits.
/// The bits are never spelled here — `selectedBits` and `buttonBits` are read off two control
/// views built with the public modifier, so if SwiftUI renumbers them both sides move at once.
///
/// This proves what the row asks the platform to say, never what VoiceOver says. The capture
/// `ios-app-icon-chooser-ax5.png` is the other half.
@MainActor
@Suite("Each icon option is one element that says its name and whether it is in use")
struct AppIconChooserAnnouncementTests {

    /// One value in a built view, with what it holds. `ForEach` rows are children labelled `row`.
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

        var descendants: [ViewNode] { [self] + children.flatMap(\.descendants) }
        var strings: Set<String> { Set(descendants.compactMap { $0.value as? String }) }
        func child(labelled label: String) -> ViewNode? { children.first { $0.label == label } }
    }

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
            // On the struct itself and not on the `Optional` around it: a dynamic cast unwraps an
            // optional, so without the check every row would be built twice.
            if mirror.displayStyle == .struct, let forEach = value as? any RowBuilding {
                node.children += forEach.builtRows().map { build($0, label: "row", depth: depth + 1) }
            }
            return node
        }
        return build(root, label: nil, depth: 0)
    }

    /// The values carrying `.accessibilityElement(children: .combine)` — see
    /// `SkippedNoticeAnnouncementTests` for why the behaviour is matched by its box's type.
    static func combinedElements(in tree: ViewNode) -> [ViewNode] {
        tree.descendants.filter { node in
            guard let modifier = node.child(labelled: "modifier"),
                  modifier.typeName == "AccessibilityContainerModifier" else { return false }
            return modifier.descendants.contains { $0.typeName == "AccessibilityChildBehaviorBox<Combine>" }
        }
    }

    /// The bits an accessibility attachment under `node` stores for `key`, or nil if it stores none.
    ///
    /// `.accessibilityAddTraits` and `.accessibilityHidden` both write an entry keyed by a type
    /// — `TraitsKey`, `VisibilityKey` — whose value is an option set with a `rawValue`.
    static func bits(for key: String, in node: ViewNode) -> UInt64? {
        let entry = node.descendants.first { $0.child(labelled: "key")?.typeName.contains(key) == true }
        let raw = entry?.child(labelled: "value")?.child(labelled: "value")?.child(labelled: "rawValue")?.value
        switch raw {
        case let wide as UInt64: return wide
        case let narrow as UInt32: return UInt64(narrow)
        default: return nil
        }
    }

    /// SwiftUI's own numbering, read rather than assumed.
    private static let selectedBits = bits(
        for: "TraitsKey", in: tree(of: Text("x").accessibilityAddTraits(.isSelected))
    )
    private static let buttonBits = bits(
        for: "TraitsKey", in: tree(of: Text("x").accessibilityAddTraits(.isButton))
    )
    private static let hiddenBits = bits(
        for: "VisibilityKey", in: tree(of: Color.red.accessibilityHidden(true))
    )

    /// The chooser over a platform that draws `applied`, built, with its rows.
    private static func chooser(
        applied: AppIconChoice = .paper, offered: Bool = true, refuses: Bool = false
    ) -> (tree: ViewNode, rows: [ViewNode]) {
        let platform = AppIconPlatform(
            applied: { applied },
            apply: { _, done in done(!refuses) },
            isOffered: { offered }
        )
        let store = AppIconStore(platform: platform)
        if refuses { store.choose(.arc) }
        let tree = tree(of: AppIconSettings(store: store).body)
        return (tree, tree.descendants.filter { $0.label == "row" })
    }

    private static func key(_ face: AppIconChoice) -> String { "appIcon.\(face.rawValue)" }

    private static func row(for face: AppIconChoice, in rows: [ViewNode]) throws -> ViewNode {
        try #require(rows.first { $0.strings.contains(key(face)) }, "no row names \(face)")
    }

    @Test("The calibration views carry distinct bits, so the assertions below compare something")
    func theBitsAreReadable() {
        #expect(Self.selectedBits != nil)
        #expect(Self.buttonBits != nil)
        #expect(Self.hiddenBits != nil)
        #expect(Self.selectedBits != Self.buttonBits)
        let shown = Self.bits(for: "VisibilityKey", in: Self.tree(of: Color.red.accessibilityHidden(false)))
        #expect(shown != Self.hiddenBits)
    }

    @Test("Every face is one combined element wrapping its button, named for the face")
    func everyOptionIsOneNamedElement() throws {
        let rows = Self.chooser().rows
        #expect(rows.count == AppIconChoice.allCases.count, "expected five rows, found \(rows.count)")

        for face in AppIconChoice.allCases {
            let row = try Self.row(for: face, in: rows)
            let elements = Self.combinedElements(in: row)
            #expect(elements.count == 1, "\(face): expected one combined element, found \(elements.count)")
            // The button is inside the element, so the name, the state and the action are one stop
            // rather than a tile followed by two pieces of text.
            let merged = try #require(elements.first?.child(labelled: "content"))
            #expect(merged.descendants.contains { $0.typeName.hasPrefix("Button<") }, "\(face): the button is outside")
            #expect(merged.strings.contains(Self.key(face)), "\(face): the name is outside the element")
            // "the default is marked as the default", and only it.
            #expect(merged.strings.contains("appIcon.default") == face.isDefault, "\(face) and 'Default' disagree")
        }
    }

    @Test("The face in use carries the selected trait, and the other four do not")
    func theOneInUseSaysSo() throws {
        let rows = Self.chooser(applied: .paper).rows
        let selected = try #require(Self.selectedBits)
        let button = try #require(Self.buttonBits)

        for face in AppIconChoice.allCases {
            let traits = try #require(Self.bits(for: "TraitsKey", in: try Self.row(for: face, in: rows)))
            #expect(traits & button == button, "\(face) is not announced as a button")
            #expect((traits & selected == selected) == (face == .paper), "\(face)'s 'in use' state is wrong")
        }
    }

    @Test("The tile is hidden from assistive technology")
    func theTileIsDecorative() throws {
        let rows = Self.chooser().rows
        let hidden = try #require(Self.hiddenBits)

        for face in AppIconChoice.allCases {
            // The tile is a nested view, so its own body has to be built to see its modifiers.
            let tile = try #require(
                try Self.row(for: face, in: rows).descendants.first { $0.typeName == "AppIconTile" }?.value
            )
            let body = try #require(Self.body(of: tile), "\(face)'s tile is not a View")
            #expect(Self.bits(for: "VisibilityKey", in: Self.tree(of: body)) == hidden, "\(face)'s tile is announced")
        }
    }

    /// `native-experience`: where the platform withdraws the choice, "no face is shown as in use".
    @Test("A platform that offers no choice draws no rows, and says why")
    func noRowsWhereTheChoiceIsWithdrawn() {
        let (tree, rows) = Self.chooser(offered: false)
        #expect(rows.isEmpty, "\(rows.count) rows offered on a device that cannot change its icon")
        #expect(tree.strings.contains("appIcon.unsupported"))
        #expect(!tree.strings.contains("appIcon.note"))
    }

    /// `settings-and-about`: a refusal "names which one is still in use where one is".
    @Test("A refusal names the face still in use, in the note's place")
    func aRefusalNamesTheFaceStillInUse() {
        let tree = Self.chooser(applied: .paper, refuses: true).tree
        #expect(tree.strings.contains { $0.hasPrefix("appIcon.refused ") })
        #expect(!tree.strings.contains("appIcon.note"))
    }

    /// The body of a type-erased view, which is what a nested private view arrives as.
    private static func body(of view: Any) -> Any? {
        guard let view = view as? any View else { return nil }
        return open(view)
    }

    private static func open<V: View>(_ view: V) -> Any { view.body }
}
