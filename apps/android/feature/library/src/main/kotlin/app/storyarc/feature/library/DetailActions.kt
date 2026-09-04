package app.storyarc.feature.library

import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.StreamingCapability

/**
 * The one thing this page wants the reader to do.
 *
 * `publication-detail` asks for "exactly one primary action" and for its wording to say
 * "which of those will happen before it is taken". That is an accessibility requirement as
 * much as a layout one: it is the first control after the title in the reading order, and a
 * screen-reader user learns the outcome before taking it. So the label is not a cosmetic
 * choice made at the button and it is not derived twice — it is this value.
 *
 * The last three cases are the delta's "the primary action cannot be honoured": the action
 * "states what it needs in plain language rather than failing when taken".
 */
internal enum class PrimaryAction {
    /** Nothing has been read. Opens at the start. */
    READ,

    /** Something has been read. Opens where the reader stopped. */
    CONTINUE,

    /**
     * An audiobook nobody has started. Opens the player at the beginning.
     *
     * **Four opening states rather than two, and the missing pair was a defect.** The page's
     * one button said *Read* for an audiobook. The routing was never wrong — `PlayingBook`
     * and `StoryArcApp` have asked `isAudio` since audiobooks landed and send one to the
     * player — so this was a promise the button did not keep, and a promise nothing fails on.
     * `publication-detail` makes it a requirement rather than a preference: the label says
     * which of the outcomes will happen, so a screen-reader user learns it before acting.
     */
    LISTEN,

    /** An audiobook already started. Opens the player where the listener stopped. */
    CONTINUE_LISTENING,

    /** Readable, but only once the whole file is local. A solid archive, say. */
    NEEDS_DOWNLOAD,

    /** Not on this device, and the library it lives in is not answering. */
    NEEDS_SOURCE,

    /** No decoder will open this, here or anywhere. Downloading changes nothing. */
    REFUSED,
}

/**
 * Which of the seven is true, from what the page already knows.
 *
 * Ordered so that a refusal beats an absence and an absence beats a reading position: a
 * publication the app cannot open must not be offered as *Continue* merely because a
 * position was recorded against it before its container turned out to be unreadable.
 */
internal fun primaryActionOf(
    publication: Publication,
    provenance: Provenance,
    isOnDevice: Boolean,
    hasProgress: Boolean,
): PrimaryAction = when {
    !publication.isOpenable -> PrimaryAction.REFUSED

    isOnDevice -> publication.opening(hasProgress)

    provenance.readiness == Provenance.Readiness.SOURCE_AWAY -> PrimaryAction.NEEDS_SOURCE

    publication.streaming == StreamingCapability.DOWNLOAD_ONLY -> PrimaryAction.NEEDS_DOWNLOAD

    else -> publication.opening(hasProgress)
}

/**
 * Which of the four ways in this publication offers.
 *
 * Two questions, asked in one place because both openings need both answers: *what will
 * happen to it* and *has it been started*. A single progress-first branch was the obvious
 * alternative and it is what got this wrong before — a started audiobook then says
 * *Continue*, in the reader's words, for something nobody is going to read.
 *
 * It asks [PublicationFormat.isAudio] rather than listing the audio containers, so a format added
 * later cannot miss this branch. That is the same rule the routing uses, and it is the reason
 * the two cannot drift: both ask the model the same question.
 */
private fun Publication.opening(hasProgress: Boolean): PrimaryAction = when {
    format.isAudio && hasProgress -> PrimaryAction.CONTINUE_LISTENING
    format.isAudio -> PrimaryAction.LISTEN
    hasProgress -> PrimaryAction.CONTINUE
    else -> PrimaryAction.READ
}

/**
 * Whether taking the primary action opens the book, rather than asking for it.
 *
 * Three of the seven states are a sentence with a button beside it rather than a way in, and
 * the screen has to keep the difference: a filled button that reports a problem when it is
 * pressed is the failure the delta names outright.
 */
internal val PrimaryAction.opensTheBook: Boolean
    get() = when (this) {
        PrimaryAction.READ,
        PrimaryAction.CONTINUE,
        PrimaryAction.LISTEN,
        PrimaryAction.CONTINUE_LISTENING,
        -> true

        PrimaryAction.NEEDS_DOWNLOAD, PrimaryAction.NEEDS_SOURCE, PrimaryAction.REFUSED -> false
    }

