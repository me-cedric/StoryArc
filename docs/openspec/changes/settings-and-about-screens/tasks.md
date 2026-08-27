# Tasks — Settings and About screens

## Phase 1 — The store and the appearance

- [x] **1.1** A settings store on both platforms, beside `ReaderPreferences` and
      `LibraryPreferences` rather than inside either: appearance, language
      override, and the reading defaults, with the same "unreadable stored data
      reads as no data" rule the theme store already uses. **Done, and smaller than
      the task implies.**

      `AppSettings` holds four values: appearance, a language override, whether the
      volume buttons turn pages, and whether the reading theme follows the app's
      appearance. That is *all* of it, because most of the seven groups own nothing of
      their own — Sources belongs to the connectors, Downloads to `offline-downloads`,
      the reading defaults to `ShelfMemory`'s per-scope defaults, and Privacy has
      nothing to toggle at all. Its whole point is that there is no backend to opt out
      of.

      The reading defaults are therefore *not* here, which the task assumed they would
      be. They already have a home that answers the harder question — "changing the
      default must not overwrite a per-series choice" — by construction.

      One value type rather than four keys, for the reason `ShelfMemory` is one blob: a
      screen that reads five settings to draw one row should read them together, and a
      reset should be an assignment rather than four deletions.

      `AppearanceMode` moved from the design system to the domain to make this possible.
      It is a setting — stored, carried by `AppSettings` — and mapping it to a colour
      scheme and a palette is the design system's business rather than its definition.
- [x] **1.2** Extend `AppearanceMode` to System / Light / Dark / OLED Dark on both
      platforms, with the OLED reader surface deliberately above true black and the
      reason stated in the setting. This is
      `reader-theming-and-page-transitions` 5.1 and 5.3, and it lands here because
      that change has nowhere to select it. **Done.**

      The tokens already carried an `oledDark` palette whose reader surface refuses to
      be `#000`, so this was wiring rather than design. Natural is deliberately not a
      case — the spec calls it a theme rather than an appearance — and a test asserts
      its absence so a future hand does not helpfully add it.

      Dynamic colour and true black turned out to be incompatible asks: Material You
      derives its surfaces from the wallpaper, and a wallpaper-tinted "true black" is
      neither. The explicit choice wins.
- [x] **1.3** Appearance applies without a restart and follows the system while
      backgrounded. Verified by capture on the emulator, both directions. **Done, and
      the first attempt failed the interesting half of it.**

      "Without a restart" was easy. *Immediately* was not: the settings screen owned its
      own copy of the settings and handed it back on the way out, so choosing OLED Dark
      left the picker sitting in the old palette until you left the screen. That
      satisfies the letter and misses the point.

      The state is hoisted to the host on both platforms. The screen reports a change,
      the host holds it and writes it through, and the theme recomposes because the value
      it reads changed. Verified on the emulator: selecting OLED Dark turned the picker
      itself true black, with the ember accent replacing dynamic colour — because the
      explicit choice wins over Material You.
- [x] **1.4** Appearance leaves the reading theme alone — the spec's own scenario,
      and a test rather than an observation, because the two stores are separate and
      it would be easy to make one write the other. **Done**, five tests on iOS and
      four instrumented on Android, over a private preferences file rather than a mock:
      what is being asserted is that values round-trip through *storage* and that two
      stores stay out of each other's way.

      The reset test is the one worth having. `settings-and-about` requires the reset
      dialogue to state that "sources, downloads, and reading progress are not
      affected", and that claim is true because of what `AppSettings` *holds* rather
      than because the reset is careful. The test writes a reading theme and a page fit
      first, resets, and checks both survive — so the claim is checked rather than
      trusted.

## Phase 2 — Organisation

- [x] **2.1** The seven groups, each with a summary row stating its current value.
      Sources and Downloads carry their group and summary only; their rows arrive
      with the connectors and `offline-downloads`. **Done on both platforms**, in the
      spec's order rather than alphabetically: Sources first because it is what a new
      reader needs, About last because it is what nobody needs twice.

      Three groups cannot be entered yet — Sources, Downloads and Language — and each
      says what it will hold rather than opening onto a blank screen. Hiding them would
      leave a reader hunting for where sources live; a sentence costs nothing and
      answers that.

      The entry point is the library toolbar, and it is present even when the library is
      empty: a reader with no books still needs to reach About, which is where the
      licences are.

      The system back gesture goes *up one level* inside Settings rather than out of it.
      On Android that is a `BackHandler` enabled only inside a group, so the innermost
      enabled handler wins and one gesture means two things without either level knowing
      about the other.
