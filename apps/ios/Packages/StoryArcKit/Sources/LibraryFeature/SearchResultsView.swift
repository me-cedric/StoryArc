internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// What one search found, wherever it was found.
///
/// **The screen the whole slice exists for.** There is one list, its headings say what the
/// match *is* — Titles, Series, People — and nothing on it says which library answered.
/// `library-browsing` is explicit that "no result is labelled with the source that supplied
/// it", and the reason is the point of the revamp: a reader with a folder, a server and a
/// catalogue has one library, and being asked to remember which of the three a book is in is
/// exactly the file-manager thinking the direction throws out.
///
/// Rows arrive in two waves and the list does not notice the difference: the device's own
/// matches are here in the frame the reader typed in, and a server's join underneath when
/// they arrive. Nothing above them moves — that promise lives in ``SearchAnswers`` and is
/// asserted there, on both platforms.
struct SearchResultsView: View {
    @Environment(\.theme) private var theme

    let answers: SearchAnswers

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
            if answers.results.isEmpty, !answers.isWaiting {
                // Named, per `library-browsing`: an empty state that does not say what was
                // searched for leaves a reader wondering whether the app heard them.
                Text("library.empty.search \(answers.term)", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                    .listRowBackground(theme.palette.surfaceCanvas)
            }

            ForEach(answers.groups) { group in
                Section {
                    ForEach(group.results) { result in
                        row(result)
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
            if answers.isWaiting {
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

            ForEach(answers.silent) { source in
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
    /// The route carries the identifier rather than the publication, which is all a result
    /// has: the page re-reads it from the model, so a row that has gone stale between the
    /// search and the tap resolves to nothing and says so, instead of opening a page about a
    /// publication the library no longer holds.
    @ViewBuilder
    private func row(_ result: SearchResult) -> some View {
        if let held = result.publicationID {
            NavigationLink(value: PublicationRoute(publicationID: held)) { line(result) }
                .buttonStyle(.plain)
        } else if let route = result.route {
            Button { onFollow(route) } label: { line(result) }
                .buttonStyle(.plain)
        } else {
            line(result).foregroundStyle(theme.palette.textSecondary)
        }
    }

    private func line(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            Text(result.title)
                .foregroundStyle(theme.palette.textPrimary)
            if let detail = result.detail, !detail.isEmpty {
                // The series or the author — what tells a reader which "Volume 1" this is.
                // Never the library it came from.
                Text(detail)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// A library that could not answer, named once, with a way to try again.
    ///
    /// `sources`: an unreachable library "is grey, never red". It is a sentence at the foot
    /// of a list of results the reader can already use, not an alert over the top of them.
    private func silentNotice(_ source: SearchAnswers.SilentSource) -> some View {
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
