public import Foundation

internal import ReadiumNavigator
internal import ReadiumShared
public import SwiftUI

public import StoryArcCore

// What a reader marks, and how it is drawn back onto the page.
//
// `ebook-reader`: "highlight in several colours, add a note, copy, and search-in-publication
// are offered" on a selection, and "highlights and notes are listed in one place and
// exportable as plain text or Markdown". The record, the store and the two export documents
// are shared with the library; what is here is the half only a renderer can do — knowing
// what is selected, and painting the marks back over the words.
//
// Android's `EpubReaderViewModel` carries the same operations.

public extension EpubReaderModel {

    /// The group name Readium draws this app's highlights under.
    ///
    /// Its own group so a future one — a search hit, a spoken sentence — can be applied and
    /// withdrawn without touching what the reader made.
    private static var annotationGroup: String { "annotations" }

    /// Marks the current selection, or changes the colour of the mark already there.
    ///
    /// The words come from the selection rather than from the resource: this is the one
    /// place the renderer knows exactly what the reader meant, down to the character.
    func highlight(_ colour: HighlightColour) async {
        guard let store = annotationStore,
              let navigator = navigator as (any SelectableNavigator)?,
              let selection = navigator.currentSelection
        else { return }

        let text = selection.locator.text.highlight?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }

        annotations = store.save(
            Annotation(
                locator: (try? selection.locator.jsonString()) ?? "",
                resource: selection.locator.href.removingFragment().string,
                progression: totalProgression(of: selection.locator),
                chapter: selection.locator.title ?? chapterTitle ?? "",
                text: text,
                colour: colour,
                createdAt: Date()
            ),
            in: publication.id
        )
        navigator.clearSelection()
        self.selection = nil
        await drawAnnotations()
    }

    /// Writes on a mark, or replaces what was written.
    func annotate(_ annotation: Annotation, with note: String) async {
        guard let store = annotationStore else { return }
        annotations = store.save(
            Annotation(
                id: annotation.id,
                locator: annotation.locator,
                resource: annotation.resource,
                progression: annotation.progression,
                chapter: annotation.chapter,
                text: annotation.text,
                colour: annotation.colour,
                note: note,
                createdAt: annotation.createdAt
            ),
            in: publication.id
        )
        await drawAnnotations()
    }

    func removeAnnotation(_ id: UUID) async {
        guard let store = annotationStore else { return }
        annotations = store.remove(id, from: publication.id)
        await drawAnnotations()
    }

    /// Goes to a mark. The same journey a bookmark takes.
    func go(to annotation: Annotation) async {
        guard let navigator, let locator = try? Locator(jsonString: annotation.locator) else {
            return
        }
        markReturnPoint()
        _ = await navigator.go(to: locator, options: NavigatorGoOptions(animated: false))
    }

    /// Paints every mark this publication holds back onto the page.
    ///
    /// Declared wholesale rather than added one at a time: Readium diffs the group against
    /// what it is already showing and decides what to redraw, which is cheaper than this
    /// type guessing.
    func drawAnnotations() async {
        guard let navigator = navigator as (any DecorableNavigator)? else { return }
        navigator.apply(
            decorations: annotations.compactMap(decoration(for:)),
            in: Self.annotationGroup
        )
    }

    private func decoration(for annotation: Annotation) -> Decoration? {
        guard let locator = try? Locator(jsonString: annotation.locator) else { return nil }
        return Decoration(
            id: annotation.id.uuidString,
            locator: locator,
            style: .highlight(tint: UIColor(annotation.colour.swatch), isActive: false)
        )
    }
}

extension HighlightColour {
    /// What the colour looks like on a page.
    ///
    /// Fixed hues rather than palette tokens: a highlight is ink a reader chose, and one that
    /// changed colour when they changed theme would stop meaning what they meant by it. The
    /// opacity is what makes it legible over any of the six page colours — Readium composites
    /// this over the text, so a solid fill would bury the words it is marking.
    var swatch: SwiftUI.Color {
        switch self {
        case .yellow: SwiftUI.Color(red: 1.00, green: 0.85, blue: 0.25)
        case .green: SwiftUI.Color(red: 0.45, green: 0.85, blue: 0.45)
        case .blue: SwiftUI.Color(red: 0.40, green: 0.72, blue: 1.00)
        case .pink: SwiftUI.Color(red: 1.00, green: 0.55, blue: 0.75)
        case .purple: SwiftUI.Color(red: 0.72, green: 0.55, blue: 1.00)
        }
    }
}
