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

/// What the second pane says before a publication has been chosen.
///
/// One sentence, per `publication-detail`: not an arbitrary publication, and not an empty
/// rectangle. Kept beside the page rather than inside whichever container presents it, so a
/// split view and a stack that has been emptied show the same words.
public struct PublicationDetailPlaceholder: View {
    public init() {}

    public var body: some View {
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
