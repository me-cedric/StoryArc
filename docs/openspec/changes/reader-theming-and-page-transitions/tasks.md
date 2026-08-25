# Tasks

Ordered so the risky unknowns are answered before anything is built on them. The
four product questions are decided — see `proposal.md`. What Phase 0 answers is
technical, and each item's fallback is in `design.md`.

## Phase 0 — Spikes (answer before building)

- [x] **0.1** Wire Readium into both apps and confirm every axis in `design.md`'s
      mapping table actually applies at runtime. **Wired, not yet confirmed axis by
      axis.** Readium Swift 3.11 and Kotlin 3.3 both render `fixture.epub` in a
      real reader, resume from a stored locator and report progression — so the
      integration is proven and the version pins are real. What is not yet done is
      driving each of the nine axes at runtime and watching the page change; that
      needs the sheet from Phase 3 to drive them from, and it is the point of 0.2.
- [x] **0.2** Confirm `PreferencesEditor.isEffective` is a usable binding for the
      `publisherStyles` coupling on both platforms. **Answered, and the answer was
      not to use it.** Which axes the publisher's stylesheet overrides is a fact
      about the axis, not about the renderer — `design.md`'s own mapping table says
      so. So `ThemeAxis.requiresPublisherStylesOff` carries it, `ReadingTheme`
      answers `isEffective`, and the rule is unit-tested on a host instead of
      observed through a navigator. Readium's editor stays available if an axis ever
      turns out to be conditionally inert for a reason the table cannot express.
- [ ] **0.3** **iOS curl spike.** Raster a Readium page to a texture and deform it
      in a Metal vertex shader. Measure the frame rate on a 120 Hz device.
      Deliverable: a number, and a go/no-go against the refresh-rate requirement.
- [ ] **0.4** **Android curl spike.** Express the same cylindrical projection as
      an AGSL `RuntimeShader` at API 33+, using `oleksandrbalan/pagecurl` as a
      geometry reference. Measure the frame rate; verify a settling animation can
      be taken over mid-gesture.
      Deliverable: a number, and a go/no-go.
- [ ] **0.4b** Verify the API-33 gate end to end on an API 31 emulator: Curl
      absent, Slide default, reason stated once, and a stored Curl preference
      left intact rather than overwritten.
- [ ] **0.5** Procedural paper grain: prototype on both platforms and judge
      whether it reads as paper. If not, price a bundled tiling texture.
- [ ] **0.6** Record the spike outcomes as an ADR — the curl decision is exactly
      the kind of thing that gets re-litigated in six months without one.

## Phase 1 — Contract and tokens

- [x] **1.1** Add a `readingThemes` group to
      `packages/design-tokens/tokens/color.json` with all six presets, authored
      in OKLCH. **Done** — `original`, `quiet`, `paper`, `bold`, `calm`, `focus`,
      each a background and foreground pair with a stated use.
- [x] **1.2** Add `oledDark` and `natural` ramps to the same file. **Done** —
      `oledDark`, `naturalLight` and `naturalDark`, the last two because Natural is
      a theme with both polarities rather than an appearance.
- [x] **1.3** Extend `scripts/build.mjs` so every reading-theme pair is asserted
      at 7:1 and every new app ramp at its existing floors. A failing preset must
      fail the build. **Done** — `pnpm tokens:check` prints a PASS line per preset
      against a 7.0 floor and exits non-zero on any failure.
- [x] **1.4** `pnpm tokens:sync`; commit the regenerated Swift and Kotlin in the
      same change. **Done** — `StoryArcColor.ReadingThemes`, `.OledDark`,
      `.NaturalLight` and `.NaturalDark` on iOS, and the same four objects on
      Android. `pnpm lint` fails if either drifts from the source.
