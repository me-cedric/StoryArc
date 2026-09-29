internal import SwiftUI

internal import DesignSystem
internal import Persistence
internal import StoryArcCore

/// The page bookmarks of a fixed-page publication with no text layer — a comic, or a
/// scan (D8). PDF's own marks keep `PdfMarkList`; this is what a reader sees instead
/// when there are no words to have selected one from.
///
/// Reads and writes ``AnnotationStore`` directly rather than through a model class:
/// there is no renderer here to hold marks against, the way `PdfTextModel` holds them
/// against page rectangles, so there is nothing a model would do beyond this view's
/// own `@State`.
struct ComicBookmarkList: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let store: AnnotationStore?
    let publication: String
    let onGo: (Int) -> Void

    @State private var annotations: [Annotation] = []

    var body: some View {
        NavigationStack {
            Group {
                if annotations.isEmpty {
                    Text("reader.bookmark.empty", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(StoryArcSpace.gutter)
                } else {
                    List {
                        ForEach(annotations) { annotation in
                            Button {
                                // Jumps, then gets out of the way — the page it jumped to
                                // is behind this sheet. `PdfTextSheet` does the same.
                                ComicPageBookmark.pageIndex(of: annotation).map(onGo)
                                dismiss()
                            } label: {
                                Text(annotation.text)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { remove(annotation) } label: {
                                    Label {
                                        Text("reader.pdf.marks.remove", bundle: .module)
                                    } icon: {
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(Text(LocalizedStringKey(ReaderMenuEntry.bookmarks.titleKey), bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("reader.pdf.done", bundle: .module) }
                }
            }
        }
        .task { annotations = (store?.annotations(for: publication) ?? []) }
    }

    private func remove(_ annotation: Annotation) {
        guard let store else { return }
        annotations = store.remove(annotation.id, from: publication)
    }
}
