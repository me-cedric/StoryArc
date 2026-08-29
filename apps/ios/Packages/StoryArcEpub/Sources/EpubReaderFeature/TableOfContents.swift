internal import SwiftUI

internal import ReadiumNavigator
internal import ReadiumShared

internal import DesignSystem

// The publication's own navigation, and the sheet that shows it.
//
// A new file rather than a section of `ThemeSheet`: typography and navigation are
// two different questions, and `ThemeSheet.swift` is at the 400-line file cap.

/// One row of the navigation.
///
/// Flat, with a depth on each row, rather than a tree. `ebook-reader` asks for the
/// navigation "to its full depth", and a flat array is what a `List` scrolls
/// lazily — the depth is what draws the nesting back.
struct ContentsEntry: Identifiable {
    /// Its place in the flattened list. Stable for as long as the sheet lives,
    /// which is longer than it takes to tap a row.
    let id: Int
    let title: String?
    let depth: Int
    /// Where tapping the row goes. Readium's own `Link`, handed straight back to
    /// the navigator, so nothing here has to understand an EPUB fragment.
    let link: ReadiumShared.Link
    /// The resource the entry opens, without query or fragment.
    ///
    /// Held rather than derived per comparison: marking the current row walks every
    /// entry, and parsing the same URL on each pass buys nothing.
    let resource: String
    /// Whether the entry points at an anchor inside its resource rather than at the
    /// whole of it.
    ///
    /// The difference decides whether any row can claim the reader's place. See
    /// ``EpubReaderModel/currentEntry(in:)``.
    let isAnchor: Bool
}

extension EpubReaderModel {
    /// The publication's navigation, flattened.
    ///
    /// Readium's, not ours. ADR-0005 leaves the EPUB's structure to the engine, and
    /// the `toc` collection is already parsed by the time a navigator exists — so
    /// this reads it rather than opening the container a second time.
    var contents: [ContentsEntry] {
        guard let links = navigator?.publication.manifest.tableOfContents else { return [] }
        var rows: [ContentsEntry] = []
        Self.flatten(links, depth: 0, into: &rows)
        return rows
    }

    private static func flatten(
        _ links: [ReadiumShared.Link],
        depth: Int,
        into rows: inout [ContentsEntry]
    ) {
        for link in links {
            rows.append(
                ContentsEntry(
                    id: rows.count,
                    title: link.title,
                    depth: depth,
                    link: link,
                    resource: link.url().removingQuery().removingFragment().string,
                    isAnchor: link.url().fragment != nil
                )
            )
            flatten(link.children, depth: depth + 1, into: &rows)
        }
    }

    /// Which row the reader is inside, or `nil` when no row can honestly claim it.
    ///
    /// Matched on the resource, and then one more test that matters more than it looks.
    /// An entry pointing at the whole resource owns it, so that row is the reader's
    /// place. An entry pointing at an *anchor* inside the resource is one of several,
    /// and nothing in a locator says which anchor the reader has scrolled past — so
    /// none of them is marked.
    ///
    /// Without that test, a publication whose whole text is one content document —
    /// `book.xhtml#ch1`, `book.xhtml#ch2`, and so on — marks its first chapter
    /// wherever the reader actually is. A mark that is wrong everywhere is worse than
    /// no mark, because the reader cannot tell which it is.
    func currentEntry(in entries: [ContentsEntry]) -> ContentsEntry.ID? {
        guard let href = locator?.href.removingQuery().removingFragment().string else { return nil }
        guard let match = entries.first(where: { $0.resource == href }) else { return nil }
        return match.isAnchor ? nil : match.id
    }

    /// Jumps to a navigation entry.
    ///
    /// Not animated: a jump to another chapter has no page to slide, and Readium
    /// animating one would suggest the reader turned there.
    func go(to entry: ContentsEntry) async {
        markReturnPoint()
        _ = await navigator?.go(to: entry.link, options: NavigatorGoOptions(animated: false))
    }
}