- [x] **1.5** Extend the domain model on both platforms: `ReadingTheme`,
      `ThemeAxis`, `ThemePreset`, and rename `PageTransition.fade` to `fastFade`.
      **Done.** `ThemePreset` carries `keepsPublisherStyles`, true for Original
      alone; `ThemeAxis` carries `requiresPublisherStylesOff` straight from
      `design.md`'s mapping table; `ReadingTheme` is a preset plus the set of axes
      deviated from, which is the only part Readium will not tell us.

      Deliberately holds **no typographic values** — a preset is a named
      `EPUBPreferences` value and Readium owns those. The superseded
      `ReaderTheme { paper, sepia, night, contrast }` is deleted rather than left
      beside its replacement.

      An axis that cannot reach the page does not count as a deviation, because
      nothing changed and marking the preset modified would be a lie the reader can
      see.
- [x] **1.6** Unit-test preset resolution, axis deviation and the
      "modified preset" state — on both platforms, against the same table.
      **Done** — 10 tests each side: the preset and axis counts, which axes
      Original disables (four of nine reach the page), deviation marking the preset
      modified while keeping it selected, an inert axis not counting, restore, adopt
      clearing the previous deviations, and Reduce Motion substituting the fast fade
      without touching the scroll modes.

## Phase 2 — Readium integration

- [x] **2.1** iOS: add `Readium` via SPM; new `Reader` target wrapping
      `EPUBNavigatorViewController`.
- [x] **2.2** Android: add Readium from Maven Central; new `:core:reader` module.
      **Done, named `:feature:epubreader`.** A feature rather than a core module,
      because Readium's EPUB navigator is a `Fragment` and the screen that hosts it
      is a `FragmentActivity` — putting that behind `:core:` would have implied it
      was infrastructure other features could use. iOS's equivalent is the separate
      `StoryArcEpub` SwiftPM package, for the platform reason recorded in ADR-0005.
- [x] **2.3** Map `ReadingTheme` → `EPUBPreferences` / `EpubPreferences` on both
      sides. One function, unit-tested, so the two platforms cannot disagree.
      **Done.** `ReadiumMapping.swift` and `ReadiumMapping.kt`, one function each
      and nothing else in the file — if Readium renames an axis the compiler points
      there and nowhere else.

      The colours come from the tokens as **hex**, which needed a small addition to
      the generator: Readium parses its own colour and the generated hex previously
      lived only in a comment. `StoryArcReadingThemeHex` is emitted from the same
      resolved value as the platform colour, so the preset's swatch and the rendered
      page cannot show different colours.

      Bold is a `fontWeight`, not a family, per `reading-themes`.
- [x] **2.4** Bind each control's availability to `isEffective`, with the
      one-line reason and the single action that disables publisher styles.
      **Done, from the domain rather than from Readium's editor.**
      `ReadingTheme.isEffective(_:)` answers it, which means the sheet needs no
      `PreferencesEditor` and the rule is unit-tested on a host. Verified on the
      emulator: selecting Original shows "The publisher's styling is in use", the
      one-line reason, a "Use StoryArc's typography" button, and the five axes it
      makes unavailable listed by name — not hidden, and not live-looking controls
      that do nothing.

      This supersedes spike **0.2**: `isEffective` on Readium's editor was going to
      be the signal, and the domain turned out to know the answer already, because
      the coupling is a property of the axis rather than of the renderer.
- [x] **2.5** Reader-local brightness that reverts on leaving the reader.
      **Done, and the two platforms revert it differently because their APIs
      differ.** Android's screen brightness is a *window* attribute, so leaving the
      activity puts the device's own back without anyone remembering to. iOS's
      `UIScreen.brightness` is global, so the reader records what it found on
      appearing and restores it on disappearing. `reading-themes` requires the
      system brightness not to be permanently modified; on iOS that is code, on
      Android it is the platform.
