internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// Everything a reader marked in a PDF, in one place.
//
// `ebook-reader`: "highlights and notes are listed in one place and exportable as plain text
// or Markdown". One list, because a note is a highlight with something written on it — two
// lists would be the app insisting on a distinction the reader did not make.
//
// The record, the store and both export documents are the ones the EPUB reader writes. What is
// here is only the list, which is why a highlight made in a PDF comes out of the same export
// as one made in a novel.
//
// Android's `PdfMarkList` draws the same rows.
struct PdfMarkList: View {
    @Environment(\.theme) private var theme

    let model: PdfTextModel
    let onGo: (Int) -> Void

    @State private var editing: Annotation?
    @State private var note = ""

    var body: some View {
        if model.annotations.isEmpty {
            // Says what the control is rather than that there is nothing: a reader who has
            // never pressed on a word has no reason to know a menu appears when they do.
            Text("reader.pdf.marks.empty", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(StoryArcSpace.gutter)
        } else {
            List {
                ForEach(model.annotations) { annotation in
                    Button { jump(to: annotation) } label: { row(annotation) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await model.remove(annotation.id) }
                            } label: {
                                Label {
                                    Text("reader.pdf.marks.remove", bundle: .module)
                                } icon: {
                                    Image(systemName: "trash")
                                }
                            }
                            Button {
                                note = annotation.note
                                editing = annotation
                            } label: {
                                Label {
                                    Text("reader.pdf.note", bundle: .module)
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
                PdfNoteEditor(text: $note) {
                    Task { await model.annotate(annotation, with: note) }
                    editing = nil
                } cancel: {
                    editing = nil
                }
            }
        }
    }

    private func jump(to annotation: Annotation) {
        guard let page = model.page(of: annotation) else { return }
        onGo(page)
    }

    private func row(_ annotation: Annotation) -> some View {
        HStack(alignment: .top, spacing: StoryArcSpace.sm) {
            // The colour the reader chose, as a bar rather than a dot: it reads as the
            // highlight it stands for, and it is what makes a colour-coded list scannable.
            Capsule()
                .fill(annotation.colour.swatch)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(annotation.chapter)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
                Text(annotation.text)
                    .textRole(.footnote)
                    .lineLimit(3)
                if annotation.hasNote {
                    Text(annotation.note)
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// Both formats, side by side, because the spec offers both and a reader choosing one is
    /// choosing where they are about to paste it.
    private var exportBar: some View {
        HStack(spacing: StoryArcSpace.md) {
            ForEach(AnnotationExport.Format.allCases, id: \.self) { format in
                ShareLink(
                    item: AnnotationExport.document(
                        model.annotations,
                        title: model.title,
                        format: format
                    )
                ) {
                    Text(format.titleKey, bundle: .module)
                }
            }
        }
        .padding(StoryArcSpace.sm)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

extension AnnotationExport.Format {
    var titleKey: LocalizedStringKey {
        switch self {
        case .plainText: "reader.pdf.export.text"
        case .markdown: "reader.pdf.export.markdown"
        }
    }
}

/// The note editor, owning the draft it is editing.
///
/// Its own view rather than a binding held by the reader, because the draft belongs to the
/// sheet: it exists while the sheet is open and it is gone when the sheet closes, which is
/// exactly the lifetime of a `@State` inside it.
struct PdfNoteSheet: View {
    let model: PdfTextModel
    let annotation: Annotation
    let onClose: () -> Void

    @State private var text: String = ""

    var body: some View {
        PdfNoteEditor(text: $text) {
            Task { await model.annotate(annotation, with: text) }
            onClose()
        } cancel: {
            onClose()
        }
        .onAppear { text = annotation.note }
    }
}

/// Somewhere to write, and two ways out of it.
struct PdfNoteEditor: View {
    @Binding var text: String
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding(StoryArcSpace.gutter)
                .navigationTitle(Text("reader.pdf.note", bundle: .module))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: cancel) {
                            Text("reader.pdf.note.cancel", bundle: .module)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: save) {
                            Text("reader.pdf.note.save", bundle: .module)
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}
