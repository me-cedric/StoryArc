internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// Which sources earn a way to the rest of what they hold.
///
/// Two conditions, and both matter. The source must have held something back — a shelf
/// that has everything needs no footer. And it must have a browser of its own: a local
/// folder is walked by this app and a way into one would lead back to the grid the reader
/// is already looking at, which is the same reason ``SourceKind/hasItsOwnBrowser`` exists.
///
/// Pure, so the rule can be asserted without a shelf. ``MoreFromTheLibraryTests`` is that
/// assertion; Android's `sourcesWithMore` is the twin.
func sourcesWithMore(_ sources: [Source], isPartial: (UUID) -> Bool) -> [Source] {
    sources.filter { $0.kind.hasItsOwnBrowser && isPartial($0.id) }
}

/// The way to the rest of a library, at the foot of the shelf.
///
/// `library-browsing`: what a source holds beyond what the app has read is "reachable from
/// search and from an explicit *more from this library* affordance at the foot of the
/// shelf". Search was already the other half; this is the one a reader can see.
///
/// **An affordance that is always there says nothing**, so a shelf where every source gave
/// everything draws no footer at all. It leads to ``SourceShelfView``, which draws that
/// source's library rows with this grid's own cells. That is the clause this footer used to
/// miss: it opened the source's catalogue browser instead, and `library-browsing` asks those
/// publications to be "rendered by the same grid, the same cells and the same publication
/// page as everything else".
struct MoreFromTheLibrary: View {
    let sources: [Source]
    let isPartial: (UUID) -> Bool
    let onBrowse: (Source) -> Void

    var body: some View {
        let more = sourcesWithMore(sources, isPartial: isPartial)
        if !more.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(more) { source in
                    Button { onBrowse(source) } label: {
                        Text("library.moreFrom \(source.displayName)", bundle: .module)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .hitRegion(alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.vertical, StoryArcSpace.md)
        }
    }
}