- [x] **2.6** Verify the reading position survives a typography change to the
      paragraph, not the page.
      **Verified, and it did not survive until it was made to.** Measured on an
      emulator: raising the text size two steps kept the chapter and the reported
      progression (50% before and after) but moved the reader roughly fourteen
      paragraphs back inside the chapter — Readium re-paginates to the
      *progression*, and a progression is a coarser thing than a paragraph.

      Both readers now capture the locator before submitting preferences and go back
      to it once the reflow has settled. Re-measured: the top paragraph moves by one,
      which is a paragraph boundary landing differently rather than a lost place.

      ponytail: the wait is a fixed 120 ms because `submitPreferences` has no
      completion callback. If Readium exposes a settled signal, wait on that.

## Phase 3 — The theme sheet

**Where this stands.** The sheet is built, wears each platform's own material, and
its semantics are covered by a test that runs on a device. Still open: the preset
cards preview each theme's colours but not its typeface (3.3), the live preview
rendered by the real renderer inside the sheet (3.6 — the change is visible in the
reader *behind* the sheet, which is what the spec asks for, but there is no sample
inside it), custom backgrounds (3.7), and the tablet layout (3.8).

- [x] **3.1** iOS: sheet on Liquid Glass, untinted, with its opaque
      Reduce-Transparency fallback declared. **Done**, and the fallback is declared
      once rather than eleven times.

      The sheet needed no material of its own — it needed the opaque fill it was
      painting *over* the system's glass removed. An iOS 26 sheet is already
      presented on Liquid Glass and already goes opaque under Reduce Transparency,
      so a second declaration here could only disagree with the first.

      The chrome we do paint ourselves is a different matter. `storyArcGlass` in
      `DesignSystem` carries both halves of the requirement — the glass, and the
      opaque `surfaceOverlay` fill with a strengthened border under Reduce
      Transparency. Eleven call sites across both readers and the library used to
      pass `.ultraThinMaterial` and declare nothing; a fallback that has to be
      remembered at eleven places is a fallback that will be missing at one.

      The two icon buttons in each reader use `.buttonStyle(.glass)` instead — the
      platform's own glass button, which brings the interactive highlight a
      hand-rolled pill does not. Both readers' chrome now sits in a
      `GlassEffectContainer`, which is the only thing that makes overlapping glass
      shapes morph as one, as the spec asks.

      Verified on the simulator: the library's toolbar, search field and skipped
      banner all pick up the covers behind them.
- [x] **3.2** Android: Material 3 modal bottom sheet honouring
      `MaterialTheme.motionScheme`. **Done.** The sheet was already a
      `ModalBottomSheet` under `MaterialExpressiveTheme`, which supplies
      `MotionScheme.expressive()` — so the motion half needed nothing but checking
      that the reader activity uses the app's theme rather than a bare
      `MaterialTheme`. It does.

      What was missing was the tonal half: the preset cards were a bare `Column`
      with a `clickable`. They are now `surfaceContainerHigh` cards, which is the
      Android counterpart of the glass the iOS cards sit on. Verified on the
      emulator.
