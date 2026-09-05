public import Foundation

public import StoryArcCore

/// The word a listener is owed because opening a publication stopped their voice.
///
/// `ebook-reader`, *Opening a different publication*: "the listener is told **once** that the
/// voice stopped, rather than discovering it by silence". Two rules live in that sentence and
/// neither is obvious from a call site, which is why they are a value rather than a flag:
///
/// **Only a displacement owes a word.** A listener who stopped the voice themselves knows they
/// did; a book that ran out of words ends with the highlight withdrawn and the transport gone,
/// which is its own announcement; audio taken for good is the platform telling them. The one
/// ending nobody is present for is the one caused by opening something else — the listener is
/// looking at the publication they just opened, not at the one that went quiet. On this
/// platform that ending has a name of its own, ``PlayerCentre/displace()``, and it is the only
/// thing that arms one of these.
///
/// **And only a *voice*.** Displacing a narrated audiobook owes nothing. `audio-playback` asks
/// for one player over both sources and states the difference "once where the publication is
/// described"; a narrator that stops when you open another book is the same event a reader
/// already understands, and saying so on every hand-over would be four words of chrome in
/// exchange for nothing. `ebook-reader`'s scenario says *the voice*, and this says the voice.
///
/// **Told once is ``taken()``.** The notice is consumed by being given, not read and left
/// standing — so returning to the screen a second time finds nothing to say. A flag cleared by
/// whoever remembers to clear it is the shape this exists to avoid: the surface that shows the
/// word is not the surface that armed it, and on a return it is the only one running.
///
/// **It names the publication**, because "the voice stopped" is only half a sentence to a
/// listener who has just opened something else — the book that went quiet is the one thing
/// they cannot see. The title is the whole of what is carried, and it is also the whole of
/// what makes the notice pending: a notice with nothing to name has nothing to say.
///
/// Mirrored in `VoiceStoppedNotice.kt` case for case, and asserted against the same table.
/// Pure, so both suites run it on the host with no session, no engine and no screen.
public struct VoiceStoppedNotice: Equatable, Sendable {

    /// Nothing is owed. The state before anything happened, and after the word has been given.
    public static let none = VoiceStoppedNotice(title: nil)

    /// The publication whose voice stopped, by the title the listener knows it under.
    /// `nil` when nothing is owed.
    public let title: String?

    /// Whether a listener is still owed the word.
    public var isPending: Bool { title != nil }

    /// The notice a displacement leaves behind.
    ///
    /// - Parameters:
    ///   - aVoice: whether what was displaced was the synthesised voice rather than a
    ///     narrated file. `false` answers ``none``, which is the second rule above.
    ///   - title: what the listener calls the publication that went quiet.
    public static func displacing(aVoice: Bool, of title: String) -> VoiceStoppedNotice {
        aVoice ? VoiceStoppedNotice(title: title) : .none
    }

    /// The notice, given.
    ///
    /// Always ``none``: this is what makes *once* structural rather than remembered. A second
    /// displacement arms a new notice, because a second silence is a second thing to be told
    /// about — the rule is one word per stopping, not one word ever.
    public func taken() -> VoiceStoppedNotice { .none }

    /// The one sentence a surface shows, in the app's language, or `nil` when nothing is owed.
    ///
    /// Worded here rather than in either surface that draws it, because two surfaces draw it —
    /// the EPUB reader and the shell — and `read-aloud-beyond-the-reader` 5.5 allows this
    /// change exactly one new key. One key can live in one catalogue, and this module's is the
    /// one both surfaces can reach. On the host the lookup answers with the key itself, which
    /// is why every test asserts ``title`` and never this.
    public var sentence: String? {
        title.map { String(localized: "player.voice.stopped \($0)", bundle: .module, locale: .storyArc) }
    }

    private init(title: String?) {
        self.title = title
    }
}
