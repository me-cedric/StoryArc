# Read-aloud beyond the reader

**Platforms: both.** The behaviour is mirrored: the voice survives the book being
closed, and there is always a way back to it. The surface diverges, and this is
the change where the divergence is the whole point — iOS grows a docked transport
in its navigation, Android grows nothing, because it already has the right one.

## Why

**Today the voice dies when the book is closed.** On iOS the reader is presented
as a full-screen cover over the app; dismissing it ends the session. So a
listener who wants to look up the next volume while listening cannot: leaving the
book is leaving the audio.

That is a defect on its own, and it is also the thing standing between the
navigation shell and the one slot it deliberately leaves empty. The platform
gives a shell a persistent accessory slot above its navigation — the mini player
every audio app on the platform uses. The direction (§3.1) reserves it and does
not fill it, for a reason it states honestly: **the only transport this app has
is read-aloud, it lives inside the reader, and the reader is presented over the
whole shell, so there is no navigation behind it to dock to.** Filling that slot
requires the session to outlive the screen.

Making it outlive the screen is a **capability change, not a layout change**, and
[AGENTS.md §3](../../../../AGENTS.md) requires it to be proposed on its own. That
is why this is a third proposal rather than a paragraph inside the shell one: if
it rode along inside the shell work it would be a lifecycle rewrite disguised as
navigation, and the shell would be blocked on speech synthesis.

**Android is already most of the way there and specified for it.** The
`ebook-reader` spec already requires that "playback continues, and platform media
controls show the publication title" when the app is backgrounded, and Android
already runs a foreground media-playback service holding a media session and
posting a media-style notification. What is unspecified on both platforms is the
case that is not backgrounding: **the app is in the foreground and the reader is
gone.** Nothing says what a listener sees then, and both apps currently answer by
stopping.

This is direction §3.1, §4.1 and open question §8.2 — of the three options the
owner is offered there, this proposal is the middle one: *propose read-aloud
outliving the reader*. A continue-reading dock is a different product idea and is
not this.

## What changes

### Modified: `ebook-reader` — *Reading aloud*

One new scenario in the existing requirement, and it is the whole capability
change: closing the publication does not stop the voice. Everything else in that
requirement — where playback starts, what the media controls show, carrying on
into the next chapter, what happens when something else takes the audio, and the
publication with nothing to say — is unchanged and restated as the delta format
requires.

### New requirement: `ebook-reader` — *The transport outside the reader*

What a listener can see and do while the voice is running and the book is closed:

- **A way back.** From wherever they are, one action returns to the book at the
  sentence being spoken. This is the requirement that makes the rest safe — a
  session with no way back is a session a reader has to force-quit.
- **A way to stop.** Pause, resume, skip a sentence, and end it, without going
  back into the book first.
- **What it says.** The publication being spoken, and the chapter — the same
  facts the platform media controls already carry.
- **When it is not there.** The transport exists only while a session does. It
  appears when speech starts and goes when speech ends, and it never lingers
  claiming to play a book that has run out of words.
- **One book at a time.** Opening a different publication ends the session at a
  sentence boundary and records where the voice got to, because two books cannot
  be read aloud at once and silently switching would lose a listener's place.
- **The platform divergence, stated as a requirement rather than left to the
  implementer.** On iOS the transport is a compact control docked with the app's
  own navigation. On Android it is the system media notification and lock-screen
  controls that already exist, and **no in-app docked bar is added** — Material
  has no persistent accessory slot above a navigation bar, and inventing one
  would be the same port failure in the opposite direction.

## Non-goals

- **A continue-reading dock.** Direction §8.2 offers it as a third option. It is
  a different product idea — a shortcut back into a book you are not currently
  listening to — and it would need its own proposal.
- **Read-aloud for comics.** Speech needs extractable text. The existing
  requirement that the control is absent for a publication with nothing to say is
  unchanged.
- **Audiobooks.** Out of scope entirely, as they already are.
- **Changing the voice, the speed, the highlighting or the sentence
  segmentation.** None of that moves.
- **Playing while the app is fully terminated.** The session lives as long as the
  app's own process rules allow, and the delta says so rather than promising
  something a platform will not honour.
- **New user-facing strings.** If the iOS transport needs a label, it goes to the
  vocabulary slice.

## Risks

**A session that outlives its screen outlives its owner.** Today the reader owns
the session, so the session cannot leak: the screen goes, it goes. Detaching them
means an explicit lifetime, and the failure mode is a voice a reader cannot find
and cannot stop. The delta therefore requires *a way back* and *a way to stop*
before anything else, and requires the transport to disappear the moment the
session ends.

**Where the reading position goes is the part that can lose data.** The existing
spec already says the recorded position is where the *voice* got to, not where
the reading stopped. Detaching the session from the screen means the writer of
that position is no longer a screen that is about to disappear. If the handoff
between the two is wrong, a listener closes their book and loses an hour. This
wants a test, not an inspection.

**On iOS this depends on the shell existing.** There is no accessory slot without
a tab bar, and there is no tab bar until `one-library-three-destinations` lands.
Until then the capability can be built and the transport has nowhere to dock, so
the ordering is not optional. Android has no such dependency — its transport
already exists.

**Android's answer is to add nothing, and that will look like an omission.** A
screenshot pair will show a docked bar on iOS and no docked bar on Android, and
that is correct. §4.9 of the direction carries the rule; this proposal restates
it so the next reviewer does not "fix" it.
