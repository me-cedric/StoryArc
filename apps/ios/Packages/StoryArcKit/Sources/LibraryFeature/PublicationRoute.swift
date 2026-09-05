public import SwiftUI

public import StoryArcCore

/// A publication's page, as a value a navigation stack can hold.
///
/// The identity rather than the ``Publication`` itself, for the reason ``LibraryView``
/// carries a `Source.ID` instead of a `Source`: a publication on the stack is re-read from
/// the model on every redraw, so a download that lands, a position that moves or a source
/// that is removed while the reader is on the page changes the page. A copy pushed onto the
/// stack would freeze all three at the moment of the tap.
///
/// One route type for every surface. A cover in the library, in a shelf, in search results
/// and in a collection all push the same value, which is what makes "the same page for
/// every kind of publication" a fact about the code rather than a promise in a document.
public struct PublicationRoute: Hashable, Sendable {
    /// ``Publication/id`` — the stable key ADR-0006 builds from whichever identity
    /// components exist.
    public let publicationID: String

    public init(_ publication: Publication) {
        publicationID = publication.id
    }

    public init(publicationID: String) {
        self.publicationID = publicationID
    }
}

extension View {
    /// Makes every ``PublicationRoute`` pushed onto the enclosing stack open the page.
    ///
    /// Attached once per navigation stack, beside whatever other destinations that stack
    /// has. A cover anywhere below it only has to push the route; it does not have to know
    /// what a publication's page is made of, which is what stops a second, slightly
    /// different detail screen from appearing on the next surface that wants one.
    ///
    /// Registered once and only once, deliberately. The series shelf on the page pushes the
    /// *same* route type, so the fourth issue of a run opens through this registration too
    /// — and back from it lands on the third rather than at the shelf, with no second
    /// destination to keep in step.
    ///
    /// - Parameters:
    ///   - onOpen: how this stack reaches the reader. The page knows which publication was
    ///     chosen and where its bytes are; it does not know what a reader is.
    ///   - onGone: called when the route names a publication the library can no longer
    ///     place — a stale shortcut, a removed source, a deleted file. The page dismisses
    ///     itself and hands the sentence back to the surface the reader came from, because
    ///     `publication-detail` requires them to be returned there rather than left on an
    ///     empty page. ``PublicationRoute/goneSentence`` is what to say.
    public func publicationDetail(
        model: LibraryModel,
        onOpen: @escaping (Publication, URL) -> Void,
        onGone: @escaping () -> Void = {}
    ) -> some View {
        navigationDestination(for: PublicationRoute.self) { route in
            PublicationDestination(route: route, model: model, onOpen: onOpen, onGone: onGone)
        }
    }

    /// The registration above, plus somewhere to put the sentence when a route resolves to
    /// nothing.
    ///
    /// What every surface actually wants, and the reason the destination modifier sat unused
    /// for a wave: on its own it hands `onGone` back to a caller that has no state to hold a
    /// sentence in, so each of the six stacks that show covers would have grown its own
    /// `@State` flag and its own alert. One modifier owns both halves instead, and a stack
    /// attaches the page in a single line.
    ///
    /// An alert rather than a banner because it is the answer to a tap that has already
    /// happened: `publication-detail` requires the reader to be "returned to the surface they
    /// came from with a plain sentence", and by the time it is shown they are back on that
    /// surface with nothing else to explain why. No new string ships for it —
    /// ``PublicationRoute/goneSentence`` is already translated, and the dismissal is the
    /// system's own.
    public func publicationPages(
        in model: LibraryModel,
        onOpen: @escaping (Publication, URL) -> Void
    ) -> some View {
        modifier(PublicationPages(model: model, onOpen: onOpen))
    }
}

/// Holds the one piece of state ``View/publicationPages(in:onOpen:)`` needs.
private struct PublicationPages: ViewModifier {
    let model: LibraryModel
    let onOpen: (Publication, URL) -> Void

    @State private var isGone = false

    func body(content: Content) -> some View {
        content
            .publicationDetail(model: model, onOpen: onOpen, onGone: { isGone = true })
            .alert(PublicationRoute.goneSentence, isPresented: $isGone) {}
    }
}

extension PublicationRoute {
    /// The plain sentence a surface shows when a page could not be opened.
    ///
    /// Here rather than in the caller so every surface says the same thing in the same four
    /// languages, and so `onGone` is a handler for *where* to put a sentence rather than an
    /// invitation to write one.
    public static var goneSentence: String {
        DetailStrings.text("detail.gone")
    }
}

/// Resolves one route against the library, and copes with it resolving to nothing.
private struct PublicationDestination: View {
    @Environment(\.dismiss) private var dismiss

    let route: PublicationRoute
    let model: LibraryModel
    let onOpen: (Publication, URL) -> Void
    let onGone: () -> Void

    var body: some View {
        if let publication = model.publications.first(where: { $0.id == route.publicationID }) {
            PublicationDetailView(publication: publication, model: model, onOpen: onOpen)
        } else {
            // Momentary, and it has to exist: `navigationDestination` has already committed
            // to showing something by the time this is known.
            Color.clear
                .task {
                    onGone()
                    dismiss()
                }
        }
    }
}

/// What the detail column says before a publication has been chosen.
///
/// **This was deleted on 2026-08-31 and is back with the pane it belongs to.** The tombstone
/// that stood here was right at the time and is worth keeping in one sentence: iOS had no
/// second pane, every sidebar row was its own `NavigationStack`, a row was always selected,
/// and so no state existed in which a pane waited for a cover. A placeholder for an
/// unreachable state is dead code, and this change's own problem was dead code.
///
/// What changed is the shelf, not the shell. ``LibraryView`` composes the Library destination
/// as a two-column `NavigationSplitView` — see ``LibraryView/container`` for why that is not
/// the "second, disagreeing navigation" the tombstone feared — so the detail column now has a
/// documented empty state and `publication-detail`'s *pane before anything is chosen* has
/// somewhere to be met.
///
/// **`detail.empty` is restored rather than written.** The same key, the same four
/// translations, still word for word what Android's `detail_pane_empty` says — so nothing
/// this pane shows is a new string for a translator to answer for.
///
/// A `ContentUnavailableView` rather than a centred `Text`, because the platform already
/// draws this shape and a reader has seen it in Mail and Notes: it is the pane saying it is
/// waiting, not the pane having failed.
struct PublicationDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("library.title", bundle: .module)
            } icon: {
                Image(systemName: "books.vertical")
            }
        } description: {
            Text("detail.empty", bundle: .module)
        }
    }
}
