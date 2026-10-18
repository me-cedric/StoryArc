import DesignSystem
import StoryArcCore
import SwiftUI

extension EpubReaderModel {
    /// Where the reader is now, for a bookmark: the locator and the chapter it is in.
    var place: EpubPlace? {
        guard let locator else { return nil }
        let place = EpubPlace(locator: locator, chapter: "")
        let resource = place.resource.split(separator: "#").first
        let chapter = contents.first { $0.href.split(separator: "#").first == resource }
        return EpubPlace(locator: locator, chapter: chapter?.title ?? title ?? "")
    }

    /// Draws every highlight on the page; the message replaces what the page had.
    func syncHighlights() { send(json: marks.highlightsJSON) }

    /// Turns the waiting selection into a highlight and draws it.
    func highlightSelection(_ colour: HighlightColour) {
        let chapter = place?.chapter ?? title ?? ""
        marks.highlightSelection(colour, chapter: chapter)
        syncHighlights()
    }
}

/// The bookmark at the reader's place: filled when there is one (`ebook-reader`, *Bookmarks*).
struct EpubBookmarkButton: View {
    let model: EpubReaderModel

    var body: some View {
        let isMarked = model.place.flatMap { model.marks.bookmark(at: $0) } != nil
        Button {
            if let place = model.place { model.marks.toggleBookmark(at: place) }
        } label: {
            Label(isMarked ? "desktop.epub.bookmark.remove" : "desktop.epub.bookmark.add",
                  systemImage: isMarked ? "bookmark.fill" : "bookmark")
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .disabled(model.place == nil)
        .help(Text(isMarked ? "desktop.epub.bookmark.remove" : "desktop.epub.bookmark.add"))
    }
}

/// The bookmarks and highlights of the book, each a way to its place (`ebook-reader`, *Bookmarks*, *Highlights
/// and notes*).
struct EpubMarksMenu: View {
    let model: EpubReaderModel

    var body: some View {
        Menu {
            Section("desktop.epub.marks.bookmarks") {
                if model.marks.bookmarks.isEmpty { Text("desktop.epub.marks.noBookmarks") }
                ForEach(model.marks.bookmarks) { mark in
                    Button(mark.chapter.isEmpty ? String(localized: "desktop.epub.marks.untitled") : mark.chapter) {
                        model.go(to: mark.locator)
                    }
                }
            }
            Section("desktop.epub.marks.highlights") {
                if model.marks.annotations.isEmpty { Text("desktop.epub.marks.noHighlights") }
                ForEach(model.marks.annotations) { annotation in
                    Button(annotation.hasNote ? "\(annotation.text) — \(annotation.note)" : annotation.text) {
                        model.go(to: annotation.locator)
                    }
                }
            }
        } label: {
            Label("desktop.epub.marks", systemImage: "bookmark.square")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(Text("desktop.epub.marks"))
    }
}

/// The bar a selection raises: highlight in a colour, or let it go.
struct EpubSelectionBar: View {
    let model: EpubReaderModel

    var body: some View {
        HStack(spacing: 10) {
            Text("desktop.epub.highlight").scaledFont(.callout, weight: .medium)
            ForEach(HighlightColour.allCases, id: \.self) { colour in
                Button { model.highlightSelection(colour) } label: {
                    Circle().fill(Self.swatch(colour)).frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 24, minHeight: 24)
                .accessibilityLabel(Text(Self.nameKey(colour)))
            }
            Button("desktop.epub.highlight.cancel") { model.marks.dismissSelection() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .storyArcGlass(in: Capsule())
    }

    static func swatch(_ colour: HighlightColour) -> Color {
        switch colour {
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .pink: .pink
        case .purple: .purple
        }
    }

    static func nameKey(_ colour: HighlightColour) -> LocalizedStringKey {
        switch colour {
        case .yellow: "desktop.epub.highlight.yellow"
        case .green: "desktop.epub.highlight.green"
        case .blue: "desktop.epub.highlight.blue"
        case .pink: "desktop.epub.highlight.pink"
        case .purple: "desktop.epub.highlight.purple"
        }
    }
}

/// A footnote's text where the reader is, or a highlight's note to write.
struct EpubNoteSheet: View {
    let model: EpubReaderModel
    let annotation: Annotation
    @State private var note: String
    @Environment(\.dismiss) private var dismiss

    init(model: EpubReaderModel, annotation: Annotation) {
        self.model = model
        self.annotation = annotation
        _note = State(initialValue: annotation.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(annotation.text).scaledFont(.body).lineLimit(4)
            TextField("desktop.epub.note", text: $note, axis: .vertical).lineLimit(3...8)
            HStack {
                Button("desktop.epub.highlight.remove", role: .destructive) {
                    model.marks.removeHighlight(annotation.id)
                    model.syncHighlights()
                    dismiss()
                }
                Spacer()
                Button("desktop.epub.note.done") {
                    model.marks.setNote(note, on: annotation.id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
