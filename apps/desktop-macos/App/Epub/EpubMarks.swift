import Foundation
import Observation
import Persistence
import StoryArcCore

/// A note the book points to, shown where the reader is rather than by leaving the page (`ebook-reader`,
/// *Following an internal link* for a footnote).
struct EpubFootnote: Equatable, Identifiable {
    let href: String
    let text: String
    var id: String { href }
}

/// What the reader chose with the pointer, waiting to become a highlight.
struct EpubSelection: Equatable {
    let text: String
    let locator: String
}

/// The reader's bookmarks and highlights in one EPUB, and what the renderer reports about them (`ebook-reader`,
/// *Bookmarks*, *Highlights and notes*). Kept in the phones' own stores, `BookmarkStore` and `AnnotationStore`,
/// under the publication's id, so the records have one shape on every Apple platform.
@MainActor
@Observable
final class EpubMarks {
    let publicationID: String
    private(set) var bookmarks: [Bookmark]
    private(set) var annotations: [Annotation]
    private(set) var selection: EpubSelection?
    var footnote: EpubFootnote?
    /// The highlight the reader clicked on the page, which the window offers to edit or remove.
    var activated: Annotation?
    private let bookmarkStore: BookmarkStore
    private let annotationStore: AnnotationStore

    /// The decorations the renderer last said it drew, by id.
    private(set) var drawn: [String] = []

    init(publicationID: String, defaults: UserDefaults = .standard) {
        self.publicationID = publicationID
        bookmarkStore = BookmarkStore(defaults: defaults)
        annotationStore = AnnotationStore(defaults: defaults)
        bookmarks = bookmarkStore.bookmarks(for: publicationID).inReadingOrder
        annotations = annotationStore.annotations(for: publicationID)
    }

