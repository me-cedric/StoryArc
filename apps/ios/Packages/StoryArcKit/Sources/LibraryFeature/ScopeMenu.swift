public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// What the shelf is narrowed to, on the axis a reader actually asks about.
///
/// `library-browsing`: the library is narrowed by **availability** — everything, or only
/// what can be read with no network — "as its primary axis". Origin was the axis before,
/// and it was the wrong question: a reader on a train wants to know whether a book opens,
/// not which machine answered for it.
///
/// Held by ``LibraryView`` rather than by ``LibraryModel``: the model's `LibraryQuery` is
/// the contract both platforms share, and adding a case to it is a change to `StoryArcCore`
/// and to Android's mirror of it. This is one shelf choice with a `UserDefaults` key of its
/// own, which is what "the choice persists until changed" needs and no more.
enum LibraryAvailability: String, CaseIterable, Sendable {
    /// Everything the app holds metadata for, reachable or not.
    case everywhere
    /// Only what opens with no network at all.
    case onThisDevice

    /// Reuses "Everywhere", which the scope selector already said in four languages and
    /// which is the same promise on the new axis.
    var titleKey: LocalizedStringKey {
        switch self {
        case .everywhere: "library.scope.all"
        case .onThisDevice: "library.availability.onDevice"
        }
    }

    var symbolName: String {
        switch self {
        case .everywhere: "square.stack.3d.up"
        case .onThisDevice: "arrow.down.circle"
        }
    }

    /// Whether a publication at this location survives the narrowing.
    ///
    /// The same question ``LibrarySurface/onDevice`` asks, deliberately: everything the app
    /// can open from a file URL qualifies — a folder the reader picked as much as a
    /// download the app fetched — because a reader with no network does not care which of
    /// the two put the file there.
    func keeps(_ location: URL?) -> Bool {
        switch self {
        case .everywhere: true
        case .onThisDevice: location?.isFileURL == true
        }
    }

    /// Where the choice is written down. Its own key beside `LibraryPreferences`' keys, in
    /// the same `UserDefaults`, so nothing has to be migrated to add it.
    static let storageKey = "app.storyarc.libraryAvailability"

    /// Whether a publication can be opened right now.
    ///
    /// `library-browsing`: one that is neither on the device nor currently reachable "stays
    /// in the library, dimmed" — "never removed from the shelf, because a library that
    /// shrinks when the Wi-Fi drops reads as data loss". So this decides an opacity and
    /// never a filter, which is the distinction the requirement turns on.
    ///
    /// A publication no library claims is readable by definition: it came from a file
    /// another app handed over, and attributing it to whichever library happens to be down
    /// would be a guess that dimmed it for nothing.
    ///
    /// Static and free of the view for the reason the sectioning rule is: it is a decision,
    /// and a decision asked once per visible cell on every redraw is worth asserting
    /// directly rather than reading off a screenshot.
    static func isReadableNow(
        _ publication: Publication,
        location: URL?,
        registry: SourceRegistry
    ) -> Bool {
        if location?.isFileURL == true { return true }
        guard let id = publication.sourceID, let source = registry[id] else { return true }
        switch source.state {
        // `connecting` is not a verdict. The library probes every network source when it
        // appears, so treating "still asking" as "cannot be reached" would grey the whole
        // shelf on every launch and then un-grey it a second later — a flash that tells the
        // reader their library is broken and then that it is not.
        case .connected, .connecting: return true
        case .unreachable, .unauthorized: return false
        }
    }
}

/// What the shelf is showing, on the one axis that is a mode rather than a filter.
///
/// Everything, or only what opens with no network. `library-browsing` makes that the
/// library's primary axis and asks that the choice "persists until changed, **and is visible
/// while it is active**" — which is why this control's own icon states it, and why it is not
/// counted in the filter control's badge.
///
/// **It used to carry a second picker, *From*, and that was the defect.** Narrowing to one
/// library was written here as a scope: a mode with a control in the toolbar, which silently
/// narrowed the search as well and which nothing on screen offered to undo — the filter
/// menu's count did not know the field existed and *Clear filters* left it set. The amendment
/// to `library-browsing` is explicit that the narrowing "is offered by name as a filter …
/// and not as a scope the view is in", so it lives in ``FilterMenu`` now, counted and cleared
/// with everything else. Android moved it for the same reason and says so in its own
/// `FilterSection`.
struct ScopeMenu: View {
    /// The primary axis, owned by the screen so it survives the menu closing.
    @Binding var availability: LibraryAvailability

    var body: some View {
        Menu {
            Picker(selection: $availability) {
                ForEach(LibraryAvailability.allCases, id: \.self) { value in
                    Label {
                        Text(value.titleKey, bundle: .module)
                    } icon: {
                        Image(systemName: value.symbolName)
                    }
                    .tag(value)
                }
            } label: {
                Text("library.scope", bundle: .module)
            }
        } label: {
            Label {
                Text("library.scope", bundle: .module)
            } icon: {
                Image(systemName: availability.symbolName)
            }
        }
        // What it is narrowed to, spoken. The icon says that a narrowing is set and cannot
        // say which one, and DESIGN.md forbids a state carried by appearance alone.
        .accessibilityValue(Text(availability.titleKey, bundle: .module))
    }
}