/**
 * How the primary action is worded, or null where the page draws no button at all.
 *
 * Null for exactly one state, and it is not a gap. `publication-detail` says an action that
 * does not apply is "absent, not shown disabled without explanation": a refused publication
 * has nothing to offer under any circumstances, so it gets [explanation] and no control.
 * iOS reaches the same shape from the other direction -- `DetailActions.swift:91` returns
 * `EmptyView()` for the same state and puts the refusal in a sentence.
 *
 * A label that could never render used to live here. `detail_action_refused`, "Cannot be
 * opened", was translated four ways and produced only inside `if (press != null)`, where
 * `press` is null exactly when the action is `REFUSED`. It said less than
 * `detail_refused_body` already says and was deleted rather than given a button, because
 * the button it would need is the one the spec forbids.
 *
 * The two `NEEDS_` states keep a label even though their button is conditional. That
 * condition is a fact about the app -- whether there is any way to fetch this publication
 * -- rather than about the action, so it is settled at the call site and not here.
 */
internal fun PrimaryAction.label(): Int? = when (this) {
    PrimaryAction.READ -> R.string.detail_action_read
    PrimaryAction.CONTINUE -> R.string.detail_action_continue
    PrimaryAction.LISTEN -> R.string.detail_action_listen
    PrimaryAction.CONTINUE_LISTENING -> R.string.detail_action_continue_listening
    PrimaryAction.NEEDS_DOWNLOAD, PrimaryAction.NEEDS_SOURCE -> R.string.detail_action_download
    PrimaryAction.REFUSED -> null
}

/** Where the download is offered, when the app has a way to fetch this publication at all. */
internal enum class DownloadControl {
    /** The primary action *is* the download: the book cannot be opened until it lands. */
    PRIMARY,

    /** The book opens now, and a copy is one of the things the overflow offers. */
    OVERFLOW,

    /** Nowhere. Either nothing can be fetched, or fetching would change nothing. */
    NONE,
}

/**
 * The one place that decides which control carries the download.
 *
 * `publication-detail` asks for "exactly one primary action" and for everything else to be
 * "available from this page without competing with" it. A `NEEDS_DOWNLOAD` publication used
 * to break both halves at once: the primary read *Download it* and the overflow carried a
 * second *Download it*, because the two were written in different composables and gated on
 * the same non-null callback without either knowing about the other.
 *
 * iOS cannot express that. `DetailActions.swift` partitions on one fact -- the primary is
 * the download when `file == nil` (`:102`) and the menu offers it when `file != nil`
 * (`:136`) -- so the two branches are complements and no state satisfies both. This is that
 * partition, named, with the answer as a value rather than as two conditions that have to
 * be kept opposite by hand. A function returning one of three cannot return two.
 *
 * `REFUSED` is [NONE] for the reason iOS's `canCopy` (`:179-181`) excludes it: fetching a
 * container no decoder will open produces a local copy that still cannot be read.
 *
 * @param canDownload whether the app has any route to a copy — false for a publication that
 *   is already on the device, and for one whose source offers no way to fetch it.
 */
internal fun downloadControl(action: PrimaryAction, canDownload: Boolean): DownloadControl =
    when {
        !canDownload -> DownloadControl.NONE
        action == PrimaryAction.REFUSED -> DownloadControl.NONE
        action.opensTheBook -> DownloadControl.OVERFLOW
        else -> DownloadControl.PRIMARY
    }

/**
 * The sentence under the action, when it needs one, and none otherwise.
 *
 * `publication-detail`: an action that does not apply is "absent, not shown disabled
 * without explanation". A button that cannot do the obvious thing owes a reason in the
 * same breath, and the two states that owe one are the two the reader did not cause.
 */
internal fun PrimaryAction.explanation(): Int? = when (this) {
    PrimaryAction.READ,
    PrimaryAction.CONTINUE,
    PrimaryAction.LISTEN,
    PrimaryAction.CONTINUE_LISTENING,
    -> null
    PrimaryAction.NEEDS_DOWNLOAD -> R.string.detail_needs_download
    PrimaryAction.NEEDS_SOURCE -> R.string.detail_needs_source
    PrimaryAction.REFUSED -> R.string.detail_refused_body
}
