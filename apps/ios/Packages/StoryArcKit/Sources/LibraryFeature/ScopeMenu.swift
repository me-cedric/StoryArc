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

/// What the shelf is showing: on which availability, and — secondarily — from where.
///
/// One control with two pickers rather than two toolbar items, because they answer the same
/// question at two strengths. Availability is first and always offered; *From* appears only
/// when there is more than one library to choose between, and `library-browsing` is explicit
/// that it "does not survive as a mode" — it narrows the shelf and nothing else.
///
/// Before this it was a source selector alone: origin as a scope, which the same requirement
/// removed because "a scope is a mode a reader can be stuck in and it silently narrowed
/// search as well".
struct ScopeMenu: View {
    let model: LibraryModel

    /// The primary axis, owned by the screen so it survives the menu closing.
    @Binding var availability: LibraryAvailability

    /// The libraries worth putting in front of a reader, or nothing at all.
    ///
    /// Empty below two libraries: a picker offering "Any library" and the one there is asks
    /// a question with a single answer. Android gates its own selector on
    /// `attributesPublications`; this is the same gate, and keeping it here — beside the
    /// menu it governs — is what lets the toolbar and this view agree without either
    /// restating the rule.
    ///
    /// The registry's own order, because `SourceRegistry.scopes` makes that order meaningful
    /// and a selector that reshuffled it would undo an arrangement the reader made by hand.
    static func offered(in registry: SourceRegistry) -> [LibraryScope] {
        registry.attributesPublications ? registry.scopes : []
    }

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

            let libraries = Self.offered(in: model.registry)
            if !libraries.isEmpty {
                Divider()

                Picker(selection: scopeBinding) {
                    ForEach(libraries, id: \.self) { scope in
                        name(of: scope).tag(scope)
                    }
                } label: {
                    Text("library.availability.from", bundle: .module)
                }
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
        .accessibilityValue(spokenValue)
    }

    private var scopeBinding: Binding<LibraryScope> {
        Binding(get: { model.query.scope }, set: { model.query.scope = $0 })
    }

    /// Both halves, in the order the menu offers them, and the second only when it is set.
    private var spokenValue: Text {
        guard let library = model.registry.name(of: model.query.scope.sourceID) else {
            return Text(availability.titleKey, bundle: .module)
        }
        return Text(availability.titleKey, bundle: .module) + Text(", ") + Text(library)
    }

    /// What one library is called in the *From* picker.
    ///
    /// "Any library" rather than "Everywhere" for the unnarrowed case: the word now belongs
    /// to the availability axis above, and two rows reading "Everywhere" in one menu would
    /// be two different promises wearing one name.
    private func name(of scope: LibraryScope) -> Text {
        guard let name = model.registry.name(of: scope.sourceID) else {
            return Text("library.availability.from.all", bundle: .module)
        }
        return Text(name)
    }
}
