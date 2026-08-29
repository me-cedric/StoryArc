public import Foundation

/// A colour a reader can mark text in.
///
/// `ebook-reader` asks for "several colours" and does not name them. Five, because a
/// reader who is colour-coding needs enough to mean different things and few enough to
/// remember what each one meant — and because a row of five fits a selection menu without
/// becoming a palette. Named rather than stored as hex so a theme can render them legibly
/// against its own page colour: yellow on Paper and yellow on Focus are not the same yellow.
public enum HighlightColour: String, Sendable, Codable, CaseIterable {
    case yellow, green, blue, pink, purple
}

/// Something a reader marked in a publication, with or without a note attached.
///
/// `ebook-reader`: "highlight in several colours, add a note ... highlights and notes are
/// listed in one place and exportable as plain text or Markdown". One record for both,
/// because a note *is* a highlight with something written on it — two types would mean two
/// lists, and the spec asks for one.
///
/// Positioned the way ``Bookmark`` is and for the same reason (ADR-0006): a fraction through
/// the publication plus the renderer's own locator, which is the only thing that finds the
/// same words again after a type size has moved every page break.
///
/// Android's `Annotation` is the same record.
public struct Annotation: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    /// What the renderer is handed to draw it and to go back to it. Opaque on purpose.
    public let locator: String
    /// Which resource it is in, so two marks at the same fraction of different chapters
    /// are not mistaken for each other.
    public let resource: String
    /// How far through the whole publication, for ordering.
    public let progression: Double
    /// The chapter it falls in, as the publication's own navigation names it.
    public let chapter: String
    /// The words the reader selected.
    public let text: String
    public let colour: HighlightColour
    /// What the reader wrote, if anything. Empty is a highlight; non-empty is a note.
    public let note: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        locator: String,
        resource: String,
        progression: Double,
        chapter: String,
        text: String,
        colour: HighlightColour = .yellow,
        note: String = "",
        createdAt: Date
    ) {
        self.id = id
        self.locator = locator
        self.resource = resource
        self.progression = progression
        self.chapter = chapter
        self.text = text
        self.colour = colour
        self.note = note
        self.createdAt = createdAt
    }

    /// Whether the reader wrote something, as opposed to only marking the words.
    public var hasNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public extension Array where Element == Annotation {

    /// In book order, not the order they were made.
    ///
    /// The list is read as places in the publication, the way the bookmark list is.
    var inReadingOrder: [Annotation] {
        sorted { left, right in
            left.progression == right.progression
                ? left.createdAt < right.createdAt
                : left.progression < right.progression
        }
    }
}
