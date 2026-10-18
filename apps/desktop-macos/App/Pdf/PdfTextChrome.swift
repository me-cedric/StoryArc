import AppKit
import DesignSystem
import Formats
import StoryArcCore
import SwiftUI

/// The marks and the live selection, drawn over one page and under nothing.
///
/// A port of `PdfPageOverlayView` to the Mac: the marks in their colours at the opacity the
/// EPUB renderer composites at, the selection in the system's own selection colour, because
/// it is not a mark yet. Drawn in the slot that fits the page, through `PdfPageGeometry`, so
/// it sits on the words whatever size the page is drawn at. Task 4.6.
struct MacPdfOverlay: View {
    let imageSize: CGSize
    let marks: [MacPdfMark]
    let selection: [CGRect]

    private static let markOpacity = 0.38
    private static let selectionOpacity = 0.32

    var body: some View {
        Canvas { context, size in
            for mark in marks {
                let rect = PdfPageGeometry.viewRect(mark.rect, imageSize: imageSize, in: size)
                let ink = Color(nsColor: NSColor(mark.colour.swatch)).opacity(Self.markOpacity)
                context.fill(Path(rect), with: .color(ink))
            }
            let colour = Color(nsColor: .selectedTextBackgroundColor).opacity(Self.selectionOpacity)
            for rect in selection {
                context.fill(Path(PdfPageGeometry.viewRect(rect, imageSize: imageSize, in: size)), with: .color(colour))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The menu a PDF selection gets: highlight in five colours, a note, copy, and search for the
/// words. The same four a reflowable selection offers, in the same order (`ebook-reader`,
/// *Text-based PDF*). On glass at the foot, because the words may be on a zoomed page.
struct MacPdfSelectionMenu: View {
    let text: MacPdfText
    let onSearch: (String) -> Void
    @State private var noting: Annotation?
    @State private var note = ""

    var body: some View {
        if let selection = text.selection, !selection.text.isEmpty {
            VStack(spacing: 8) {
                Text(selection.text).scaledFont(.callout).lineLimit(2).storyArcGlassText(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    ForEach(HighlightColour.allCases, id: \.self) { colour in
                        Button { Task { await text.highlight(colour) } } label: {
                            Circle().fill(colour.swatch).frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
                                .hitTarget()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(colour.titleKey))
                        .help(Text(colour.titleKey))
                    }
                    Divider().frame(height: 16)
                    action("desktop.pdf.note", "square.and.pencil") { Task { noting = await text.highlight(.yellow) } }
                    action("desktop.pdf.copy", "doc.on.doc") { text.copySelection() }
                    action("desktop.pdf.searchSelection", "magnifyingglass") {
                        let words = selection.text
                        text.clearSelection()
                        onSearch(words)
                    }
                    Spacer()
                    action("desktop.pdf.deselect", "xmark") { text.clearSelection() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .storyArcGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 48)
            .sheet(item: $noting) { annotation in
                VStack(spacing: 16) {
                    Text("desktop.pdf.note.prompt").scaledFont(.headline)
                    TextField("desktop.pdf.note", text: $note, axis: .vertical).lineLimit(3...6).frame(width: 320)
                    HStack {
                        Button(role: .cancel) { noting = nil } label: { Text("desktop.sheet.cancel") }
                            .keyboardShortcut(.cancelAction)
                        Button {
                            Task { await text.annotate(annotation, with: note) }
                            noting = nil
                        } label: { Text("desktop.pdf.note.save") }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(24)
                .onDisappear { note = "" }
            }
        }
    }

    private func action(_ key: LocalizedStringKey, _ symbol: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Label(key, systemImage: symbol).labelStyle(.iconOnly).hitTarget() }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(key))
            .help(Text(key))
    }
}

/// Search in the document: the field, the hits in context, and the cap when it was reached.
struct MacPdfSearchPanel: View {
    let text: MacPdfText
    @Binding var query: String
    let onGo: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("desktop.pdf.search.prompt", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await text.search(query) } }
                .accessibilityLabel(Text("desktop.pdf.search"))
            if text.isSearching {
                Text("desktop.epub.search.searching").scaledFont(.callout).foregroundStyle(.secondary)
            } else if text.hits.isEmpty, !query.isEmpty {
                Text("desktop.epub.search.none").scaledFont(.callout).foregroundStyle(.secondary)
            }
            if !text.hits.isEmpty {
                List(text.hits) { hit in
                    Button { onGo(hit.page) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MacPdfText.chapter(ofPage: hit.page)).scaledFont(.caption).foregroundStyle(.secondary)
                            (Text(hit.snippet.before) + Text(hit.snippet.match).bold() + Text(hit.snippet.after))
                                .scaledFont(.callout).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(hit.snippet.before) \(hit.snippet.match) \(hit.snippet.after)"))
                }
                .listStyle(.plain)
                .frame(minHeight: 160)
                if text.isCapped {
                    Text("desktop.pdf.capped \(PdfTextSearch.matchLimit)")
                        .scaledFont(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: 340)
    }
}

extension HighlightColour {
    /// Named, not described: a screen reader saying "yellow" is what a reader picking a colour needs.
    var titleKey: LocalizedStringKey {
        switch self {
        case .yellow: "desktop.pdf.colour.yellow"
        case .green: "desktop.pdf.colour.green"
        case .blue: "desktop.pdf.colour.blue"
        case .pink: "desktop.pdf.colour.pink"
        case .purple: "desktop.pdf.colour.purple"
        }
    }
}