- [x] **3.3** Preset grid, three by two, each card previewing **its own** colours
      and typeface. **Done.** It was marked done once before the typeface half
      existed, and then reopened; this is the whole thing.

      The colours were already there — each card drew its own background. What a card
      could not do was show a *face*, because it drew three grey rules and a rule has
      no letterforms. It now draws two short lines of real text in the preset's own
      face, colour and weight. Words rather than lorem ipsum, because a reader judges
      a typeface by shapes they know, and two lines fit a 44-point card while still
      showing ascenders, descenders and a figure.

      That needed the bundled faces in front of each platform's *own* text stack, not
      only Readium's: `CTFontManagerRegisterFontsForURLs` on iOS,
      `FontFamily(Font(assetManager …))` on Android. Without it a specimen falls back
      to the system font in silence — the one failure a typeface picker must not have.

      The typeface picker itself now draws each name in the face it names. On iOS that
      meant replacing the menu with a list of rows: SwiftUI strips a custom font
      inside a menu, and a picker whose options all look alike is a list of words
      rather than a choice.

      Two defects in Phase 6 surfaced while doing this, both fixed:

      - **Bitter shipped as Thin.** The build narrowed the weight axis to 300–700 and
        the instancer kept the bottom of the range as the default instance, so the
        family's default was Light and its name still read "Bitter Thin". The page was
        unaffected — CSS resolves `normal` to 400 within the declared range — but any
        native specimen would have drawn a hairline and called it Bitter.
      - **The narrowing was not paying for itself.** Measured: about 1% on the
        families with a wide range, and **+52 kB on Bitter**, because the instancer
        restructures `gvar` and promotes `GPOS` to 32-bit offsets. It is gone. Pinning
        `opsz` is the whole win, at 43% on the two families that have one.

      The family name is now written from the same constant the app asks for, rather
      than inherited. Inheriting it went wrong twice — "Bitter Thin", and the
      instancer's own `--update-name-table` renaming Literata to "Literata 12pt".

      Verified on the emulator: six cards in six faces, and eight picker rows each in
      their own letterforms, Bitter at Regular weight.
- [x] **3.4** First level: presets, font-size stepper with step dots, page-mode
      control, brightness. Second level behind one "Customise" action.
- [x] **3.5** Fine axes: line, character, word and paragraph spacing, margins,
      alignment, font family, bold. Long-press to reset an axis.
- [ ] **3.6** Live preview rendered by the **real** renderer, showing a chapter
      title and body text, reflowing continuously during a drag.
- [x] **3.7** Custom background: swatches, picker, derived text colour at 7:1,
      refusal below 4.5:1 **with the measured ratio shown**. **Done for reflowable
      publications.** The fixed-layout half is held — see below.

      The contrast maths is domain code on both platforms, using the *same*
      relative-luminance definition as `packages/design-tokens/scripts/oklch.mjs`
      down to the 0.04045 knee. A golden-value test pins the two together: if they
      drifted, a pairing could clear the build gate and be refused in the sheet, or
      worse the other way round.

      Deriving a text colour is black or white and nothing else, because contrast
      depends only on relative luminance and those are its extremes — so it is the
      whole answer rather than a search that stopped early. The consequence is worth
      stating: a **mid-tone background has no text colour that reaches 7:1 at all**.
      Grey `#808080` tops out near 5.3. The sheet says so instead of quietly handing
      back black and looking like a pass.

      The ratio is on screen at all times, not only when something is refused. A
      number that appears only to scold is a number the reader has no reason to
      trust. The refusal states its own measurement, which is what the spec asks
      for and the reason the rejected pairing has to exist as a value long enough to
      be measured.

      A malformed hex measures 1 — the worst — never 21. A typo must not be the
      reason a pairing is accepted.

      The seventh slot is a field beside `preset` rather than a seventh enum case,
      which is what "alongside the six presets rather than overwriting one" means.
      Choosing colours keeps the typography the reader already set; tapping one of
      the six leaves the palette behind; and Original refuses it outright, because
      the publisher's own colours are the point of that preset. Three tests each
      side hold those.

      The picker is a `ColorPicker` on iOS and three Material sliders on Android.
      Compose has no colour picker, and the sheet already speaks in sliders — a
      hand-rolled hue wheel would be more code and less familiar.

      Verified on the emulator end to end: picking the navy swatch showed the
      pairing and "Contrast 15.7 to 1"; choosing a dark text colour on it was
      refused with "1.0 to 1 is below the 4.5 to 1 needed to read comfortably".

      **Held:** the last scenario — a custom background applying "to the area around
      the page and not to the page itself" for fixed-layout, comics and scanned PDFs.
      The comic reader hard-codes black and knows nothing about a reading theme, and
      it cannot learn one until themes persist, because `reading-themes` gives
      reflowable and fixed-layout separate defaults that have to be *stored*
      somewhere. See 3.10.