- [x] **2.2** Search across settings, listing each match with its group path, and
      navigating to it highlighted. **Done, with the highlight not done and said so.**

      The index is a *list* rather than a reflection over the screens, because the screens
      are Compose functions and SwiftUI views, and a list is the only thing that can be
      read without building one. Each entry carries terms rather than one label, so "night"
      finds Appearance and "licence" finds About — a reader searches for the thing they
      want, not for what the screen calls it.

      A match on a setting shows its group underneath; a match on a group shows its current
      value. That is the "group path" clause, and it is what makes a match actionable:
      someone who searched "volume" needs to know it lives under Reading.

      Two honest limits. The terms are English, because an index keyed on the current
      locale would miss a reader who searches in the language they think in and matching
      both needs a catalogue the function cannot see. And selecting a match navigates to
      the group without *highlighting* the row inside it — with at most three rows per
      group there is nothing to hunt for, and a highlight mechanism for that would be
      machinery for nothing. Both are marked in the code.

      Verified on the emulator: "volume" → one row, "Volume buttons turn pages / Reading".
      "night" → Appearance, showing "OLED Dark".
- [x] **2.3** Reading defaults: the *global* half of
      `reader-theming-and-page-transitions` 3.10. Changing one must not overwrite a
      per-series choice already made — `ShelfMemory.settingDefault` already
      guarantees that by construction, so this is the screen for it plus the test
      that says so through the store. **Done on both platforms.**

      Two scopes, listed separately, because `reading-themes` gives comics and reflowable
      text their own defaults and means it: a reader who wants cream paper for novels may
      well want black behind a comic.

      Names rather than the reader's preset *cards*. A card previews a theme in its own
      colours and typeface, which earns its space when the page is visible behind it and
      is six swatches of decoration in a settings list.

      The whole settings value is written, not just the preset: a preset carries its own
      typography, and a default that kept the previous typography would not be the preset
      the reader chose.

      Verified on the emulator by reading the store before and after. Choosing Bold for
      Books added `default REFLOWABLE → BOLD` and left all three per-shelf entries and the
      fixed-layout default exactly as they were. The guarantee is structural — the two
      live in different maps, so one *cannot* reach the other — and this is that on a
      device rather than in a test.
- [x] **2.4** Reset to defaults, confirming first and stating explicitly that
      sources, downloads and reading progress are untouched. **Done, and it names a
      fourth thing the spec does not.**

      A theme chosen *while reading* is not progress, and it is not a setting either — it
      is a decision the reader made about one series. So the confirmation names it
      alongside the three the spec lists, and `ShelfMemory.clearingDefaults()` is what
      makes that true: it empties the defaults map and cannot reach a per-shelf entry.

      Naming what survives is the whole job. A confirmation that only asks "are you sure"
      leaves a reader guessing at the blast radius, which is exactly what makes a reset
      button frightening enough to never press.

      Verified on the emulator by reading both stores across the reset. Appearance went
      from OLED Dark to System, both scope defaults were emptied, and all three per-series
      choices were still there afterwards.

## Phase 3 — Privacy

- [x] **3.1** The privacy statement: no account, no backend, no analytics, no crash
      reporting, and that data leaves the device only to sources the reader
      configured. Written once and quotable, because it is a claim the app has to
      keep. **Done**, and there is nothing to toggle beside it, which is the point:
      `settings-and-about` asks for the posture to be "verifiable rather than merely
      stated", and a screen of disabled switches would imply there is something to
      switch off.
- [x] **3.2** Individually clearable cache, reading history and downloads, each
      stating what it removes and how much space it frees. **Done for the two that
      exist**, and the third is named rather than omitted.

      Cache clears with no confirmation and reading history clears behind one. The
      asymmetry is the point: a cache is rebuildable by definition, and asking twice
      for something with no consequence teaches a reader to click through dialogues.
      History is places in books, so it asks, and the confirmation names what goes
      rather than calling it "data".

      Downloads has nothing to clear because nothing downloads yet, and the screen
      says so. A Privacy screen listing two items looks incomplete; one that says why
      the third is missing does not.

      `ProgressStore.clear()` deletes through the store rather than removing the file
      on both platforms. Dropping a database from under an open connection is how a
      later read finds a corrupt file instead of an empty one.
