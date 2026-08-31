# Tasks — audiobooks, and one player for everything that speaks

Test-first throughout. The Android list is longer than the iOS one on purpose:
Android's media contract reaches the notification shade, the lock screen, process
death and Android Auto, and iOS already has the compact-bar surface from
`read-aloud-beyond-the-reader`. That asymmetry is platform obligation, not scope
creep — see [`design.md`](design.md).

## 1. The shared player model

- [~] 1.1 Both: `PlaybackSessionTests` / `PlaybackSessionTest` — one session type
      with two sources, and the surfaces cannot tell which is behind them. Assert by
      driving the same assertions over both.
      **iOS done.** A new `Playback` target in `StoryArcKit` — host-testable, so
      `pnpm test:ios` covers it with no simulator. `PlaybackSource` has two places the
      sources may differ (a part's duration, and what a skip moves) and **no `kind`,
      no `isNarrated` and nothing a view can switch on**; `PlayerCentre` is the one
      session object. Nine of the sixteen tests are parameterised over both source
      kinds, which is what "driving the same assertions over both" means here.
      *The Android half is not started.*
- [~] 1.2 Both: parts, position, duration and speed as the design's table defines
      them. Assert that a source with **no known duration** reports position without
      a total rather than inventing one.
      **iOS done.** `PlaybackTime` carries `total: TimeInterval?` and `isScrubbable`,
      and `PlayerCentre.scrub(to:)` refuses to reach a source that cannot answer — so
      the scrubber is *absent* rather than present and refusing. Mutation-checked:
      making `isScrubbable` always true fails both the spoken-duration test and the
      scrub test. *The Android half is not started.*
- [~] 1.3 Both: starting a second publication stops the first, records its position
      first, and does not resume it when the second ends.
      **iOS done.** `PlayerCentre.begin` calls `end()` first, and `end()` writes the
      position before it clears anything. Mutation-checked: deleting that call fails
      the displacement test. *The Android half is not started.*

## 2. Audiobooks open

- [x] 2.1 Both: format-detection tests for M4B, MP3, FLAC and Ogg from **contents**
      rather than extension — an `.m4b` and an `.m4a` holding the same audio behave
      identically. `FormatSniffer` on both platforms, plus `Container.isAudio` so the
      reader-or-player question is asked in one place. Mutation-checked on both.
      *The folder half moves to 2.2*, which is where the folder scanner lives.
- [x] 2.2 Both: a folder of audio is one audiobook, and a folder mixing audio and
      images is the kind the majority of its entries are. `FolderKind` on both
      platforms, seven tests each, mutation-checked (make a tie an audiobook and the
      tie test fails). Asserted against the corpus's own two folders read from disk,
      not from a literal, so regenerating the fixtures differently fails it.
      `PageOrdering.isPage` split so audio reuses the resource-fork and dotfile
      exclusions rather than restating them.
      **A tie is a comic — a product decision, recorded as one**, because a folder of
      images is what StoryArc has always made of a folder.
      **And this one reads extensions where the rest of the layer reads bytes**, which
      is documented at the type: the unit being detected is the folder, its cheap
      evidence is its entries' names, and sniffing each entry would be one read per
      file to answer a question asked before anything is opened. Each part is still
      sniffed when opened.
      *Still to come with the player:* turning an audiobook folder into a
      `Publication`, which needs the model to carry an audio format.
- [ ] 2.3 Both: an audiobook with no chapter markers opens, its parts standing in for
      chapters, and nothing is reported as missing.
- [~] 2.4 Both: an `.aax`/`.aaxc` is refused by name, states the store's content
      protection as the reason, prompts for no key or account, and is distinct from
      an unsupported container. **Detection done and mutation-checked** — the brand is
      read at offset 8 and gets its own container case, so the refusal is structural
      rather than a message a caller chooses. What remains is the *wording* the user
      sees, which needs the player's own surface to say it on.
- [ ] 2.5 Both: a truncated audiobook plays what it can and states how much it could
      not, in the player's controls, without interrupting playback.
- [x] 2.6 Add audiobook fixtures to the shared corpus: a chaptered M4B, the same
      chapters as ID3 CHAP frames, an unchaptered single file, a folder of parts
      whose names defeat lexical sort, a folder mixing audio and images, a truncated
      M4B, and a locked-file *stub* for 2.4 carrying the signature and nobody's
      content. Seven fixtures, 100 kB, byte-deterministic.
      `packages/test-fixtures/scripts/generate.py`, `manifest.json`, `README.md`.
      Two things the work turned up and the corpus now records: the first truncated
      fixture had no `moov` at all — ffmpeg writes it last, so a cut file pinned
      "damaged beyond opening" instead of "plays what it can", and `+faststart`
      fixed it; and `protected.aax` still holds a **decodable** stream, so the
      refusal has to come from the brand rather than from a decoder choking.
- [ ] 2.7 iOS: `AVURLAsset` + `loadChapterMetadataGroups`. Android: media3 ExoPlayer.
- [ ] 2.8 Android: bump media3 to **1.11.0** and declare `media3-exoplayer` and
      `media3-session` explicitly in the version catalog. Readium only puts 1.10.0 on
      the classpath at runtime scope. **Nothing else in this section is blocked on
      the bump** — see `design.md`: ID3 chapters already parse at 1.10.0, so the
      MP3-folder path, detection and the unchaptered case all land without it, and
      the bump buys M4B's own chapter atom and nothing else.

## 3. The platform session

- [ ] 3.1 iOS: `AVAudioSession` category `.playback`, mode **`.spokenAudio`**.
- [ ] 3.2 iOS: extend the existing `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`
      wiring to the narrated source, so both feed the same lock screen.
- [ ] 3.3 iOS: speed without pitch — `AVPlayer.rate` with
      `audioTimePitchAlgorithm = .timeDomain`.
- [ ] 3.4 Android: a real `MediaSessionService` with
      `foregroundServiceType="mediaPlayback"` and both `FOREGROUND_SERVICE`
      permissions. Assert the service is declared in the merged manifest.
- [ ] 3.5 Android: media3's automatic `MediaStyle` notification — hand-rolling it is
      how the shade and the lock screen fall out of step.
- [ ] 3.6 Android: `MediaSession.Callback.onPlaybackResumption` returning the saved
      position, so the shade carousel works after process death.
- [ ] 3.7 Android: `MediaLibraryService` and `automotive_app_desc.xml`.
- [ ] 3.8 Both: interruption tests — audio taken and returned with the resume hint
      resumes; a pause the listener made is never undone; audio taken for good ends
      the session and records the position.
- [ ] 3.9 Both: route-change test — headphones removed pauses, and reconnecting does
      **not** resume.

## 4. The surfaces

- [ ] 4.1 Both: `CompactPlayerTests` / `CompactPlayerTest` — the bar names the
      publication and the **chapter**, is absent when nothing plays, and does not
      displace, cover or resize the navigation control. Assert content behind it
      still scrolls to its end.
- [ ] 4.2 iOS: generalise `ReadAloudDock` in `tabViewBottomAccessory` to the shared
      session, so a narrated book and a spoken one produce the same bar.
- [ ] 4.3 Android: hand-compose the row in `NavigationSuiteScaffold`'s `content`
      slot, full-width `surfaceContainer`, sharing the navigation bar's container
      colour. **Not** `BottomSheetScaffold` (no `bottomBar` slot, so the peek row
      would sit behind the navigation bar), **not** `HorizontalFloatingToolbar` and
      **not** `BottomAppBar` — both compile without complaint and both are ruled out
      by guidance. `design.md` records why, because the build will not.
- [ ] 4.4 Android: flat `LinearProgressIndicator` for the progress line.
- [ ] 4.5 Both: the full player — cover, publication, chapter, position, duration,
      play/pause, skip both ways, scrub, chapter list, speed, sleep timer. Assert
      opening it never restarts, reloads or repositions the audio.
- [ ] 4.6 Both: a publication with no chapter markers lists its parts in playing
      order rather than showing an empty list.

## 5. Controls

- [ ] 5.1 Both: speed changes without changing pitch, states a number, is remembered
      per publication and offered as the series default. Range 0.5×–3×.
- [ ] 5.2 Both: skip states its interval on the control, is configurable, and
      crossing a chapter boundary continues rather than stopping. Defaults 15 s back
      and 30 s forward — a **product decision**, recorded as one; media3's own
      defaults (5 s / 15 s) are wrong for spoken word.
- [ ] 5.3 Both: sleep timer offers durations **and end-of-chapter**, shows the
      remaining time, fades out rather than cutting, and records a position slightly
      before where the fade ended.
- [ ] 5.4 Android: declare `COMMAND_SEEK_TO_PREVIOUS`/`NEXT` so the notification's
      three compact slots carry seek-back / play-pause / seek-forward.

## 6. Playback outlives the publication

- [ ] 6.1 Both: leaving the reader while playing does not stop it, and the compact
      bar is the one action back.
- [ ] 6.2 Both: returning to a read-aloud session resumes at the sentence being
      spoken **then**, not where the reader left.
- [ ] 6.3 Both: reaching the end withdraws the highlight, dismisses the media
      controls and removes the compact bar.

## 7. Position

- [ ] 7.1 Both: an audiobook's position is an offset in a named part, survives close,
      restart and re-download, and resolves through content identity like every other
      position.
- [ ] 7.2 Both: a publication both read and listened to has **one** position, and
      returning never offers a choice of two.
- [ ] 7.3 Both: finishing by listening marks the publication finished and makes the
      same end-of-publication offers as finishing a comic.

## 8. Accessibility

- [ ] 8.1 Both: every control announced with a name and, where it has one, its value
      — speed, skip interval, remaining sleep time, position.
- [ ] 8.2 Both: the scrub control is an adjustable announcing its position **in
      time**, not as a percentage.
- [ ] 8.3 Both: the compact bar is one element with separate play/pause and open
      actions, and **does not steal focus when it appears**.
- [ ] 8.4 Both: at the largest accessibility text size nothing is truncated to one
      word and no transport control is pushed off the screen.

## 9. Docs and close-out

- [ ] 9.1 Module `README`s for the new player modules on both platforms.
- [ ] 9.2 Update `docs/openspec/STATUS.md` and the format table in the docs.
- [ ] 9.3 `pnpm lint`, `pnpm check`, `swiftlint --strict --no-cache`, `pnpm gradle`,
      `pnpm build:ios`, `pnpm build:ios:tests`, `pnpm build:android:tests`.
- [ ] 9.4 `agent-compass openspec-guard . --strict`.
- [ ] 9.5 `/opsx:verify audiobooks-and-playback`, then `/opsx:sync`.