    /// A renderer message the reading model does not handle itself.
    func receive(_ type: String, _ body: [String: Any]) {
        switch type {
        case "selection":
            let text = (body["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            selection = text.isEmpty ? nil : EpubSelection(text: text, locator: Self.json(body["locator"]) ?? "{}")
        case "footnote":
            guard let href = body["href"] as? String else { return }
            footnote = EpubFootnote(href: href, text: body["text"] as? String ?? "")
        case "highlight-activated":
            let id = (body["id"] as? String).flatMap(UUID.init(uuidString:))
            activated = annotations.first { $0.id == id }
        case "highlights":
            drawn = body["ids"] as? [String] ?? []
        default:
            break
        }
    }

    // MARK: - Bookmarks

    /// The bookmark at a place, if there is one.
    func bookmark(at place: EpubPlace) -> Bookmark? {
        bookmarks.mark(at: place.progression, in: place.resource)
    }

    /// Adds a bookmark at the place, or removes the one already there.
    func toggleBookmark(at place: EpubPlace, now: Date = .now) {
        let mark = bookmark(at: place) ?? Bookmark(
            locator: place.locator, resource: place.resource, progression: place.progression,
            chapter: place.chapter, excerpt: "", createdAt: now
        )
        bookmarks = bookmarkStore.toggle(mark, in: publicationID).inReadingOrder
    }

    func removeBookmark(_ id: UUID) {
        bookmarks = bookmarkStore.remove(id, from: publicationID).inReadingOrder
    }

    // MARK: - Highlights

    /// Turns the waiting selection into a highlight, in the colour chosen.
    @discardableResult
    func highlightSelection(_ colour: HighlightColour, chapter: String, now: Date = .now) -> Annotation? {
        guard let selection else { return nil }
        let place = EpubPlace(locator: selection.locator, chapter: chapter)
        let annotation = Annotation(
            locator: selection.locator, resource: place.resource, progression: place.progression,
            chapter: chapter, text: selection.text, colour: colour, note: "", createdAt: now
        )
        annotations = annotationStore.save(annotation, in: publicationID)
        self.selection = nil
        return annotation
    }

    /// Writes a note on a highlight; an empty note removes the note and keeps the highlight.
    func setNote(_ note: String, on id: UUID) {
        guard let annotation = annotations.first(where: { $0.id == id }) else { return }
        let edited = Annotation(
            id: annotation.id, locator: annotation.locator, resource: annotation.resource,
            progression: annotation.progression, chapter: annotation.chapter, text: annotation.text,
            colour: annotation.colour, note: note, createdAt: annotation.createdAt
        )
        annotations = annotationStore.save(edited, in: publicationID)
        if activated?.id == id { activated = edited }
    }

    func removeHighlight(_ id: UUID) {
        annotations = annotationStore.remove(id, from: publicationID)
        if activated?.id == id { activated = nil }
    }

    func dismissSelection() { selection = nil }

    /// The message that draws every highlight on the page; it replaces what the page had.
    var highlightsJSON: String { highlightsJSON(spoken: nil) }

    /// The highlights message, with the sentence the voice speaks as one more decoration in its own tint.
    func highlightsJSON(spoken: String?) -> String {
        var items = annotations.map { annotation in
            let id = annotation.id.uuidString
            return "{\"id\":\"\(id)\",\"locator\":\(annotation.locator),\"color\":\"\(annotation.colour.rawValue)\"}"
        }
        if let spoken {
            items.append("{\"id\":\"\(Self.spokenID)\",\"locator\":\(spoken),\"color\":\"\(Self.spokenTint)\"}")
        }
        return "{\"type\":\"highlights\",\"items\":[\(items.joined(separator: ","))]}"
    }

    /// The decoration of the sentence being spoken; never a reader's highlight, so activating it opens nothing.
    static let spokenID = "spoken"
    static let spokenTint = "lightskyblue"

    /// A sentence of a chapter, as a locator the renderer finds again by its text.
    static func spokenLocator(_ sentence: String, href: String) -> String? {
        let place: [String: Any] = ["href": href, "type": "application/xhtml+xml", "locations": [String: Any]()]
        return json(place.merging(["text": ["highlight": sentence]]) { first, _ in first })
    }

    static func json(_ object: Any?) -> String? {
        guard let object, JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Where a reader is, in the terms a bookmark and a highlight record: the resource, the progression within it, and
/// the chapter's name.
struct EpubPlace: Equatable {
    let locator: String
    let resource: String
    let progression: Double
    let chapter: String

    init(locator: String, chapter: String) {
        self.locator = locator
        self.chapter = chapter
        let object = (try? JSONSerialization.jsonObject(with: Data(locator.utf8))) as? [String: Any]
        resource = object?["href"] as? String ?? ""
        let locations = object?["locations"] as? [String: Any]
        progression = locations?["progression"] as? Double ?? 0
    }
}

extension EpubSearchHit {
    /// One search result as the renderer posts it.
    static func of(_ raw: [String: Any], id: Int) -> EpubSearchHit? {
        guard let locator = raw["locator"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: locator),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        let text = locator["text"] as? [String: Any]
        return EpubSearchHit(
            id: id,
            chapter: locator["title"] as? String,
            before: text?["before"] as? String ?? "",
            match: text?["highlight"] as? String ?? "",
            after: text?["after"] as? String ?? "",
            locator: json
        )
    }
}

extension EpubReaderModel {
    /// A move to another chapter that the app did not ask for is a link the reader followed in the book: the
    /// place it left becomes the way back (`ebook-reader`, *Following an internal link*, *Returning from any jump*).
    func noteJump(from previous: String?, to raw: [String: Any]) {
        defer { isMovingItself = false }
        guard !isMovingItself, let previous, isReady else { return }
        let before = EpubPlace(locator: previous, chapter: "").resource.split(separator: "#").first
        let after = (raw["href"] as? String)?.split(separator: "#").first
        guard let after, after != before else { return }
        returnLocator = previous
    }
}
