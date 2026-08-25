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
- [ ] **2.5** Reader-local brightness that reverts on leaving the reader.
- [ ] **2.6** Verify the reading position survives a typography change to the
      paragraph, not the page.

## Phase 3 — The theme sheet

- [ ] **3.1** iOS: sheet on Liquid Glass, untinted, with its opaque
      Reduce-Transparency fallback declared.
- [ ] **3.2** Android: Material 3 modal bottom sheet honouring
      `MaterialTheme.motionScheme`.
- [ ] **3.3** Preset grid, three by two, each card previewing **its own** colours
      and typeface.
- [ ] **3.4** First level: presets, font-size stepper with step dots, page-mode
      control, brightness. Second level behind one "Customise" action.
- [ ] **3.5** Fine axes: line, character, word and paragraph spacing, margins,
      alignment, font family, bold. Long-press to reset an axis.
- [ ] **3.6** Live preview rendered by the **real** renderer, showing a chapter
      title and body text, reflowing continuously during a drag.
- [ ] **3.7** Custom background: swatches, picker, derived text colour at 7:1,
      refusal below 4.5:1 **with the measured ratio shown**.
- [ ] **3.8** Tablet: popover on iPadOS, expanded anchored sheet on Android, with
      the reader still visible.
- [ ] **3.9** Accessibility: slider values and increment actions, grid semantics
      with selected state, stepper announcing position out of total.

## Phase 4 — Transitions

- [ ] **4.1** Shared transition coordinator on both platforms: mode, direction,
      progress, interruption.
- [ ] **4.2** Slide and fast fade — cheap, and they de-risk the coordinator
      before the curl lands on it.
- [ ] **4.3** Curl, per the Phase 0 outcome. Finger-tracked, interruptible, lit
      edge, cast shadow, mirrored for right-to-left. Metal on iOS, AGSL on
      Android at API 33+.
- [ ] **4.3b** Page rastering for reflowable content: raster at display scale,
      hold at most the outgoing and incoming pages, restore live interaction the
      instant the turn completes.
- [ ] **4.4** Scroll mode with the axis rule, including the webtoon default.
- [ ] **4.5** Boundary rubber-band at the first and last page.
- [ ] **4.6** Turn triggers: tap zones, keyboard, external controller, optional
      volume buttons.
- [ ] **4.7** Reduce Motion: fall back to fast fade, keep the modes listed with
      their reason, restore the choice when the setting is turned off.
- [ ] **4.8** Placeholder at the correct aspect ratio when the destination page is
      not yet decoded.
- [ ] **4.9** Absent-Curl path: hide Curl where the device cannot honour it —
      Android below API 33, and any device failing the frame-rate check — default
      to Slide, state the reason in plain language without naming an API level,
      and leave a stored Curl preference untouched.

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

- [ ] **6.1** Bundle Literata, Source Serif 4, EB Garamond, Bitter and Atkinson
      Hyperlegible, subset to Latin, Latin Extended, Greek and Cyrillic. Record
      every OFL licence in acknowledgements.
- [ ] **6.2** Register them with Readium's font-family API on both platforms.
- [ ] **6.3** Label Atkinson Hyperlegible as designed for low vision.
- [ ] **6.4** Report the binary-size delta per family — this is a real cost and
      should be a visible one.

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
