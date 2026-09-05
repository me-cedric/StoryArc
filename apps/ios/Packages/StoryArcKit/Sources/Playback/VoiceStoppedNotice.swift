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
/// looking at the publication they just opened, not at the one that went quiet.
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
/// Mirrored in `VoiceStoppedNotice.kt` case for case, and asserted against the same table.
/// Pure, so both suites run it on the host with no session, no engine and no screen.
public struct VoiceStoppedNotice: Equatable, Sendable {

    /// Nothing is owed. The state before anything happened, and after the word has been given.
    public static let none = VoiceStoppedNotice(isPending: false)

    /// Whether a listener is still owed the word.
    public let isPending: Bool

    /// The notice a displacement leaves behind.
    ///
    /// - Parameter aVoice: whether what was displaced was the synthesised voice rather than a
    ///   narrated file. `false` answers ``none``, which is the second rule above.
    public static func displacing(aVoice: Bool) -> VoiceStoppedNotice {
        aVoice ? VoiceStoppedNotice(isPending: true) : .none
    }

    /// The notice, given.
    ///
    /// Always ``none``: this is what makes *once* structural rather than remembered. A second
    /// displacement arms a new notice, because a second silence is a second thing to be told
    /// about — the rule is one word per stopping, not one word ever.
    public func taken() -> VoiceStoppedNotice { .none }

    private init(isPending: Bool) {
        self.isPending = isPending
    }
}
