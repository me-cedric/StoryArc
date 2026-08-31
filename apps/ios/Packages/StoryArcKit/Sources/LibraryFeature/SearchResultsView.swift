internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// What one search found, wherever it was found.
///
/// **The screen the whole slice exists for.** There is one list, its headings say what the
/// match *is* — Titles, Series, People — and each row says which library supplied it.
/// `library-browsing`'s *Mixed local and server search* asks for exactly that: results
/// "merged into one ranked list, each labelled with its source". The label is the same
/// sentence the publication page's provenance line uses, in the reader's own name for the
/// library and nothing else about it.
///
/// It is drawn only where more than one place could have answered, which is
/// ``SearchListing/namesOrigin``'s rule — with one place the label is on every row and
/// distinguishes nothing from nothing.
///
/// Rows arrive in two waves: the device's own matches are here in the frame the reader typed
/// in, and a server's join when they arrive. No row is ever removed, replaced or reordered
/// against another — and a late row can still push a *later heading* down the screen. Exactly
/// what is and is not promised lives on ``SearchListing``, asserted on both platforms.
struct SearchResultsView: View {
    @Environment(\.theme) private var theme

    let listing: SearchListing

    // A row for a publication the library already holds leads to that publication's page,
    // and pushes the route itself — see ``row(_:)``. `publication-detail` names search among
    // the surfaces a cover leads from, and a result the device holds is that cover written
    // as a line.

    /// Goes to the library a row came from, carrying the term so it opens on the answer
    /// rather than at its front door.
    let onFollow: (SearchRoute) -> Void

    /// Asks a library that went quiet to try once more.
    let onRetry: (String) -> Void

    var body: some View {
        List {
            if listing.rows.isEmpty, !listing.isWaiting {
                // Named, per `library-browsing`: an empty state that does not say what was
                // searched for leaves a reader wondering whether the app heard them.
                Text("library.empty.search \(listing.term)", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                    .listRowBackground(theme.palette.surfaceCanvas)
            }

            ForEach(listing.groups) { group in
                Section {
                    ForEach(group.rows) { found in
                        row(found)
                    }
                } header: {
                    Text(group.kind.titleKey, bundle: .module)
                }
                // On the section, not on the list: a row paints its own background over the
                // scroll view's, so hiding the scroll view's alone left the headings on the
                // app's canvas and the rows on the system's white.
                .listRowBackground(theme.palette.surfaceCanvas)
            }

            // Last, under everything, and quiet. Both of these are the app talking about
            // itself, and neither is worth a row's worth of attention while there are
            // results above them to read.
            if listing.isWaiting {
                Label {
                    Text("search.waiting", bundle: .module)
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
                .listRowSeparator(.hidden)
                .listRowBackground(theme.palette.surfaceCanvas)
            }

            ForEach(listing.silent) { source in
                silentNotice(source)
            }
        }
        .listStyle(.plain)
        // The scroll view's own material, hidden so the app's canvas is what results sit on.
        // `native-experience` asks for the app's own surfaces, and the direction asks for a
        // room, not a form.
        .scrollContentBackground(.hidden)
        .background(theme.palette.surfaceCanvas)
    }

    /// One result.
    ///
    /// Three shapes, and the difference between them is only what happens on a tap: a book
    /// the device holds leads to its page; something a server has is followed to; a person or
    /// a tag is a name the server matched and goes nowhere, so it is not drawn as though it
    /// might.
    ///
    /// **A row a server answered is followed to that server, never to the publication page.**
    /// It has not been fetched, so the library holds no publication for it, and the page
    /// resolves against the library's own set — it would open on "this one is gone". The
    /// catalogue's own browser is where a remote entry is looked at and acquired.
    ///
    /// The route carries the identifier rather than the publication, which is all a result
    /// has: the page re-reads it from the model, so a row that has gone stale between the
    /// search and the tap resolves to nothing and says so, instead of opening a page about a
    /// publication the library no longer holds.
    ///
    /// The held row now draws the system's disclosure indicator and the followed row does
    /// not, which is a distinction worth having rather than one to hide: one pushes onto this
    /// stack and comes back, the other leaves for a server's own browser. See ``ListRow`` for
    /// why the indicator is kept.
    @ViewBuilder
    private func row(_ found: FoundRow) -> some View {
        if let held = found.result.publicationID {
            NavigationLink(value: PublicationRoute(publicationID: held)) { line(found) }
                .buttonStyle(.plain)
        } else if let route = found.result.route {
            Button { onFollow(route) } label: { line(found) }
                .buttonStyle(.plain)
        } else {
            line(found).foregroundStyle(theme.palette.textSecondary)
        }
    }

    private func line(_ found: FoundRow) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            Text(found.result.title)
                .foregroundStyle(theme.palette.textPrimary)
            if let detail = found.result.detail, !detail.isEmpty {
                // The series or the author — what tells a reader which "Volume 1" this is.
                Text(detail)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            if listing.namesOrigin {
                // The label the scenario asks for, under the row rather than beside it: a
                // library's name is as long as the reader made it, and a trailing label
                // would take its width from the title at the largest text size.
                Text(Self.label(found.origin))
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// Which library a row came from, in the reader's own words.
    ///
    /// The same two strings `DetailProvenanceLine` uses, resolved the same way — two
    /// spellings of "On this device" in one app is how a vocabulary drifts.
    private static func label(_ origin: SearchOrigin) -> String {
        switch origin {
        case let .library(_, name):
            String(localized: "library.cell.source \(name)", bundle: .module, locale: .storyArc)
        case .thisDevice:
            DetailStrings.text("source.onThisDevice")
        }
    }

    /// A library that could not answer, named once, with a way to try again.
    ///
    /// `sources`: an unreachable library "is grey, never red". It is a sentence at the foot
    /// of a list of results the reader can already use, not an alert over the top of them.
    private func silentNotice(_ source: SearchListing.SilentSource) -> some View {
        HStack {
            Text("search.silent \(source.name)", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
            Spacer()
            Button {
                onRetry(source.sourceID)
            } label: {
                Text("search.retry", bundle: .module).textRole(.footnote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.palette.accent)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(theme.palette.surfaceCanvas)
    }
}
