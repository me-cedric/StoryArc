internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// The places a reader marked, beside the publication's own navigation.
//
// `ebook-reader` puts bookmarks "alongside the table of contents", so they share the one
// sheet and differ only by which segment is showing. Android's `Bookmarks` draws the same
// rows into the same sheet, behind a tab rather than a picker, because that is where an
// Android reader looks for the same thing.

/// One publication's marks, in book order.
struct BookmarkList: View {
    @Environment(\.theme) private var theme

    let model: EpubReaderModel
    let onGo: (Bookmark) -> Void

    var body: some View {
        if model.bookmarks.isEmpty {
            // Says what the control is rather than that there is nothing, because a reader
            // who has never pressed it has no reason to know where it lives.
            Text("bookmarks.empty", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(StoryArcSpace.gutter)
        } else {
            List {
                ForEach(model.bookmarks) { bookmark in
                    Button { onGo(bookmark) } label: { row(bookmark) }
                        .buttonStyle(.plain)
                }
                // The platform's own delete rather than a button on every row: a swipe is
                // where an iOS reader removes a row, and a trailing button on each would
                // crowd the excerpt the row exists to show.
                .onDelete { offsets in
                    for index in offsets { model.removeBookmark(model.bookmarks[index].id) }
                }
            }
            .listStyle(.plain)
        }
    }

    private func row(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            Text(bookmark.chapter.isEmpty
                ? String(localized: "bookmarks.unnamed", bundle: .module, locale: .storyArc)
                : bookmark.chapter)
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(1)

            // Only when there is one. An empty second line would leave the rows different
            // heights for a reason the reader cannot see.
            if !bookmark.excerpt.isEmpty {
                Text(bookmark.excerpt)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
