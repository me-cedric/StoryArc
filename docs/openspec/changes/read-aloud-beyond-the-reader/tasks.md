# Tasks

**Ordering:** Phase 2 on iOS cannot start until the navigation shell from
`one-library-three-destinations` exists — there is no accessory slot without a
tab bar. Phases 0, 1 and 3 have no such dependency, and the whole Android side
has none.

**A task that changes a screen owes a screenshot from a booted simulator or
emulator**, light and dark, default and largest text size, per
[AGENTS.md §6](../../../../AGENTS.md).

## Phase 0 — Prove the assumption

- [ ] **0.1** iOS: start speech, dismiss the reader, confirm the voice continues
      with the audio-session category and background modes the app already
      declares. Deliverable: a yes or no, on a booted simulator and — because
      audio-session behaviour on a simulator is not a device — recorded as
      simulator-only until someone runs it on hardware.
- [ ] **0.2** Android: confirm the existing foreground service keeps speaking when
      the reader activity is finished while the app stays in the foreground, which
      is a different case from the backgrounding the service was built for.

## Phase 1 — Move the ownership

- [ ] **1.1** iOS: lift the session out of the reader's model into something that
      outlives a screen. The reader observes it; it does not own it.
- [ ] **1.2** The position handoff: the reached position is written when the
      session ends, whoever ended it and whatever screen was on top. **A test, not
      an inspection** — this is the path that can lose an hour of listening.
- [ ] **1.3** Mirrored host tests on both platforms: closing the publication mid
      sentence, reopening it, ending from outside the reader, and the platform
      taking the session away.
- [ ] **1.4** One session at a time: opening another publication ends the current
      one at a sentence boundary, records the position, and says so once.

## Phase 2 — The iOS transport

- [ ] **2.1** The docked control in the shell's accessory slot, with the inline
      form when the navigation is minimised. **Plain controls inside it** — the
      slot is already glass, and this codebase has a comment recording what
      glass-on-glass did to three glyphs.
- [ ] **2.2** Choosing it returns to the publication at the spoken sentence,
      without the voice stopping, from every destination and from any depth.
- [ ] **2.3** It appears when a session starts, goes when it ends, and reserves no
      space when absent. Screenshot: with a session and without, on each
      destination.
- [ ] **2.4** Accessibility: reachable in the reading order, labelled per action,
      and it does not take focus when it appears. Verified with the screen reader
      on, not by reading the code.
- [ ] **2.5** Screenshot at the largest text size, where a compact transport
      truncates first.

## Phase 3 — Android, which adds no bar

- [ ] **3.1** Confirm the notification and lock-screen controls are correct while
      the app is foregrounded with no reader on screen — not only while
      backgrounded. Screenshot the notification in both states.
- [ ] **3.2** Returning from the notification lands in the publication at the
      spoken sentence, not at the app's launch destination.
- [ ] **3.3** Explicitly assert that no in-app docked bar is added, and record why
      in the handoff, so the divergence is not read as an omission and "fixed"
      later.

## Phase 4 — The unhappy paths

- [ ] **4.1** Audio taken by a call and given back: the voice resumes; a pause the
      listener made is never undone.
- [ ] **4.2** Audio taken for good: the session ends, the position is recorded,
      the transport goes.
- [ ] **4.3** End of the publication: the voice stops, the highlight is withdrawn,
      the transport and the media controls both go away.
- [ ] **4.4** The process is reclaimed mid-session: nothing is left claiming to
      play, and the last recorded position is where the voice actually got to.

## Phase 5 — Gates

- [ ] **5.1** `corepack pnpm spec:validate`.
- [ ] **5.2** iOS: `swiftlint lint --strict`, `swift build`, `swift test`,
      `pnpm test:ios:epub`, `pnpm build:ios` — this change touches what the app
      target and StoryArcEpub compile. 400-line cap.
- [ ] **5.3** Android: `./gradlew :feature:epubreader:lint
      :feature:epubreader:testDebugUnitTest`, then the fuller run if anything
      outside that module moved.
- [ ] **5.4** `corepack pnpm lint`.
- [ ] **5.5** No new user-facing string ships from this change. If the iOS
      transport needs a label, hand it to the vocabulary slice.
- [ ] **5.6** Screenshots complete and referenced in the handoff, including the
      Android notification, which is a screen a reader sees even though it is not
      a screen the app draws.