- [x] **3.10** **Theme scope and persistence.** Added, because the
      `reading-themes` requirement of the same name had no task and the gap was
      visible in the product: the theme started at its default on every open, so
      every choice a reader made was lost when they closed the book. **Done for
      reflowable publications.**

      `ShelfMemory` is one small data structure that answers all three scenarios,
      and the third answers itself. A theme is stored per *shelf* — its series, or
      its own identity where it has none, because a standalone book is a series of
      one and keying it to the global default would mean reading one novel in sepia
      changed every other book. A scope's default covers a shelf never opened. And
      "changing the default does not overwrite a per-series choice already made"
      needs no logic at all: `settingDefault` writes to a different dictionary, so it
      *cannot* reach a shelf entry.

      Reflowable and fixed-layout are separate scopes because the spec says so and
      because it is right: a line height means nothing to a page of artwork, and a
      reader who wants cream paper for novels may well want black behind a comic. The
      key carries the scope, so a series called "Bone" holding both a comic and an
      ebook does not share one entry.

      A `ShelfSettings` is the theme *and* the typography, not just the preset. Storing
      only the preset would silently put a moved line height back on the next open —
      losing work the reader can see they did. Two round-trip tests hold that, and a
      third holds it for a custom palette.

      Android needed `kotlinx.serialization`, which was already in the version
      catalogue and unused. Hand-rolling a JSON codec for a map of nested records is
      exactly the boilerplate it exists to remove, and the model will need
      serialising again for sync. iOS was already `Codable`.

      One thing moved while wiring this: the stable publication key is now
      `PublicationIdentity.stableId`, with `Publication.id` delegating to it. The
      identity is the only thing that decides the key, and a caller holding an
      identity and not a whole publication needs it just as much — the reader's view
      model, as it turns out.

      The Android save is a `combine` over the two flows rather than a call in each
      mutator. There are six mutators; one that forgot would lose a choice silently.

      Verified on the emulator: chose Calm, stepped the size to 115%, force-stopped
      the app, relaunched, reopened the book — Calm at 115%, still marked Modified.
      iOS runs the same resolution through `UserDefaults` and is covered by the same
      domain tests, but has not been driven end to end on a simulator.

      **Held:** the global default is readable and writable but no settings screen
      changes it yet — that is `settings-and-about`, which does not exist. And the
      comic reader still hard-codes black, so the fixed-layout scope has no reader
      reading it. See 3.11.
- [ ] **3.8** Tablet: popover on iPadOS, expanded anchored sheet on Android, with
      the reader still visible.
- [x] **3.9** Accessibility: slider values and increment actions, grid semantics
      with selected state, stepper announcing position out of total. **Done, and
      tested on a device rather than asserted.**

      The question a slider's accessibility value has to answer — what does this
      number mean — is a domain question, so `ThemeAxis` answers it: `unit` says
      whether the number is a multiple or an em, and `step` is a tenth of the range.
      Both platforms read the same answer, so they cannot describe the same slider
      differently, and a test asserts that an axis with a slider always has both —
      a tenth axis added to `sliderRange` and forgotten would otherwise ship a
      slider a screen reader reads as a bare float.

      Stepping the sliders was not only for the increment action. A continuous drag
      submitted a preference change per frame, and every one of those relays out the
      page. Ten positions also makes the ticks Material draws read as a scale;
      twenty read as noise, which is what the first attempt looked like on the
      emulator.

      Two defects only a semantics dump could show, both now fixed: every slider
      was unnamed, because the axis heading is a *sibling* node and a screen reader
      landing on the slider heard a bare percentage of a range; and the typeface
      rows were a radio button beside two loose labels, so "Designed for low vision"
      was a node a reader could walk straight past.

      `uiautomator dump` reports a Compose slider as an unnamed `SeekBar` whatever
      its semantics say, so it cannot answer this — it is what made the first
      attempt look broken when it was not. `ThemeSheetSemanticsTest` runs in a real
      composition on the emulator and asserts what a screen reader actually learns:
      four tests, all passing.

      iOS carries the same labels and values through the equivalent SwiftUI
      modifiers. Those are not yet driven by VoiceOver — 7.4 is where that belongs.

