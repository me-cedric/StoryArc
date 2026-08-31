# Audiobooks, and one player for everything that speaks

## Why

StoryArc reads aloud and cannot play an audiobook, and those two facts are stranger
together than either is alone.

**Read-aloud already built two thirds of a player.** It has a position that
survives closing the publication, it holds the audio session, it recovers from a
phone call, it publishes to the lock screen with a title and a chapter name, and it
follows the text as it speaks. What it does not have is anywhere to *be* in the app.
Leave the publication and it stops; there is no surface saying something is
playing, no way back to it, no speed, no sleep timer, and no way to start it and go
and do something else — which is the entire reason a person plays a book instead of
reading one.

**Audiobooks are the format a reading app is expected to open.** A reader with an
M4B, or a folder of chapter MP3s from a library service, has nowhere to put it.
Both platforms decode these natively — no new dependency, no server, nothing to
sign in to. What is missing is the app treating a publication whose pages are
minutes as a publication.

**And the two want the same surface.** A voice reading an EPUB and a narrator
reading an M4B differ in where the audio comes from and in nothing else a listener
can name. They should not get two players, two lock screens, two position models
and two sets of controls.

## What changes

**Audiobooks open.** M4B, a folder of ordered audio files treated as one
publication, and a single long audio file — detected by content like every other
format, with chapters taken from the container's own markers where it has them and
from the file order where it does not.

**One player, two sources.** A player surface that both read-aloud and an audiobook
drive. It rests as a compact bar above the navigation control, showing what is
playing and offering play, pause and a way back; opening it gives the full screen —
cover, chapter, position, speed, sleep timer, skip, and the chapter list. The
compact bar does not displace the navigation control and does not appear when
nothing is playing.

**Playback keeps going.** Leaving the publication does not stop it. That is the
whole point of the surface and the one behaviour that turns read-aloud from a
demonstration into a feature.

**Position is time, and it is the same position.** An audiobook's place is an
offset into a chapter, stored by [`reading-progress`](../../specs/reading-progress/spec.md)
alongside every other position, so finishing an audiobook marks the publication
finished exactly as finishing a comic does.

**Different from Apple's, deliberately.** Three choices, each because it suits a
reading app: the compact bar states the *chapter*, not the file name, because that
is what a listener is in the middle of; the sleep timer offers an
end-of-chapter option, which a music player has no reason to have and a book player
does; and the same surface serves a synthesised voice and a narrator, with the
source named once and never again — a listener should not have to think about which
kind of audio they started.

## Platforms

**Both.** Each platform's own media stack, its own now-playing integration and its
own compact-bar component; [ADR-0001](../../../decisions/0001-independent-native-cores.md)
forbids either drawing the other's. The behaviour below is identical on both.
design.md names the components and the guidance.

## Non-goals

- **No streaming audio service, no store, no subscriptions.** Audiobooks come from
  the sources StoryArc already has: the device, a folder, a share, a catalogue.
- **No new sync.** Position rides on the mechanism
  [`reading-progress`](../../specs/reading-progress/spec.md) already defines. There
  is no separate listening history and nothing about playback leaves the device,
  per [`project.md`](../../project.md).
- **No DRM.** An Audible `.aax`/`.aaxc`, or any other encrypted audio, is refused by
  name like any other unsupported container. StoryArc does not implement, work
  around, or advise on removing a content protection.
- **No transcript alignment.** Matching a narrator's audio to an EPUB's text —
  EPUB 3 media overlays included — is a separate problem and is not started here.
- **Not the shell's layout.** The bar sits above the navigation control and changes
  nothing about it; the destinations are [`quiet-shell-and-search`](../quiet-shell-and-search/proposal.md).
- **Not the reader's chrome.** [`quiet-reader`](../quiet-reader/proposal.md) owns
  that, and touches different requirements in `ebook-reader` than this change does.

## Capabilities

- **`publication-formats`** — audiobook containers open, and encrypted audio is
  refused by name.
- **`audio-playback`** *(new)* — the player surface, its controls, its lifetime, and
  what it does when the audio is taken away.
- **`ebook-reader`** — read-aloud drives that player instead of its own controls,
  and survives leaving the publication.
- **`reading-progress`** — a position measured in time.