/// The table of contents.
///
/// `ebook-reader`: "the publication's own navigation is shown to its full depth,
/// with the current position highlighted". Presented the way ``ThemeSheet`` is —
/// a popover the platform turns into a detented sheet on a phone — so the reader's
/// two panels open and close alike.
struct TableOfContentsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let model: EpubReaderModel

    /// Which third of the sheet is showing.
    ///
    /// `ebook-reader` puts bookmarks "alongside the table of contents", and searching inside
    /// the book is the third way of asking the same question — where in this book do I go.
    /// One sheet with a picker rather than three sheets, because a reader who opened the
    /// wrong one would have to close it to ask again.
    @State private var tab = Tab.contents

    fileprivate enum Tab: Hashable {
        case contents, bookmarks, search, annotations

        var title: LocalizedStringKey {
            switch self {
            case .contents: "contents.title"
            case .bookmarks: "bookmarks.title"
            case .search: "search.title"
            case .annotations: "annotations.title"
            }
        }
    }

    var body: some View {
        let entries = model.contents
        let current = model.currentEntry(in: entries)
        return NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach([Tab.contents, .bookmarks, .search, .annotations], id: \.self) { choice in
                        Text(choice.title, bundle: .module).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, StoryArcSpace.gutter)
                .padding(.bottom, StoryArcSpace.sm)

                switch tab {
                case .bookmarks:
                    BookmarkList(model: model) { bookmark in
                        Task {
                            await model.go(to: bookmark)
                            dismiss()
                        }
                    }
                case .search:
                    SearchInBook(model: model) { match in
                        Task {
                            await model.go(to: match)
                            dismiss()
                        }
                    }
                case .annotations:
                    AnnotationList(model: model) { annotation in
                        Task {
                            await model.go(to: annotation)
                            dismiss()
                        }
                    }
                case .contents:
                    rows(entries, current: current)
                }
            }
            .navigationTitle(Text(tab.title, bundle: .module))
            // Inline, matching the theme sheet. See the note there.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("contents.done", bundle: .module) }
                }
            }
        }
    }

    @ViewBuilder
    private func rows(_ entries: [ContentsEntry], current: ContentsEntry.ID?) -> some View {
        if entries.isEmpty {
            // Said, not shown as a blank sheet. Plenty of EPUBs declare no `toc`
            // collection at all, and an empty list reads as a broken reader.
            Text("contents.empty", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(StoryArcSpace.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(entries) { entry in
                ContentsRow(entry: entry, isCurrent: entry.id == current) {
                    // Closed before the jump, not after it. The move belongs to the
                    // model and outlives the sheet, and waiting for Readium to land
                    // would leave the reader looking at a list they have left.
                    dismiss()
                    Task { await model.go(to: entry) }
                }
            }
            .listStyle(.plain)
            // No fill of our own. A sheet on iOS 26 is already presented on Liquid
            // Glass and `native-experience` wants it "left untinted so it picks up
            // the page beneath it" — a `List`'s own background is opaque.
            .scrollContentBackground(.hidden)
        }
    }
}

/// One entry, at its depth, tappable.
private struct ContentsRow: View {
    @Environment(\.theme) private var theme

    let entry: ContentsEntry
    let isCurrent: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: StoryArcSpace.sm) {
                title
                    .textRole(.body)
                    // Weight as well as colour, and the tick beside it: where the
                    // reader is never rests on colour alone.
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? theme.accent : theme.palette.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: StoryArcSpace.sm)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent)
                }
            }
            // The nesting, as indentation. It is the only thing on the row that says
            // a section belongs to the chapter above it.
            .padding(.leading, CGFloat(entry.depth) * StoryArcSpace.lg)
            // A single line of text is shorter than the 44 pt touch floor by itself.
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // One control, not a title and a tick to swipe through separately.
        .accessibilityElement(children: .combine)
        // `.isSelected` is what *announces* the current chapter. The tick and the
        // weight are what show it.
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    /// The entry's own title, or a placeholder for one that has none.
    ///
    /// Readium leaves `title` optional because a navigation document may carry a
    /// link with no text, and a row with no words is a row nobody can aim at.
    private var title: Text {
        guard let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return Text("contents.untitled", bundle: .module) }
        return Text(title)
    }
}