## Phase 4 — Transitions

- [x] **4.1** Shared transition coordinator on both platforms: mode, direction,
      progress, interruption. **Done for mode and position; interruption belongs with
      the curl.**

      The two platforms need different amounts of it, which is worth recording. On
      iOS one `displayIndex` drives all three containers, because `scrollPosition`
      and `TabView`'s selection speak the same language — there is no coordinator
      type to write. Android needs one: a `PagerState`, a `LazyListState` and a plain
      index have nothing in common, and fourteen call sites in the reader reached
      into the pager directly. `Paging` is that seam — two questions, three
      implementations, and the chrome, slider, thumbnail strip and end screen no
      longer know which container is underneath.

      Two bugs the seam surfaced, both fixed:

      - **A coordinator wrapper rebuilt on every recomposition is a fresh
        `LaunchedEffect` key**, and an effect that writes the position it just read
        then recomposes for ever. It looks exactly like a reader whose taps do
        nothing, because the frame never settles.
      - **The page a publication opens on was reaching only the pager.** A ComicInfo
        cover or a resumed position arrives after `open()`, not at first composition;
        seeding worked while `rememberPagerState` was the only container, because it
        restores itself from saved state. A fade and a scroll have nothing saved to
        restore from, so they opened at page one. Both now jump once, when the real
        answer arrives.
- [x] **4.2** Slide and fast fade — cheap, and they de-risk the coordinator
      before the curl lands on it. **Done, and the de-risking worked** — both bugs
      above were found by Slide and Fast fade rather than by the curl.

      Slide is the platform's own pager on each side, which brings its gesture, fling
      and edge resistance for free. Fast fade has no container at all: 140 ms, which
      is about the shortest a dissolve can be without reading as a cut, and short
      enough that it does not become the thing it substitutes for.

      Verified on the emulator: the picker offers Slide, Fast fade and both scroll
      axes; Curl is absent with its reason; single edge taps turn in both directions
      in every mode; the slider turns; and each choice survives a process kill,
      per shelf and per scope.
- [ ] **4.2** Slide and fast fade — cheap, and they de-risk the coordinator
      before the curl lands on it.
- [ ] **4.3** Curl, per the Phase 0 outcome. Finger-tracked, interruptible, lit
      edge, cast shadow, mirrored for right-to-left. Metal on iOS, AGSL on
      Android at API 33+.
- [ ] **4.3b** Page rastering for reflowable content: raster at display scale,
      hold at most the outgoing and incoming pages, restore live interaction the
      instant the turn completes.
- [x] **4.4** Scroll mode with the axis rule, including the webtoon default.
      **Done.** A lazy list on both platforms, pages stitched with no gap: each page
      fills the scroll's *cross* axis and takes what it needs along the scroll axis.
      Fitting each one to the screen instead leaves a band of background between
      every pair, and stitching along the wrong axis leaves a row of slivers — which
      is what the first attempt did, because the flag was a boolean that assumed
      vertical.

      The axis comes from the domain: vertical for reflowable text and for pages
      "materially taller than they are wide", horizontal otherwise. Two is the
      threshold, and it is chosen not to need tuning — a comic page is about 0.65
      wide-to-tall and a webtoon strip is many times its width, so two is far above
      one and far below the other. It is measured from the first decoded page rather
      than declared, because a webtoon rarely says it is one, and first rather than
      tallest because waiting for the tallest means waiting for the whole publication.

      The axis override is the second scroll row rather than a separate control.
      `page-transitions` requires the axis to be "separately overridable", and two
      rows are that with nothing extra for a reader to find. ponytail: two rows;
      split them into a mode and an axis picker if a third axis ever exists.

      Zoom is off inside a scroll, deliberately: the scroll owns the drag, and two
      things claiming it is how a reader ends up able to do neither.

      Verified on the emulator in both axes — pages meeting edge to edge, the page
      counter tracking a continuous scroll.
