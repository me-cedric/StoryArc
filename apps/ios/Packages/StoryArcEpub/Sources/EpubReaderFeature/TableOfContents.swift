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
                    resource: link.url().removingQuery().removingFragment().string
                )
            )
            flatten(link.children, depth: depth + 1, into: &rows)
        }
    }

    /// Which row the reader is inside, or `nil` when the navigation does not name
    /// the resource they are in.
    ///
    /// Matched on the resource alone. Where a publication lists several entries
    /// inside one resource, the first of them is marked: an entry carries a fragment
    /// but no position, so which of them the reader has scrolled past is not a
    /// question Readium can answer. And a resource the navigation never names marks
    /// nothing, rather than marking a neighbour that is not where the reader is.
    func currentEntry(in entries: [ContentsEntry]) -> ContentsEntry.ID? {
        guard let href = locator?.href.removingQuery().removingFragment().string else { return nil }
        return entries.first { $0.resource == href }?.id
    }

    /// Jumps to a navigation entry.
    ///
    /// Not animated: a jump to another chapter has no page to slide, and Readium
    /// animating one would suggest the reader turned there.
    func go(to entry: ContentsEntry) async {
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

    var body: some View {
        let entries = model.contents
        let current = model.currentEntry(in: entries)
        return NavigationStack {
            rows(entries, current: current)
                .navigationTitle(Text("contents.title", bundle: .module))
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
                    Task {
                        await model.go(to: entry)
                        dismiss()
                    }
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
