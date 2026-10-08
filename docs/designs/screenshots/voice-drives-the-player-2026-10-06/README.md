# The read-aloud voice drives the one player — task 13.2

Evidence for `close-the-audited-gaps` task 13.2 on Android. `audio-playback`, *One player
for everything that speaks*: "every source of spoken audio — a narrated audiobook and the
read-aloud voice alike — SHALL drive that one surface".

Before this change the voice drove a surface of its own. A listener who left the reader had
no compact bar to come back through and no full player at all — no chapter list, no speed,
no sleep timer. iOS has had all four since read-aloud became a second `PlaybackSource`
inside its one `PlayerCentre`.

Captured on 2026-10-06, Pixel 7 Pro emulator, Android 14 (API 34), against the fixture
corpus on the device. The session is `Harbour Lights 01`, started from the EPUB reader's
menu and then left with Back, so every frame below is the voice speaking with the reader
closed.

| Frame | What it shows | Appearance | Text size |
| --- | --- | --- | --- |
| `voice-compact-light.png` | The compact bar on Home, naming the publication and the chapter the voice is in, with play/pause. It rests above the navigation control and does not displace it | light | default |
| `voice-player-light.png` | The full player the bar opens onto: the coverless well, the chapter, *Part 2 of 4*, the transport, the speed and the sleep timer | light | default |
| `voice-player-chapters-light.png` | The same player scrolled to its chapter list: chapter one *Finished*, chapter two *Playing*, the rest unmarked | light | default |
| `voice-compact-dark.png` | The compact bar in dark | dark | default |
| `voice-player-dark.png` | The player in dark | dark | default |
| `voice-player-chapters-dark.png` | The chapter list in dark | dark | default |

## What to look for, and why each is a requirement rather than a preference

**No scrub control, and no clock.** A synthesised chapter has no duration a container
states, so `audio-playback`'s "a position with no total" is what the player draws: *Part 2
of 4* rather than a `0:00` that never moves. The first draft of this change drew that
frozen clock, and the frames are what caught it.

**No *end of chapter* among the sleep-timer choices.** `SleepTimer.of` answers null where
nothing measures the part, so the option is **absent** rather than present and refusing —
"every control the player offers works, or is absent".

**The transport says *Previous sentence* and *Next sentence*, and states no interval.** A
voice moves a sentence at a time; a control labelled *30 s* over one would state a distance
it cannot travel. The glyphs are the ones the reader's own read-aloud bar already uses.

**The chapter list is the reading order.** A reflowable EPUB carries no chapter markers, so
`audio-playback`'s "a publication with no chapter markers lists its parts in playing order
instead" is what these rows are. A resource the table of contents does not name reads as
*Chapter N*, the same words an unnamed chapter of a narrated book gets.

## What is not photographed here

The car row and the lock screen. Both need the voice to be a media3 `Player` behind the
`MediaLibrarySession`, which this change does not build — see the task's own note in the
handoff. The voice still posts `ReadAloudService`'s own notification, and that notification
is unchanged by this work.
