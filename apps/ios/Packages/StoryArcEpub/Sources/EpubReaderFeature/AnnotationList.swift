internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// Everything a reader marked, in one place.
//
// `ebook-reader`: "highlights and notes are listed in one place and exportable as plain text
// or Markdown". One list, because a note is a highlight with something written on it — two
// lists would be the app insisting on a distinction the reader did not make.
//
// Android's `Annotations` draws the same rows.

/// One publication's marks, in book order, with the export the spec asks for.
struct AnnotationList: View {
    @Environment(\.theme) private var theme

    let model: EpubReaderModel
    let onGo: (Annotation) -> Void

    @State private var editing: Annotation?
    @State private var note = ""

    var body: some View {
        if model.annotations.isEmpty {
            // Says what the control is rather than that there is nothing: a reader who has
            // never selected a word has no reason to know a menu appears when they do.
            Text("annotations.empty", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(StoryArcSpace.gutter)
        } else {
            List {
                ForEach(model.annotations) { annotation in
                    Button { onGo(annotation) } label: { row(annotation) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await model.removeAnnotation(annotation.id) }
                            } label: {
                                Label {
                                    Text("annotations.remove", bundle: .module)
                                } icon: {
                                    Image(systemName: "trash")
                                }
                            }
                            Button {
                                note = annotation.note
                                editing = annotation
                            } label: {
                                Label {
                                    Text("annotations.note", bundle: .module)
                                } icon: {
                                    Image(systemName: "square.and.pencil")
                                }
                            }
                        }
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .bottom) { exportBar }
            .sheet(item: $editing) { annotation in
                NoteEditor(text: $note) {
                    Task { await model.annotate(annotation, with: note) }
                    editing = nil
                } cancel: {
                    editing = nil
                }
            }
        }
    }

    /// Both formats, side by side, because the spec offers both and a reader choosing one
    /// is choosing where they are about to paste it.
    private var exportBar: some View {
        HStack(spacing: StoryArcSpace.md) {
            ForEach(AnnotationExport.Format.allCases, id: \.self) { format in
                ShareLink(item: AnnotationExport.document(
                    model.annotations,
                    title: model.publication.displayTitle,
                    format: format
                )) {
                    Text(format.titleKey, bundle: .module)
                        .textRole(.footnote)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(StoryArcSpace.md)
    }

    private func row(_ annotation: Annotation) -> some View {
        HStack(alignment: .top, spacing: StoryArcSpace.sm) {
            // The colour as a rule down the side rather than a dot: it is the mark's
            // identity, and a reader scanning the list is looking for "the green ones".
            Capsule()
                .fill(annotation.colour.swatch)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                if !annotation.chapter.isEmpty {
                    Text(annotation.chapter)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                }
                Text(annotation.text)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(3)
                if annotation.hasNote {
                    Text(annotation.note)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

extension AnnotationExport.Format {
    var titleKey: LocalizedStringKey {
        switch self {
        case .plainText: "annotations.export.text"
        case .markdown: "annotations.export.markdown"
        }
    }
}

/// Writing on a mark.
///
/// Internal rather than private: the selection menu's "Note" lands here directly, and
/// that menu lives in the reader view rather than in this list.
struct NoteEditor: View {
    @Environment(\.theme) private var theme

    @Binding var text: String
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding(StoryArcSpace.md)
                .navigationTitle(Text("annotations.note", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: cancel) { Text("annotations.cancel", bundle: .module) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: save) { Text("annotations.save", bundle: .module) }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}