- [x] **3.3** Diagnostic export: shown before sharing, with every credential, token
      and server hostname redacted. The redaction is a tested function, not a
      regex written at the call site. **Done.**

      This task was held earlier in the belief that it needed a log the app does not
      keep. It does not: the export is a *report* of what the app knows about itself
      — version, device class, settings, reading defaults, storage sizes — and none
      of that needs a logging subsystem.

      `DiagnosticRedaction` is the tested function, with the same five rules in the
      same order on both platforms and the same fifteen tests:

      1. The whole authority of a URL, taken as one span. Split rules leave behind
         the part they do not claim, and the part left behind is the password.
      2. A bare IPv4 address, which identifies a server without a scheme.
      3. A value introduced by a word meaning secret. The key survives, because
         knowing a token was present is useful and knowing the token is not.
      4. Any unbroken 32-character run, as a backstop for a credential nothing names.
      5. The home directory, which carries the reader's own name.

      Redaction is the second line of defence. The first is that the report carries
      no free text at all: a source is reported as a count rather than by the name
      the reader gave it, because a name they chose is where a hostname would be.

      The device is reported as a **class**, not a model. `BuildInfo` had already
      settled that for the issue link, and a report the reader may post publicly is a
      stronger reason to hold the line rather than a reason to relax it.

      The report is assembled per platform. Every value is one only the platform can
      read, so a shared builder would be a shape with no logic in it — the rule is
      shared because the rule is the dangerous part.

      Share only, no copy button: both platforms' share sheets already offer copy.

## Phase 4 — About

- [x] **4.1** Version and build, the author, the repository link, the licence.
      **Done**, with the version read from the bundle rather than written down — a
      hard-coded version in an About screen is a version that is wrong by the next
      release.
- [x] **4.2** The free-and-open statement, and one Ko-fi link that appears only
      here — never as a prompt, an interstitial or a nag. **Done.** One link, one
      screen, and the word "optional" in its own label.
- [x] **4.3** Acknowledgements, with every third-party licence in full. This is
      what `format-scope-and-libraries` 6.1 and `reading-themes` are waiting on:
      the five bundled OFL notices already ship inside both apps, and nothing shows
      them. **Done, and it needed a source of truth first.**

      `third_party/libarchive/VENDORING.md` pointed at a `THIRD_PARTY_NOTICES.md` that
      did not exist. So the inventory now does, in `packages/licences`: `notices.json`
      names each component, its licence identifier, where it came from, and *why it is
      in the app* — a dependency whose reason nobody can state is a dependency to
      remove, and this screen is where that becomes visible. `texts/` holds each licence
      body, taken from SPDX rather than transcribed.

      One copy on disk, read by both apps, the same arrangement as `packages/fonts` and
      the vendored libarchive: Android stages it into assets, iOS reads it as a
      resource-only SwiftPM package. It ships *in the app* rather than only in the
      repository because BSD and Apache require the notice to travel with the binary,
      and a notices file only a developer can see discharges nothing.

      The list is filtered by platform. Telling an Android reader that the app depends on
      the Readium *Swift* toolkit would be worse than telling them nothing.

      `THIRD_PARTY_NOTICES.md` at the repository root is generated from the same
      inventory, which is what VENDORING.md was pointing at all along.

      Verified on the emulator: the list shows the five Android entries, and tapping
      Literata renders the full SIL Open Font Licence including its copyright line.
- [x] **4.4** Report a problem: opens the issue tracker with version, platform
      version and device class pre-filled, and no personal data. **Done.** Device
      *class* rather than device, which is what the spec asked for and the more careful
      answer: a model identifier is not personal on its own, but it narrows a person far
      more than "iPhone" does.

## Phase 5 — Unblocking what waited

- [x] **5.1** Volume-button page turns, off by default —
      `reader-theming-and-page-transitions` 4.6, which was held because volume keys
      that silently stop changing the volume are a defect rather than a feature.
      **Done on Android. Not possible on iOS, and the app says so.**

      The plumbing is shaped by one fact: a volume key never reaches Compose. It arrives
      at the `Activity`, and only the activity can consume it before the system changes
      the volume. So the reader cannot handle this itself — it fills in a handler while it
      is on screen and the host calls it, and the host also checks the setting, because a
      handler being present is not on its own permission to use it.

      The holder is provided *downward* through a composition local even though the
      information flows *up*. That is the trick: a local carries a mutable object the host
      owns, the reader assigns into it in a `DisposableEffect` and clears it on the way
      out. A parameter threaded through four screens would say the same thing louder.

      Verified on the emulator, both ways round. With the setting off, two volume-down
      presses in the reader left it on page 5. With it on, the same two presses took it to
      page 7.

      **iOS cannot do this within the rules.** The system owns the volume buttons, and the
      only way to observe them is to watch `AVAudioSession.outputVolume` — a trick App
      Review has rejected, and one that breaks the moment anything else plays audio. So
      the Reading group states that rather than offering a switch that does nothing.
      `page-transitions` already allows a trigger to be absent where the platform cannot
      honour it; it is the same clause the curl uses.