- [ ] **4.5** Boundary rubber-band at the first and last page.
- [ ] **4.6** Turn triggers: tap zones, keyboard, external controller, optional
      volume buttons.
- [x] **4.7** Reduce Motion: fall back to fast fade, keep the modes listed with
      their reason, restore the choice when the setting is turned off. **Done in the
      domain and in both pickers.**

      `TransitionChoices` computes it rather than storing it, which is what makes the
      last clause free: the stored choice is never rewritten, so turning the setting
      off restores it without the reader reopening anything. iOS reads
      `accessibilityReduceMotion` from the environment, which is where a change to it
      arrives. Android has no equivalent flag and reads the animator duration scale,
      which is what "remove animations" sets — on demand, not cached, for the same
      reason.

      Listed and marked, not hidden: `page-transitions` is explicit that "a control
      that vanishes teaches the user nothing".

      Not verified on a device with the setting on. That belongs to 7.6.
- [ ] **4.8** Placeholder at the correct aspect ratio when the destination page is
      not yet decoded.
- [x] **4.9** Absent-Curl path: hide Curl where the device cannot honour it —
      Android below API 33, and any device failing the frame-rate check — default
      to Slide, state the reason in plain language without naming an API level,
      and leave a stored Curl preference untouched. **Done, and currently that is
      every device**, because the curl does not exist yet: `canCurl` defaults to
      false on both platforms. `page-transitions` says "the app never ships a curl
      that stutters in preference to a slide that does not", so the honest answer for
      a curl with no implementation is that it is unavailable.

      Two treatments, because the spec asks for two, and the difference is whether
      the reader can do anything about it. Reduce Motion leaves Curl and Slide
      *listed and marked*; a device that cannot curl leaves Curl *absent*, with the
      reason stated once as a sentence. A permanently dead row is furniture.

      The stored preference is untouched in both cases, so a reader who set Curl on a
      capable device reads with Slide here and finds Curl still chosen when they go
      back. Three tests each side hold that.

      Verified on the emulator: "Curl is not offered here: this device cannot draw it
      smoothly enough to be worth it." No API level named.

## Phase 5 — Appearance and Natural

- [ ] **5.1** Extend `AppearanceMode` to System / Light / Dark / OLED Dark on
      both platforms.
- [ ] **5.2** Natural as a theme with its own light and dark variants: accents
      app-wide, grain confined to reading surfaces.
- [ ] **5.3** OLED Dark: true black chrome, reader surface deliberately above
      true black, with the reason surfaced in the setting.
- [ ] **5.4** Natural grain as procedural noise on reading surfaces only,
      disabled automatically under Reduce Transparency or Increase Contrast, and
      absent below API 33 on Android with the palette retained.
- [ ] **5.5** Opt-in setting linking app appearance to reading theme; off by
      default.

## Phase 6 — Fonts

- [x] **6.1** Bundle Literata, Source Serif 4, EB Garamond, Bitter and Atkinson
      Hyperlegible, subset to Latin, Latin Extended, Greek and Cyrillic. Record
      every OFL licence in acknowledgements. **Done**, in `packages/fonts` — one
      copy read by both apps, the same arrangement as the fixture corpus and the
      vendored libarchive.

      `scripts/build.py` fetches from google/fonts and subsets, so the files are
      reproducible rather than remembered. Polytonic Greek is deliberately absent:
      the task names Greek, and polytonic is a separate Google Fonts subset that
      costs EB Garamond a couple of hundred kilobytes on its own.

      The five OFL notices ship with both apps — SwiftPM resources on iOS, staged
      assets on Android. The acknowledgements *screen* that displays them belongs
      to `settings-and-about` and does not exist yet; the files being in the bundle
      is what the licence requires, and the screen is what the spec requires.
