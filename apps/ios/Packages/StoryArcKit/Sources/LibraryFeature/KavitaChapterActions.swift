internal import SwiftUI

import Kavita
internal import Persistence
import StoryArcCore

/// `KavitaChapterList`'s own context menu, split out once it reached this file's own cap —
/// the same seam `CoverCell.swift` and `PublicationActionMenu.swift` already made between a
/// cell and what a long press on it offers.
///
/// `library-browsing`'s *A publication's actions wherever it is drawn* names "a server's own
/// browser" among the places this menu belongs. `Open`, `Keep`, `Mark read` and `Add to
/// list` all ask the server or the cache directly, by this chapter's own identity, so they
/// stand whether or not the unified library has indexed this series yet. `Start from the
/// beginning` and `Show details` go through `LibraryModel`, which answers only for a
/// publication it already holds — see ``KavitaChapterList/known(_:)`` — so they are offered
/// only then, rather than drawn for a tap that would carry out nothing.
extension KavitaChapterList {
    @ViewBuilder
    func actions(for chapter: KavitaChapter) -> some View {
        openAction(for: chapter)
        keepAction(for: chapter)
        markAction(for: chapter)
        addToListActions(for: chapter)
        knownActions(for: chapter)
    }

    private func openAction(for chapter: KavitaChapter) -> some View {
        Button {
            Task { await open(chapter) }
        } label: {
            Label(
                String(localized: "library.action.open", bundle: .module, locale: .storyArc),
                systemImage: "arrow.up.forward.app"
            )
        }
        .disabled(fetching != nil)
    }

    /// `kavita-server` has a scenario about opening "a downloaded Kavita publication"
    /// offline, and until this there was no way to have one: the browser wrote every
    /// chapter to the caches directory. This is the asking.
    private func keepAction(for chapter: KavitaChapter) -> some View {
        Button {
            Task { await keep(chapter) }
        } label: {
            Label(
                String(localized: "kavita.keep", bundle: .module, locale: .storyArc),
                systemImage: "arrow.down.circle"
            )
        }
        .disabled(kept.contains(chapter.id))
    }

    private func markAction(for chapter: KavitaChapter) -> some View {
        Button {
            Task { await mark(chapter, read: !chapter.isFinished) }
        } label: {
            Label(
                chapter.isFinished
                    ? String(localized: "library.mark.unread", bundle: .module, locale: .storyArc)
                    : String(localized: "library.mark.read", bundle: .module, locale: .storyArc),
                systemImage: chapter.isFinished ? "circle" : "checkmark.circle"
            )
        }
    }

    /// Only this server's own lists: a Kavita list can hold nothing else, and offering
    /// another server's would be offering a refusal.
    @ViewBuilder
    private func addToListActions(for chapter: KavitaChapter) -> some View {
        ForEach(lists.filter { $0.server.id == sourceId }) { list in
            Button {
                Task { await add(chapter, to: list) }
            } label: {
                Label(
                    String(
                        format: String(localized: "kavita.addToList %@", bundle: .module, locale: .storyArc),
                        list.title
                    ),
                    systemImage: "text.append"
                )
            }
        }
    }

    /// *Start from the beginning* and *Show details*, offered only once ``known(_:)``
    /// resolves — see this file's own header.
    @ViewBuilder
    private func knownActions(for chapter: KavitaChapter) -> some View {
        if let known = known(chapter) {
            if RestartOffer.isOffered(
                publicationCount: 1,
                hasSomethingToClear: model.finishedPublications.contains(known.id)
                    || model.readFraction(of: known) != nil,
                isWired: true
            ) {
                Button {
                    restarting = known
                } label: {
                    Label(
                        String(localized: "library.restart", bundle: .module, locale: .storyArc),
                        systemImage: "arrow.counterclockwise"
                    )
                }
            }

            NavigationLink(value: PublicationRoute(known)) {
                Label(
                    String(localized: "library.action.showDetails", bundle: .module, locale: .storyArc),
                    systemImage: "info.circle"
                )
            }
        }
    }

    /// The same publication the unified library would hold for this chapter, when it
    /// already does — see this screen's own `model` header.
    /// ``knownKavitaChapter(sourceId:series:chapter:in:)``, lifted out so a test can reach it
    /// without rendering the row.
    private func known(_ chapter: KavitaChapter) -> Publication? {
        knownKavitaChapter(sourceId: sourceId, series: series, chapter: chapter, in: model.publications)
    }
}

/// Which publication a browsed Kavita chapter's full menu acts on, or `nil` when this device
/// has browsed to it but never indexed it — see ``KavitaChapterList``'s own header.
///
/// Internal, not private: a view body is not somewhere this can be asserted, and
/// `KnownKavitaChapterTests` is where an indexed chapter and an unindexed one are told
/// apart, and an unparseable source id is told from both.
func knownKavitaChapter(
    sourceId: String,
    series: KavitaSeries,
    chapter: KavitaChapter,
    in publications: [Publication]
) -> Publication? {
    guard let sourceUUID = UUID(uuidString: sourceId) else { return nil }
    let candidate = KavitaContributor.publication(source: sourceUUID, series: series, chapter: chapter)
    return publications.first { $0.id == candidate.id }
}
