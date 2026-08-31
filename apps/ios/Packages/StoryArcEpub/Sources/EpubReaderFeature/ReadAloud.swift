public import Foundation

public import StoryArcCore

// What reading aloud is, with no engine in it — and only the part of it that is the
// *reader's*.
//
// **Most of this file moved to `Playback`.** The pause table, the interruption outcome, the
// handover, the book being played, the lock-screen label and the compact bar's contents
// were all written here for the speech synthesizer, and `audiobooks-and-playback` asks for
// one player behind both a narrator and a synthesised voice. The first thing those two
// share is exactly this decision — what a *pause* means, and whether the end of an
// interruption starts the audio again — so the types moved rather than being copied. A
// second copy is a copy that can drift, and the interruption rule is the one nobody would
// notice drifting until a book started talking on its own during a phone call.
//
// What is left here is what a narrator has no equivalent of: the colour the *spoken
// sentence* is drawn in, and the reflowable position a voice writes down. Both are about
// text on a page, which an audiobook does not have.
//
// Android pins the moved table in `ReadAloud.kt`.

/// The colour the sentence being spoken is drawn in.
///
/// Deliberately not one of the five a reader can highlight with, and deliberately not the
/// accent: a mark the reader made is something they can come back to, and the voice's
/// place is not. A neutral at the same weight reads as "the voice is here" without
/// offering itself as a mark — and it stays legible under every reading theme, which a
/// hue would not.
///
/// Android draws the same colour from the same three numbers in `ReadAloud.kt`.
enum SpokenHighlight {
    static let red = 0.55
    static let green = 0.55
    static let blue = 0.58
}

/// Where the voice got to, in the form the progress store takes.
///
/// The handoff, as a value. The reader used to be the only thing that wrote a position: it
/// wrote on every navigator move, and the page followed the voice, so the two agreed. A
/// session that outlives its screen has no navigator to move, so the voice writes for
/// itself — and what it writes is the decision worth asserting, which is why it is a value
/// rather than a call into a database.
///
/// `ebook-reader`: the recorded position "is where the voice got to, not where the reading
/// stopped … whether the session ended with the publication open or continued after it was
/// closed". Android pins the same shape in `ReadAloud.kt`.
///
/// **A reflowable position, not a time.** `reading-progress` gives an audiobook an offset in
/// a named part and a reflowable publication a fraction plus a locator, and a publication
/// read aloud is still a reflowable publication — "there is one position, and it is wherever
/// the reader last was by either means". So a voice reading an EPUB writes what the eye
/// would have written, and this type stays here rather than moving to `Playback` with the
/// rest.
struct ReachedPosition: Equatable, Sendable {
    /// The sentence being spoken, as Readium's own opaque locator JSON.
    ///
    /// Not a page number: `ebook-reader` requires the position to survive a type-size
    /// change, and a reflowable page number cannot.
    let locator: String
    /// How far through the whole publication, 0…1.
    let progression: Double

    /// Whether there is anything worth writing down.
    ///
    /// A sentence Readium could not turn into a locator is a sentence nothing can resume
    /// from, and writing an empty one over a good position is how an hour is lost.
    var isRecordable: Bool { !locator.isEmpty }

    /// The record `reading-progress` stores.
    func record(for identity: PublicationIdentity, at moment: Date) -> ReadingProgress {
        ReadingProgress(
            identity: identity,
            position: .reflowable(progression: progression, locator: locator),
            // The reader's own rule: a reflowable book is finished at the end of its
            // content rather than at a page number.
            isFinished: progression >= Self.finished,
            updatedAt: moment
        )
    }

    /// Close enough to the end of the content to count as the end of the book.
    static let finished = 0.999
}