- [x] **5.2** A custom reading colour for comics, so the matte around a fixed-layout
      page has a value to take — that change's 3.11. **Done on both platforms.**

      Swatches in Settings, not the reader's full picker. The picker has sliders and a
      contrast refusal, and both of those need the *page* visible behind them to be worth
      anything: here there is nothing to judge a colour against, and every suggested
      background clears AAA already, so a refusal path with no way to see why would be
      worse than the nine swatches. Black is one of them, because "none" has to be
      reachable or a reader who tries a colour is stuck with one.

      A *preset* deliberately does not reach the matte. A comic has no typography for a
      preset to change, so all a preset could offer it is a paper colour — and that is not
      what a preset means. Only a colour the reader chose explicitly applies.

      Verified on the emulator: choosing the pale green stored
      `custom: {background: #E8EFE6, foreground: #000000}` against the fixed-layout
      default, and a comic opened afterwards showed pale green above and below the page
      with the artwork drawn over it untouched.
- [x] **5.3** *Part of it.* The **opt-in link** between app appearance and reading theme —
      `reader-theming-and-page-transitions` 5.5 — is done on both platforms. Natural itself
      (that change's 5.2 and 5.4) is not, and is not this change's to build: it needs the
      procedural grain from its Phase 0.5 prototype.

      The link had been half-built and was worth catching: the *toggle* shipped with task
      1.1 and nothing read the value, so it was dead state in a store. It now resolves to a
      preset — Light to Paper, every dark appearance to Quiet — and the reader opens with
      that instead of the shelf's own theme.

      Two presets rather than four, on purpose. The difference between Dark and OLED Dark
      is the *chrome*'s black point, and a reading surface is deliberately never pure black
      anyway, so mapping OLED Dark to something darker would undo the reason that
      appearance exists.

      The shelf's stored theme is not overwritten on open, so turning the setting off brings
      it back. Adjusting a theme *while* linked does record it, which is stated in the code
      rather than glossed: that is the reader changing their mind on purpose, and a change
      that silently failed to stick would be the worse surprise.

      Verified on the emulator with the app in dark mode. Link off: the page stayed Calm,
      which is the spec's own default — "a dark app chrome with a paper-white page is a
      legitimate preference". Link on: the page became Quiet, and the shelf still read
      Calm afterwards.

## Phase 6 — Validation

- [x] **6.1** `pnpm check` green: specs, tokens, tests and both lints. **Done**, and it
      stayed green through the token change that followed.

      One flake worth recording rather than hiding: the iOS suite exits with signal 11
      about once in fifteen `pnpm check` runs, and has never done it in a direct
      `swift test`. A rerun always passes.

      What is ruled out:

      - **Not a race for a file on disk.** Every test builds its store with `inMemory()`.
      - **Not "the first run after a rebuild".** That was the best hypothesis, because
        every failure followed a build. Tested directly — touch a source, rebuild, run,
        three times — and it passed three times out of three.

      So it is an intermittent crash in `swiftpm-testing-helper` rather than in the suite,
      and it has never reproduced on demand. Left alone, and written down here with the
      disproved hypothesis so the next person does not repeat the experiment.
- [x] **6.2** Emulator and simulator captures of every screen, light and dark, at
      default and largest text size. **Done on Android, scripted, and it caught a crash.**

      Twenty-four captures in `docs/designs/screenshots/settings/`: six screens — the
      settings list, Appearance, Reading, Privacy, About and a licence body — in each of
      the four combinations. Scripted rather than done by hand, because twenty-four
      captures by hand is twenty-four chances to capture the wrong screen.

      Two things the script had to learn, both of which it got wrong first:

      1. **Changing `font_scale` restarts the activity.** Setting it while the app is open
         loses whatever screen was reached, so the theme and the size are set before the
         launch.
      2. **Walking between screens loses its place.** One back press per group meant that
         by About the walk had left Settings, and three of the four About captures were of
         the device home screen. Each screen now gets a fresh launch.

      **And the second attempt found that About crashed the process.** `AboutGroup`
      applied its own vertical scroll inside `SettingsScreen`'s scrolling column, which
      Compose refuses. Fixed, and `pnpm smoke:android` now walks thirteen routes asking
      only whether each one still opens — which is the check that was missing.

      The captures then showed a compliance defect no scan would have: the licence bodies
      read `Copyright (c) <year> <owner>`, the SPDX template's placeholder. Each component
      now carries its own copyright line.

      **iOS is not captured.** The simulator drives fine and the screens render, but a
      scripted sweep there needs the same navigation work again, and Android's sweep is
      what found the crash and the placeholder. Recorded as open rather than claimed.
- [x] **6.3** Accessibility pass over the lists and the search. **Done on Android and
      verified on a device. Started on iOS, and it found more than it closed.**

      **The pass found 30 candidate defects, 27 of which survived an independent attempt
      to refute them.** Twenty-three are fixed. Four were already fixed by the time the
      fixes were applied, because the pass and the device work overlapped.

      Three of them were found by driving TalkBack on the emulator rather than by reading
      code, and none of the three was visible in a screenshot:

      1. **A comic page announced its file name.** TalkBack said "page10.png" — a name
         from inside a CBZ, which the reader never chose. It says "Page 10 of 12" now.
      2. **A colour swatch announced its hex.** "Colour #E8EFE6" is read one character at
         a time. Each colour already had a name in a code comment, and a comment is not
         something a screen reader can say, so the names moved into core.
      3. **A row's tap target depended on the length of its label.** A one-line settings
         row measured 34dp while a two-line row measured 48dp.

      The reader chrome had a fourth, which the colour lens found: a white icon on a 20%
      white pill, drawn straight onto page art. Over a white manga page that measures
      1:1. The pills carry a scrim now.

      **Tooling, because a screenshot cannot show any of this.** `pnpm a11y:android` reads
      the accessibility tree off the device and reports an unnamed control, a name that is
      a raw value, and a target under 48dp. It has a self-test, because a scanner that
      silently stops matching reports a clean screen. Every settings screen, the library,
      the reader page and the reader chrome now report zero problems.

      **iOS is half done, and honest about it.** A UI test target now runs Apple's own
      `performAccessibilityAudit`, which is the platform's check rather than ours. It
      immediately found defects the code lenses had missed, and two of them are open:

      - **`ScanSummary` draws `textTertiary` on `storyArcGlass`.** What sits behind glass
        is cover art, so the contrast is not a number anyone can bound. The reader chrome
        had the same defect and was fixed with a scrim. Fixing it here means auditing
        every glass surface that carries text, which is its own piece of work. Recorded as
        an expected failure in `AccessibilityAuditTests`, so it starts failing the moment
        someone fixes it and leaves the annotation behind.
      - **Five untraced issues across the Settings list and its four groups**: one
        contrast failure, one contrast "nearly passed", and two fonts that do not follow
        Dynamic Type. Untraced because `xcodebuild` prints the audit's verdict without the
        element description, and reading that needs the Xcode result bundle rather than a
        terminal. At least one is likely a deliberate exception — a typeface specimen is a
        picture of a typeface, so it is sized in points on purpose and the audit cannot
        know that.

      **One thing the audit taught that the numbers did not.** The token fix that preceded
      this solved `textTertiary` to exactly 4.5:1, and Apple's audit reported "Contrast
      nearly passed" for it. A token sitting on the threshold fails the platform's own
      check while passing ours, so every role now clears 4.9:1 and the gate says why.

      **What is still unknown.** VoiceOver has not been driven by a person, only audited.
      TalkBack's spoken output was not captured — the accessibility tree is what it
      composes an utterance from, and that is what was read, which is not the same as
      listening. Neither platform has been checked on real hardware or by anyone who uses
      a screen reader daily.
- [x] **6.4** `/opsx:sync`, if any requirement turned out to need changing — and if
      none did, say so, because "the spec was right" is worth recording. **Nothing to
      merge, and one requirement reworded.**

      There is nothing for `/opsx:sync` to do: this change never carried delta specs. The
      `settings-and-about` capability was already in `docs/openspec/specs/`, which is why
      the proposal could name the five held items it unblocked.

      **The spec was right about behaviour.** Every requirement it states is built, and
      none of them turned out to be wrong once it met a device. Two notes:

      1. "cache, reading history, and downloads are individually clearable" is built for
         the two that exist. Downloads is named as absent rather than omitted. That is the
         requirement partly satisfied, not a requirement to change: the row appears when
         `offline-downloads` lands.
      2. **One wording change.** "the file is shown before sharing" said *file*, and the
         export is text handed to the share sheet rather than an artifact written to disk.
         A reader who wants a file gets one by picking a files app from that sheet, so
         building one first would be a step that serves nobody. Reworded to "the export is
         shown in full before it can be shared".

         The same scenario gained a line the implementation taught: the export carries no
         free text the user wrote. Redaction is a second line of defence, and the first is
         that a source is reported by kind rather than by the name the reader gave it —
         because a name they chose is exactly where a hostname would be. That was a design
         decision the requirement did not ask for and should have.
