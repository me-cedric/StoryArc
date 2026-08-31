internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// What the reader offers over a PDF that carries text, and what it says about one that does
// not.
//
// `ebook-reader`: "WHEN a PDF contains a text layer THEN text selection, in-publication search,
// and the document outline work", and a PDF that is images only "is read with the image-reader
// behaviour of comic-reader, and text-dependent controls are hidden".
//
// Hidden, not disabled, and that is the whole shape of this file: every control below is built
// against `pdfText` being present. A comic never has one; a scan never has one; nothing is
// greyed out anywhere, because there is nothing to grey.
//
// The members are internal rather than private because `ReaderView.body` is in another file.
//
// Android's `PdfTextControls` offers the same set.
extension ReaderView {

    /// Everything the text layer puts on screen: the menu, the sheet, and the sentence.
    ///
    /// One overlay rather than three modifiers on the body, so `ReaderView` stays the screen's
    /// structure — the same reason the chrome and the containers live in their own files.
    @ViewBuilder
    var pdfTextControls: some View {
        ZStack(alignment: .bottom) {
            if let pdfText, let selection = pdfText.selection, !selection.text.isEmpty {
                PdfSelectionMenu(
                    text: selection.text,
                    onHighlight: { colour in Task { await pdfText.highlight(colour) } },
                    onNote: { markThenNote(in: pdfText) },
                    onCopy: { pdfText.copySelection() },
                    onSearch: { searchForSelection(in: pdfText) },
                    onDismiss: { pdfText.clearSelection() }
                )
                .padding(.bottom, StoryArcSpace.xl)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Built once the pages are there, because that is when the renderer exists and when
        // it can be asked whether the document has any text in it.
        .task(id: model.pages.count) { await preparePdfText() }
        // The marks on the page in front of the reader, resolved the first time it is shown.
        .task(id: model.currentIndex) { await pdfText?.resolveMarks(onPage: model.currentIndex) }
        .sheet(isPresented: $isFindingText) {
            if let pdfText {
                PdfTextSheet(model: pdfText, opensOn: findingTab) { page in goToPage(page) }
            }
        }
        .sheet(item: $noting) { annotation in
            if let pdfText {
                PdfNoteSheet(model: pdfText, annotation: annotation) { noting = nil }
            }
        }
        // A sentence rather than a control. There is no search box to explain, so this is the
        // only place a reader can learn that the file is a picture of a page.
        .alert(
            Text("reader.pdf.noText.title", bundle: .module),
            isPresented: $saysThereIsNoText
        ) {
            Button { saysThereIsNoText = false } label: {
                Text("reader.pdf.noText.done", bundle: .module)
            }
        } message: {
            Text("reader.pdf.noText.message", bundle: .module)
        }
    }

    /// Builds the text model, or leaves it absent for a publication that has no text.
    func preparePdfText() async {
        guard pdfText == nil, let pdf = model.pdf, pdf.hasTextLayer else { return }
        let created = PdfTextModel(
            renderer: pdf,
            store: annotations,
            publication: model.publication.id,
            title: model.publication.displayTitle
        )
        await created.load()
        pdfText = created
        await created.resolveMarks(onPage: model.currentIndex)
    }

    /// The marks and the live selection on one page, or nothing to draw.
    func decoration(at index: Int) -> PdfPageDecoration {
        guard let pdfText else { return .none }
        let selection = pdfText.selection
        return PdfPageDecoration(
            marks: pdfText.marks(onPage: index),
            selection: selection?.locator.page == index ? (selection?.rects ?? []) : []
        )
    }

    /// How a press-and-drag on one page is answered, or `nil` where there is nothing to select.
    ///
    /// A PDF that has no text still answers, once: the press is what a reader does when they
    /// expect to select, and silence there reads as a broken gesture rather than as a scan.
    func selectionHandler(at index: Int) -> ((CGPoint, CGPoint, Bool) -> Void)? {
        if let pdfText {
            return { from, to, _ in
                Task { await pdfText.select(onPage: index, from: from, to: to) }
            }
        }
        guard model.pdf != nil else { return nil }
        return { _, _, isFinished in
            guard isFinished else { return }
            saysThereIsNoText = true
        }
    }

    /// Marks the selection and opens somewhere to write on it.
    ///
    /// A note is a highlight with something written on it, so there is nothing to write on
    /// until the highlight exists. Marking in the first colour and opening the editor is the
    /// shortest honest path from "these words" to "and here is what I think of them"; a reader
    /// who wanted a different colour changes it in the list afterwards.
    private func markThenNote(in pdfText: PdfTextModel) {
        Task { noting = await pdfText.highlight(.yellow) }
    }

    /// Searches the publication for the words the reader selected.
    private func searchForSelection(in pdfText: PdfTextModel) {
        let words = pdfText.selection?.text ?? ""
        pdfText.clearSelection()
        findingTab = .search
        isFindingText = true
        Task { await pdfText.search(words) }
    }

    /// Turns to a hit or a mark. The same journey a slider drag takes, and it leaves the
    /// same way back — `ebook-reader` asks for one control after "a link, a table-of-contents
    /// entry, a bookmark, or a search result", because they are one act from the reader's side.
    private func goToPage(_ page: Int) {
        jump(to: page)
    }
}
