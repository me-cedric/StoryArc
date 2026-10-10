internal import SwiftUI

internal import DesignSystem

/// One thing a reader can do about a cover.
///
/// Task 24.1 of `close-the-audited-gaps`. The cover's actions used to be stacked text buttons
/// with a few points between them, each as tall as its own text: a finger hit the wrong one.
/// Two or more related actions are one menu (`design.md` §10), and the system draws each row
/// of a menu at full height.
enum CoverMenuRow: Hashable {
    case choose
    case find
    case searchWeb
    case sendToServer
    case remove

    /// Whether the row waits for a yes before it acts.
    ///
    /// Removing deletes the stored picture and sending changes the cover for everyone who sees
    /// the list, and neither can be undone from here. The rest only open something the reader
    /// can leave.
    var asksFirst: Bool {
        self == .remove || self == .sendToServer
    }
}

/// The cover's menu: which rows, in which groups, and what a row does.
///
/// Free of the views so a test can state the grouping without a window. The publication page
/// and the Kavita reading-list cover both build one, so the two cannot disagree about the
/// order.
struct CoverMenu {
    /// Whether there is artwork to put an edit button on.
    let hasCover: Bool

    /// The groups, top to bottom. A separator divides each pair.
    let rows: [[CoverMenuRow]]

    /// False when there is no title to search for, which is when the row refuses rather than
    /// opening an engine's front page.
    var webSearchEnabled = true

    let act: (CoverMenuRow) -> Void

    /// Where the menu is reached from.
    enum Placement: Equatable {
        /// A round button on the cover's corner, and a long press on the cover.
        case buttonOnCover
        /// A cover-shaped hole has no corner worth a button, so the hole is the menu.
        case coverlessWell
    }

    var placement: Placement { hasCover ? .buttonOnCover : .coverlessWell }

    /// The rows for what is on offer right now.
    ///
    /// Choosing comes first and removing comes last, alone in its own group: a destructive row
    /// is never beside the row a thumb is most likely to be aiming at.
    static func rows(find: Bool, web: Bool, send: Bool, remove: Bool) -> [[CoverMenuRow]] {
        var getting: [CoverMenuRow] = [.choose]
        if find { getting.append(.find) }
        if web { getting.append(.searchWeb) }
        if send { getting.append(.sendToServer) }
        return remove ? [getting, [.remove]] : [getting]
    }
}

/// The menu's rows. Both the edit button and the long press draw this, so they are one list.
struct CoverMenuRows: View {
    let menu: CoverMenu

    var body: some View {
        ForEach(Array(menu.rows.enumerated()), id: \.offset) { _, group in
            Section {
                ForEach(group, id: \.self) { row in
                    switch row {
                    case .choose:
                        item(.choose, symbol: "photo") {
                            Text(menu.hasCover ? "cover.change" : "cover.choose", bundle: .module)
                        }
                    case .find:
                        item(.find, symbol: "magnifyingglass") { Text("covers.find", bundle: .module) }
                    case .searchWeb:
                        // The arrow marks that the row leaves the app. The note says what the
                        // browser does and that StoryArc downloads nothing, as the text under
                        // the old button did.
                        item(.searchWeb, symbol: "arrow.up.right") {
                            Text("covers.web.search", bundle: .module)
                            Text("covers.web.note", bundle: .module)
                        }
                        .disabled(!menu.webSearchEnabled)
                    case .sendToServer:
                        item(.sendToServer, symbol: "icloud.and.arrow.up") {
                            Text("covers.writeBack", bundle: .module)
                        }
                    case .remove:
                        Button(role: .destructive) { menu.act(.remove) } label: {
                            Label { Text("cover.remove", bundle: .module) } icon: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private func item<Title: View>(
        _ row: CoverMenuRow, symbol: String, @ViewBuilder title: () -> Title
    ) -> some View {
        Button { menu.act(row) } label: {
            Label { title() } icon: { Image(systemName: symbol) }
        }
    }
}

/// The round glass button on the cover's corner.
///
/// 44 × 44 pt, the Human Interface Guidelines' hit region for a button, drawn on the same
/// glass as the rest of the chrome so Reduce Transparency and Increase Contrast give it the
/// opaque fallback.
struct CoverEditButton: View {
    let menu: CoverMenu

    var body: some View {
        Menu {
            CoverMenuRows(menu: menu)
        } label: {
            Image(systemName: "pencil")
                .font(.body.weight(.semibold))
                .storyArcGlassText(.primary)
                .frame(width: 44, height: 44)
                .storyArcGlass(in: Circle())
                .contentShape(Circle())
                // On the label, where the button inside the menu is, so that button carries
                // the name; the menu around it takes the same name from it.
                .accessibilityLabel(Text("cover.edit", bundle: .module))
        }
        .buttonStyle(.plain)
    }
}

/// The visible words for a cover that has none yet. A reader who meets a glyph is told what to
/// do about it rather than left to guess that the well can be pressed.
struct CoverAddMenu: View {
    let menu: CoverMenu

    var body: some View {
        Menu {
            CoverMenuRows(menu: menu)
        } label: {
            Label { Text("cover.add", bundle: .module) } icon: { Image(systemName: "photo.badge.plus") }
                .hitRegion()
                // Named on the label, as the edit button is: in a list row the menu answered
                // with the symbol's name, "photo.badge.plus" (task 26.6).
                .accessibilityLabel(Text("cover.add", bundle: .module))
        }
        .textRole(.subheadline)
    }
}

private struct CoverEditing: ViewModifier {
    let menu: CoverMenu?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let menu {
            switch menu.placement {
            case .buttonOnCover:
                content
                    .overlay(alignment: .bottomTrailing) {
                        CoverEditButton(menu: menu).padding(StoryArcSpace.sm)
                    }
                    .contextMenu { CoverMenuRows(menu: menu) }
            case .coverlessWell:
                // The visible "Add a cover" beside it is the control a screen reader reaches,
                // so the well is not announced a second time.
                Menu { CoverMenuRows(menu: menu) } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Puts the cover's menu on this artwork, or leaves it alone where the screen offers none.
    func coverEditing(_ menu: CoverMenu?) -> some View {
        modifier(CoverEditing(menu: menu))
    }

    /// Asks before the stored picture is deleted. Cancel keeps it.
    ///
    /// The dialog hangs on the screen and not on the menu: a menu is gone the moment a row is
    /// chosen, and takes anything attached to it along.
    func coverRemoval(asking: Binding<CoverMenuRow?>, remove: @escaping () -> Void) -> some View {
        confirmationDialog(
            Text("cover.remove.ask", bundle: .module),
            isPresented: asking.isAsking(.remove),
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: remove) {
                Text("cover.remove", bundle: .module)
            }
        } message: {
            Text("cover.remove.body", bundle: .module)
        }
    }
}

extension Binding where Value == CoverMenuRow? {
    /// A switch that is on while this row waits for an answer, and clears it when dismissed.
    func isAsking(_ row: CoverMenuRow) -> Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue == row },
            set: { if !$0, wrappedValue == row { wrappedValue = nil } }
        )
    }
}
