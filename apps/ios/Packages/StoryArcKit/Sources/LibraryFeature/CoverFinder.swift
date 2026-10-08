internal import SwiftUI

internal import Catalogue
internal import DesignSystem
internal import Formats
internal import StoryArcCore

/// Which ways of finding a cover the publication page offers.
///
/// Task 6.2 of `cover-for-every-publication`. The two ways ask different questions of the
/// reader's privacy, and that is why this is one value and not two booleans read where they
/// are drawn:
///
/// - **The title search** is this app asking three catalogues about the title, so it is
///   offered only while the lookup switch is on.
/// - **The web search** is the reader's browser asking, with no request from this app at
///   all, so it is offered whatever the switch says.
///
/// Android's `CoverFinderOffer` is its twin.
struct CoverFinderOffer: Equatable {
    let findACover: Bool
    let webSearch: Bool

    static func of(lookUpIsOn: Bool) -> CoverFinderOffer {
        CoverFinderOffer(findACover: lookUpIsOn, webSearch: true)
    }
}

extension LibraryModel {

    /// What the page offers right now, read from the setting at the moment the page is drawn.
    ///
    /// `rung` is the process's own. A test hands another, so it flips the switch without
    /// touching the one every other suite reads.
    func coverFinderOffer(through rung: CoverLookupRung = .live) -> CoverFinderOffer {
        .of(lookUpIsOn: rung.isEnabled())
    }

    /// The reader's tap on a candidate, as a stored cover.
    ///
    /// The one place a looked-up picture becomes a chosen cover. The picture is fetched
    /// through `client`, which checks the setting and the host, and stored through
    /// ``setCover(_:for:in:)``, which is the path the system picker already takes, so the
    /// crop to a cover's shape, the override store and the redraw of every copy are one set
    /// of lines.
    ///
    /// Nothing calls this until the reader taps. `cover-art`: the app "never silently adopts
    /// a match it is not certain of".
    ///
    /// - Returns: whether the picture was stored. False is a picture that did not arrive or
    ///   could not be used, and the page says so in the words it already uses for a picked
    ///   picture.
    func adoptCandidate(
        _ candidate: CoverCandidate,
        for publication: Publication,
        via client: CoverLookupClient,
        in overrides: CoverOverrideStore = CoverOverrideStore()
    ) async -> Bool {
        guard let picture = await client.image(at: candidate.imageURL) else { return false }
        return await setCover(picture, for: publication, in: overrides)
    }
}

/// The title search, its wait, and the candidates it finds.
///
/// A sheet over the publication page. It asks once when it opens and waits for the reader: a
/// candidate is adopted only by a tap on its row.
struct CoverFinderSheet: View {
    let publication: Publication
    let model: LibraryModel

    /// Called once with whether the tapped picture was stored.
    let onDone: (Bool) -> Void

    /// The one client that checks the setting and the host. The process's own by default.
    var client: CoverLookupClient = CoverLookupRung.live.client

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var found: [CoverCandidate]?

    var body: some View {
        NavigationStack {
            Group {
                if let found {
                    CoverCandidateSheet(candidates: found, onChoose: choose, client: client)
                } else {
                    VStack(spacing: StoryArcSpace.sm) {
                        ProgressView()
                        Text("covers.finding", bundle: .module)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(Text("covers.candidates", bundle: .module))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("shelves.cancel", bundle: .module) }
                }
            }
        }
        .task(id: publication.id) {
            found = await client.candidates(
                title: publication.displayTitle, author: publication.authors.first
            )
        }
    }

    private func choose(_ candidate: CoverCandidate) {
        Task {
            let stored = await model.adoptCandidate(candidate, for: publication, via: client)
            onDone(stored)
            dismiss()
        }
    }
}