- [x] **6.2** Register them with Readium's font-family API on both platforms.
      **Done**, one file per platform. Readium renders reflowable EPUB in a web
      view, so a family it has not been told about resolves to nothing and the page
      falls back silently — the declaration is not optional decoration.

      The declared weight range is the range the file was instanced down to.
      Declaring wider would ask the renderer to extrapolate weights the file no
      longer carries.

      Verified on the emulator: selecting EB Garamond changes the letterforms and
      the figures on the page behind the sheet, which is the only proof that the
      asset was actually served rather than silently missed.
- [x] **6.3** Label Atkinson Hyperlegible as designed for low vision. **Done, and
      as a property of the face rather than a string in a sheet.**
      `ReaderTypeface.isDesignedForLowVision` carries it, so the label cannot be
      forgotten by a second picker. Verified on the emulator: the row reads
      "Atkinson Hyperlegible" with "Designed for low vision" beneath it.
- [x] **6.4** Report the binary-size delta per family — this is a real cost and
      should be a visible one. **Done, and the number is worse than the estimate.**

      | Family | Bundled | Upstream | Saving |
      | --- | --- | --- | --- |
      | Literata | 898 kB | 1814 kB | 51% |
      | Source Serif 4 | 1095 kB | 2017 kB | 46% |
      | EB Garamond | 1197 kB | 1568 kB | 24% |
      | Bitter | 567 kB | 631 kB | 10% |
      | Atkinson Hyperlegible | 196 kB | 215 kB | 9% |
      | **Total** | **3954 kB** | **6245 kB** | **37%** |

      4.0 MB per app, against `design.md`'s "roughly 2–3 MB". The estimate was
      optimistic and the table is the number.

      One reduction does the work, and it changes nothing a reader can see:
      subsetting to the four named scripts, and pinning the optical-size axis of the
      two families that have one. Narrowing the weight axis was also tried and then
      removed — it saved about 1% and *grew* Bitter by 52 kB, because the instancer
      restructures `gvar` and promotes `GPOS` to 32-bit offsets. EB Garamond and
      Bitter have no second axis, which is why they barely move and why EB Garamond
      is the largest of the five.

      `python3 packages/fonts/scripts/build.py --check` reprints the bundled column,
      so this table cannot quietly go stale.

      **The first version of this table was wrong** — it read "Bitter 563 kB / 563 kB
      / 11%", three numbers that cannot all be true. That is what `--check` is for.

## Phase 7 — Validation

- [ ] **7.1** `pnpm lint` — specs and token contrast, including all six presets.
- [ ] **7.2** `pnpm test:ios` and `pnpm test:android`.
- [ ] **7.3** `pnpm lint:android`, `swiftlint --strict`, both app builds.
- [ ] **7.4** **Visual proof.** Simulator and emulator screenshots of the theme
      sheet and all six presets, in light and dark, at default and largest text
      size. A `#Preview` is not proof.
- [ ] **7.5** Record the curl: a screen recording on each platform, because a
      still frame cannot show interruptibility or finger tracking.
- [ ] **7.6** Accessibility pass: VoiceOver and TalkBack over the sheet, Reduce
      Motion, Reduce Transparency, largest text size.
- [ ] **7.7** `/opsx:sync` to merge the delta specs into the main specs.
- [ ] **3.11** **The custom background around a fixed-layout page.** The last
      scenario of 3.7: a custom background "applies to the area around the page and
      not to the page itself, because tinting artwork is not a reading preference".

      Now unblocked by 3.10 — the fixed-layout scope exists and resolves — but the
      comic reader hard-codes `Color.Black` and knows nothing about a reading theme.
      It needs the theme threaded in on both platforms, and the matte around the page
      painted from it.
