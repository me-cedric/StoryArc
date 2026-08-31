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
- [x] **0.3** **iOS curl spike.** Raster a Readium page to a texture and deform it
      in a Metal vertex shader. Measure the frame rate on a 120 Hz device.
      Deliverable: a number, and a go/no-go against the refresh-rate requirement.

      **Go, with two corrections to the plan and one honest gap.**

      A *fragment* shader, not a vertex shader, and no mesh: SwiftUI's `[[stitchable]]`
      colour shaders sample textures as arguments, so the whole fold is one function
      over two `texture2d<half>`s. A vertex shader would need a mesh to deform, and the
      fold contributes no geometry the projection cannot express per pixel.

      No rastering for comics, per `comic-reader`: the page is already a `CGImage`, and
      the shader takes it directly. Rastering is only the reflowable case, which is
      4.3b.

      **The number is still missing, and it needs a device.** A frame rate measured on
      a simulator running on a Mac's GPU is not a frame rate, and the machine here has
      no 120 Hz iPhone attached. What *is* verified is that the shader compiles and
      lands where SwiftUI looks for it: `pageCurl` is a stitchable symbol in
      `StoryArcKit_ReaderFeature.bundle/default.metallib`, with the expected texture
      and float arguments.

      One consequence for anyone building this repo: `ReaderFeature` now compiles a
      `.metal` file, and the Metal toolchain is not part of a default Xcode install.
      `xcodebuild -downloadComponent MetalToolchain`, ~690 MB, recorded in
      `apps/ios/README.md`.
- [x] **0.4** **Android curl spike.** Express the same cylindrical projection as
      an AGSL `RuntimeShader` at API 33+, using `oleksandrbalan/pagecurl` as a
      geometry reference. Measure the frame rate; verify a settling animation can
      be taken over mid-gesture.
      Deliverable: a number, and a go/no-go.

      **Go, and the spike turned into the implementation** — see 4.3. Three findings
      worth keeping:

      1. **Not a cylinder.** The task says "cylindrical projection", and a cylinder
         was authored first. Seen straight down, a folded page shows two things and
         hides a third: the un-turned part, the turned part lying face-down on it, and
         the crease — which is edge-on and contributes *no pixels* from directly
         above. Every convincing 2D curl therefore *shades* the crease rather than
         projecting it. Claiming a cylinder here would be claiming geometry that draws
         nothing.
      2. **A brush, not a `RenderEffect`.** `createRuntimeShaderEffect` binds the
         *view's own* content to one input, which is the wrong shape: a turn needs two
         pages at once. Two `BitmapShader`s into one `RuntimeShader`, drawn as a brush,
         is `comic-reader`'s "uses the already-decoded page directly rather than a
         re-raster" in code.
      3. **No number, and the reason matters.** A frame rate measured on an emulator
         running on a Mac's GPU is not a frame rate. The shader is a few texture reads
         and one `exp` per pixel, so the API-33 capability gate is the real gate — and
         a frame-rate check with no device that fails it would be speculative
         complexity. If such a device turns up, the check belongs then.

      Interruption is `Animatable.stop()` before a new drag, which is the documented
      mechanism: it leaves the value where it stands rather than queueing behind the
      running spring. Consistent with what the frames show; a proper demonstration is
      7.5's recording, because a still cannot show it.
- [x] **0.4b** Verify the API-33 gate end to end on an API 31 emulator: Curl
      absent, Slide default, reason stated once, and a stored Curl preference
      left intact rather than overwritten. **Verified by substitution, not on API 31.**

      `canCurl` is a constructor parameter, so passing it `false` on the API 35
      emulator exercises every consequence of the gate — which is all four clauses of
      this task:

      - **Curl absent**, not disabled: the picker offered Slide, Fast fade and both
        scroll rows and no Curl row at all.
      - **The reason stated once**, as a sentence under the list: "Curl is not offered
        here: this device cannot draw it smoothly enough to be worth it." No API level
        named, which is what the spec asks for.
      - **Slide the default**: a comic whose *stored* mode was `PAGE_CURL` opened and
        rendered, paged.
      - **The stored preference intact**: `FIXED_LAYOUT/natural-sort` still reads
        `PAGE_CURL` afterwards. `TransitionChoices` falls back rather than rewriting,
        and this is that on a device rather than in a test.

      What is *not* verified is the `Build.VERSION.SDK_INT` comparison itself — one
      line, and the only part a stand-in cannot reach. Downloading a 1.5 GB API 31
      system image to confirm a version comparison is a poor trade against three unit
      tests plus the above; if an API 31 AVD ever exists here, it is one run.

      A footnote on the method, because it nearly produced a false alarm: `grep -c`
      counts *lines*, and the whole preferences blob is one line. It looked for a
      moment as though a stored preference had been overwritten. It had not.
- [ ] **0.5** Procedural paper grain: prototype on both platforms and judge
      whether it reads as paper. If not, price a bundled tiling texture. **Built,
      not judged.** The shader exists on both platforms and is wired to the page —
      see 5.4, which carries the three parameters and how confident each is. What
      remains is the half this task is actually about: looking at it. A bundled
      tiling texture stays the fallback if the answer is that it reads as digital.
- [x] **0.6** Record the spike outcomes as an ADR — the curl decision is exactly
      the kind of thing that gets re-litigated in six months without one.
      **Done**: [ADR-0009](../../../decisions/0009-page-curl-as-a-fragment-shader.md).

      It records the two ways the spikes contradicted the plan — a fragment shader
      rather than a vertex shader and a mesh, and a fold rather than a cylinder,
      because the crease contributes no pixels — and the two things that are *not*
      settled: the frame-rate number, and rastering for reflowable content.

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
- [x] **3.6** Live preview rendered by the **real** renderer, showing a chapter
      title and body text, reflowing continuously during a drag. **Done, and what
      "the real renderer" turned out to mean is worth stating exactly, because it is
      not what the word first suggests.**

      It is a web view — `WKWebView` on iOS, the system `WebView` on Android — which
      is precisely what Readium paints a reflowable page in. It is **not** a second
      Readium navigator over the publication's own resources.

      The requirement's own preview content is what settles that. It asks for "a
      chapter title and at least three lines of body text", which is a *constructed*
      specimen; a navigator renders the resource at a locator and nothing else, so it
      can show a page but never that. "The same engine that renders the publication"
      is therefore the layout engine, and this is it: the same WebKit and the same
      Blink that lay out the page a moment later, given the same axis values.

      Two things are given up by not being a navigator, and both are named in the
      code as well as here:

      - **The publisher's stylesheet is absent.** Under any preset but Original that
        is what the reader asked for — `publisherStyles` is off and StoryArc's values
        win. It is a real gap only under Original, where the preview shows the
        browser's defaults rather than the publisher's design.
      - **ReadiumCSS itself is absent.** Its resets and its `--USER__*` plumbing are
        not reproduced; the same *numbers* are emitted as plain CSS. Where ReadiumCSS
        does something StoryArc's values do not describe, the page has it and the
        preview does not.

      What keeps "the same engine" from decaying into "roughly the same" is a test,
      not an intention. On iOS every axis is asserted against the `EPUBPreferences`
      the same theme produces — font size, line height, letter and word spacing,
      paragraph spacing, margins, alignment, hyphenation, colours — so the document
      and the page cannot compute one differently. Android cannot make that half:
      `EpubPreferences` needs a device, so `ThemePreviewDocumentTest` holds the same
      strings instead, which is what keeps the two documents identical.

      **The words are the publication's**, which is the requirement's other half.
      Both readers already had the resource read a bookmark's excerpt uses; the
      preview asks the same code for a longer slice at the same position, once when
      the sheet opens — a disk read inside a slider drag is a disk read inside a
      slider drag. A publication it cannot be read from falls back to sample text,
      in all four locales.

      The bundled type resolves in both previews, which needed two different answers.
      Android reaches its own staged assets through `file:///android_asset/`, which
      stays readable whatever `allowFileAccess` says. iOS serves the same files
      through a `WKURLSchemeHandler`, because `WKWebView` refuses a `file:`
      subresource under a document loaded as a string and the alternatives were
      copying two megabytes of type into a cache directory or rebuilding a base64
      face on every keystroke. Without the declaration the family silently falls back
      — which would make the preview disagree with the page on the most visible axis
      there is.

      Fixed at 200 points, deliberately *not* growing with the text size. The delta
      asks the preview to stay "large enough to judge a spacing change" at large
      text, and on a sheet that grows every point the preview takes is a point the
      controls below it lose.

      One Kotlin trap, recorded because it produced a wrong document that compiled:
      `trimIndent()` runs *after* interpolation, so a stylesheet's own unindented
      lines set the common indent to zero and every line keeps the indentation it was
      written with — including the doctype, which is then not the first thing in the
      file. The document is assembled line by line instead, and the test asserts the
      prefix.

      Two things moved to keep `EpubReaderActivity.kt` under its recorded length:
      `ThemeBottomSheet` left it for `ThemeSheet.kt`, where the sheet it wraps already
      lives, and the activity came out 34 lines shorter than it went in.

      **Not verified on a screen.** `pnpm test:ios:epub` needs a booted simulator this
      worktree does not own, so the iOS half compiled (`build-for-testing`) and did
      not run. See 7.4 for what to capture.
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

      **The global default now has a screen**: `settings-and-about-screens` task 2.3,
      with a scope each for books and for comics. Verified on the emulator by reading the
      store before and after — a new default left every per-series choice untouched,
      which is structural rather than careful, because the two live in different maps.

      **Still held:** the comic reader hard-codes black, so the fixed-layout scope has no
      reader taking its colours from it. See 3.11.
- [x] **3.8** Tablet: popover on iPadOS, expanded anchored sheet on Android, with
      the reader still visible. **Done, and mostly by declaring the right thing
      rather than by writing two layouts.**

      iOS presents the sheet as a `popover` anchored to the theme button, with
      `presentationCompactAdaptation(.sheet)` — so a tablet gets a popover and a phone
      gets the detented sheet back. Writing the two presentations separately would
      mean maintaining the phone one twice. A popover has no detent to size it, so it
      carries an ideal size instead: wide enough for the preset grid, narrow enough
      that the page stays readable beside it.

      Android needed nothing. Material 3's `ModalBottomSheet` caps itself at 640 dp
      and centres, which *is* the expanded anchored sheet the spec describes.

      Verified on the emulator, resized to 1600×2560 at 320 dpi — the library goes to
      five columns and the sheet sits centred at its cap with the page visible above
      and either side of it. The iPad popover is not verified: the simulator accepts
      no injected input, which `apps/ios/README.md` records, so the reader cannot be
      reached to open it.
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

- [x] **3.11** **The custom background around a fixed-layout page.** The last
      scenario of 3.7: a custom background "applies to the area around the page and
      not to the page itself, because tinting artwork is not a reading preference".
      **Done on both platforms**, in `settings-and-about-screens` task 5.2 — the matte
      needed somewhere to be *set* before it was worth painting.

      Two decisions worth keeping. The artwork is drawn over the matte untouched, which is
      the whole requirement: tinting the art would be tinting someone else's drawing. And
      a *preset* deliberately does not reach the matte — a comic has no typography for a
      preset to change, so all a preset could offer is its paper colour, and that is not
      what a preset means. Only a colour the reader chose explicitly applies.

      Verified on the emulator: pale green above and below the page, blue artwork over it,
      unchanged.

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
- [ ] **4.3** Curl, per the Phase 0 outcome. Finger-tracked, interruptible, lit
      edge, cast shadow, mirrored for right-to-left. Metal on iOS, AGSL on
      Android at API 33+. **Android done and verified; iOS built but unverified.**

      One AGSL shader over two decoded pages, driven by an `Animatable` so that a new
      drag during the settle takes over from where the page is. Right-to-left is a
      coordinate flip inside the shader rather than a second shader.

      Verified on the emulator, frame by frame with held `motionevent` gestures:

      - the crease tracks the finger, at 55% and then 37% of the width as the finger
        moved;
      - the turned sheet shows the page's *back* — the same pixels mirrored about the
        crease and dimmed to 55%, because a mirrored image at full brightness reads as
        a reflection rather than as paper;
      - the leading edge catches light and the revealed page is darkest against the
        crease, which is the only place a lifted page can cast a shadow;
      - releasing past halfway completes the turn: page 4 became page 5;
      - a right-to-left publication curls from the *left* edge with the gesture
        mirrored.

      Three bugs found on the way, all instructive:

      1. **The regions were inverted.** The turned sheet lies *left* of the crease and
         the reveal is right of it — the material that used to lie ahead of the crease
         is what folds back over the page behind it. Getting it backwards renders the
         *next* page at rest, which is how the mistake announced itself.
      2. **`CLAMP` smeared the edge pixel across the letterbox.** Outside the page
         there is nothing, so the tile mode is `DECAL` and the canvas paints black
         first — the same black the other three modes show there.
      3. **The release decision read a stale progress.** Driving the `Animatable` from
         the drag means launching a coroutine per move event, and those had not run by
         the time the finger lifted, so every turn sprang back. The reached fraction is
         now kept in the gesture loop, where the decision is made.

      A fourth belonged to the seam rather than the curl: a `PagerState` with no pager
      laid out has nothing to scroll, and asking it to animate does nothing at all.
      Curl and Fast fade now share the container-less `Paging.Indexed`.

      **iOS is built and compiles, and is not visually verified.** The Metal shader is
      the AGSL's twin down to the constants, which is what `design.md` asks for — one
      projection expressed twice rather than solved twice. The gesture is a
      `DragGesture` using SwiftUI's own `predictedEndTranslation` as the flick model
      rather than a velocity calculation of ours.

      What is verified: it compiles, and `pageCurl` is a stitchable symbol in the
      feature bundle's `default.metallib` where `ShaderLibrary.bundle(.module)` looks
      for it. What is not: anything visual or tactile, because the simulator accepts no
      injected input — the limitation `apps/ios/README.md` already records. That is
      7.4's and 7.5's job, and it needs a device or a person.
- [ ] **4.3b** Page rastering for reflowable content: raster at display scale,
      hold at most the outgoing and incoming pages, restore live interaction the
      instant the turn completes. **Still the remaining hard part, and now visible in
      the product rather than only in this file**: the ebook reader's page-turn section
      lists Curl and Fast fade with "not available yet for text that reflows: it needs a
      picture of the page". Both readers offer the other two modes fully.

      **Apple Books does this, so the approach is proven rather than hypothetical.** A
      reader sent a screenshot of Apple Books mid-curl over reflowable French text: the
      fold is lit, the crease shades, and the *back* of the turning page carries the
      page's own text mirrored. That last detail is the evidence that matters — it is
      exactly what `page-transitions` asks for when it says "the turning page is a
      faithful raster of the page it replaces", and it means Apple is deforming a texture
      of live web content rather than doing something a third-party app cannot.

      **The raster is only half the work, and probably the smaller half.** Readium owns
      the turn. `EpubReaderModel.goForward()` and `goBackward()` exist on both platforms
      and have *zero callers*: Slide is Readium's own paginated scroll animation, and
      `ReadiumMapping` says so. Nothing in StoryArc is holding the turn at a fraction
      between two pages, because nothing in StoryArc is running the turn.

      So Curl and Fast fade need StoryArc to take the turn over:

      1. Consume the gesture itself, rather than letting Readium's paginated scroll have
         it.
      2. Raster the outgoing page.
      3. Move the navigator with `animated: false`, so Readium changes the content without
         animating it.
      4. Run our own animation over the raster — the shader for Curl, a cross-fade for
         Fast fade.

      Fast fade needs one raster and Curl needs two, so **Fast fade is the cheaper first
      step and should land first.** Curl additionally needs the incoming page before it is
      on screen, which means either a second offscreen navigator or a snapshot round-trip,
      and that is the part worth prototyping before committing to.

      With that said, the remaining open question is *when to snapshot and what it costs*:

      - **iOS:** `WKWebView.takeSnapshot(with:)` is asynchronous and returns a `UIImage`;
        `UIView.drawHierarchy(in:afterScreenUpdates:)` is synchronous and cheaper but
        blocks. A turn cannot wait on an async snapshot at the moment the finger moves,
        so the outgoing page has to be rastered *before* the gesture begins — which means
        on settle of the previous turn, not on demand.
      - **Android:** a `WebView` draws to a `Canvas`, so a `Bitmap` is one `draw` call.
        The same timing problem applies.
      - **Both:** the raster must be at display scale or the curl shows a soft page
        against sharp chrome, and ADR-0009's shader already takes two textures — so the
        shader itself needs no change. This is a source problem, not a rendering one.

      The reader's wording was corrected at the same time. "Not available" reads as a
      property of the format; "not available yet" is what is true.

      **iOS Fast fade is done.** `ReflowableTurn.swift` plus
      `EpubReaderModel.turnWithFade(forward:)`: its own tap and pan recognisers, a
      `snapshotView` of the outgoing page, `goForward(animated: false)`, then the still
      fades. `canFade` joins `canCurl` as a platform capability so the two readers can
      disagree honestly.

      **Android Fast fade is bounded, and here is the boundary.** It is harder than iOS,
      for one specific reason:

      - iOS: `PaginationView.isScrollEnabled` is internal, but the paginated container is
        a `UIScrollView` and `isScrollEnabled` on *that* is public. One line disables
        Readium's swipe and our own recognisers take over.
      - Android: `EpubNavigatorFragment.resourcePager` is a **public field**, which is
        better — no hierarchy walk needed. But it is an `R2ViewPager`, which extends the
        old `ViewPager` and exposes no input switch. `javap` shows only
        `setCurrentItem(int)`, `onTouchEvent` and `onInterceptTouchEvent`. There is no
        `isUserInputEnabled` as `ViewPager2` would have.

      So Android needs a touch-interception layer over the `FragmentContainerView` that
      consumes a horizontal drag past a threshold and passes everything else through — link
      taps and text selection must keep working, which is what makes it fiddly rather than
      long. `drawToBitmap` on the container gives the still directly, because Android's
      WebView renders in process.

      **That landed.** `ReflowableTurn.kt` carries the `TurnInterceptor` this note
      describes, and `EpubReaderViewModel.transitions` passes `canFade = true` on both
      platforms. Fast fade over reflowable text is built on both; Curl over it is not,
      which is the one thing 4.3b still owes.

      Reverify against Apple Books when the curl is built: the crease, the lit edge, and
      the mirrored text on the back are the three things to compare.
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

      **And for reflowable text, where scroll is Readium's own preference rather than a
      container of ours.** `EPUBPreferences.scroll` existed and was unwired; a scroll
      view of ours over a web view that already paginates would be two things fighting
      for the same gesture. The ebook reader's theme sheet now has a page-turn section
      offering Pages and Continuous scroll, with Curl and Fast fade listed and marked —
      which is the spec's "a mode is unavailable for the content" scenario, and 4.3b's
      absence stated in the interface rather than left to be discovered.

      One row, not two, for reflowable text: prose scrolls the way it is read, and a
      horizontal river of it is not a preference anyone holds.

      **This surfaced a real defect**, recorded here because it was invisible until
      scroll mode existed: in scroll mode Readium reports a total progression of `0.0`
      rather than nothing, so the fallback keyed on *absence* never fired and the reader
      sat at "0% read" through a whole chapter. Worse, that zero was what got stored.
      `TotalProgression` in the domain now decides it — a reported zero that the
      position contradicts is not a report — with six tests each side. Verified on the
      emulator: 37% read at the point the test predicts 37%.
- [x] **4.5** Boundary rubber-band at the first and last page. **Done by the
      platform, which is the right rung to stop on.** Every mode that has a drag has
      one from the container: `HorizontalPager` and `LazyColumn`/`LazyRow` on Android,
      `TabView` and `ScrollView` on iOS, all with their own overscroll. Fast fade has
      no drag to resist, and a tap past the last page reaches the end screen
      `comic-reader` asks for rather than a rubber-band.

      Hand-rolling this would replace four correct platform behaviours — including
      each one's feel and its own accessibility settings — with one of ours.
- [x] **4.6** Turn triggers: tap zones, keyboard, external controller, optional
      volume buttons. **Done except the volume buttons.**

      Tap zones and the keyboard are in both readers — arrows, page up and down, and
      space. An external controller needs nothing more: a d-pad and shoulder buttons
      arrive as the same key events, which is why the keyboard path is the controller
      path.

      Volume buttons were held on the spec's own wording — "the volume buttons **where
      enabled in settings**" — because there was no settings screen to enable them in.
      **There is now**, and they work: `settings-and-about-screens` task 5.1, verified on
      the emulator with the setting both off and on.

      iOS cannot honour them at all. The system owns those buttons, and the only way round
      it is a trick App Review has rejected. The Reading group says so rather than
      offering a switch that does nothing — the same "absent where the platform cannot
      honour it" clause the curl uses.
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
- [x] **4.8** Placeholder at the correct aspect ratio when the destination page is
      not yet decoded. **Done, and it only ever mattered in one mode.** In a paged
      mode the page is screen-sized whether or not it has decoded, so there was
      nothing to hold. In a stitched scroll a screen-sized placeholder becomes a
      page-sized item the moment it decodes, and every page below it lurches — so a
      stitched placeholder holds a page's shape instead.

      Two by three, because the page's real proportions are unknown until it is read
      and a comic page is close enough that the difference is not what a reader
      notices. An item that changed height by half again is.
- [x] **4.9** Absent-Curl path: hide Curl where the device cannot honour it —
      Android below API 33, and any device failing the frame-rate check — default
      to Slide, state the reason in plain language without naming an API level,
      and leave a stored Curl preference untouched. **Done.**

      This note used to end "and currently that is every device, because the curl does
      not exist yet: `canCurl` defaults to false on both platforms". That stopped being
      true when 4.3 landed and was never corrected. The comic readers now pass a real
      answer — `Build.VERSION.SDK_INT >= TIRAMISU` on Android
      (`ReaderViewModel.kt:89`), `true` on iOS, whose floor is 26 — so the absent-Curl
      path is the API-31-and-32 path rather than every device.

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

- [x] **5.1** Extend `AppearanceMode` to System / Light / Dark / OLED Dark on
      both platforms. **Done**, and it landed in `settings-and-about-screens` task 1.2
      rather than here, because a fourth appearance with nowhere to select it is dead
      code. The type, the palette and the tests are on both platforms; the screen that
      offers it belongs to that change.

      Natural is deliberately *not* a case. The spec calls it "a theme rather than an
      appearance… carries its own light and dark variants", so a case here would force
      a choice between Natural and dark mode that the spec exists to avoid. A test
      asserts its absence, so a future hand does not helpfully add it.
- [x] **5.2** Natural as a theme with its own light and dark variants: accents
      app-wide, grain confined to reading surfaces. **Done.** The tokens have carried
      `naturalLight` and `naturalDark` since 1.2 and nothing read them; this is what
      reads them. The grain half is 5.4.

      **Where Natural lives, and why it is not an appearance.** It is a second axis
      crossed with the first: `AppearanceMode` answers *which polarity* — which end of
      light and dark, or follow the device — and Natural answers *which texture*. So
      the Appearance screen keeps its four radio rows and gains a switch below them,
      and System, Light and Dark each acquire a Natural variant. 5.1's reasoning is
      unchanged and its two tests are untouched: a fifth case would force the choice
      between Natural and dark mode that the spec exists to avoid.

      It is not a reading theme either. A `ThemePreset` reaches the page and stops
      there; `design.md` asks Natural's accents to reach "the library, settings and
      source list" so the theme is coherent rather than bolted onto the reader.

      **OLED Dark declines it.** Warm cream stock and true black are opposite asks,
      and true black is the whole reason that appearance exists — a Natural canvas at
      `#16100C` would quietly break the promise. So the switch is *disabled with the
      reason on screen* rather than hidden or left live and inert, which is the
      treatment dynamic colour already gets under the same appearance.

      **On Android, Natural also overrides Material You**, for the same shape of
      reason OLED Dark does: a wallpaper-derived tonal wash beside a clay accent is
      two themes at once. The dynamic-colour row gains a third note saying so, so no
      switch on that screen silently does nothing.

      The accents are `clayStrong` on paper and `clay` on ink — `pnpm tokens:check`
      already gates both at 3:1, which is why no token moved for this. `accentMuted`
      takes `clayStrong` on both variants rather than a `clayMuted` that does not
      exist: its only reader is the settings-search highlight at 30 % alpha, and
      inventing a token no contrast gate covers to serve one wash is the worse trade.

      **The stored value is its own key, not a field on `AppSettings`.** Storing an
      independent axis inside the field it is independent of is how a boolean ends up
      encoded in an enum a year later; and reading it inside the theme resolver —
      `@AppStorage` on iOS, a shared Compose state over `SharedPreferences` on Android
      — leaves every existing call site of the theme entry point untouched.
      `ReaderPreferences` already set the precedent that a preference can live outside
      `AppSettings` when the type that reads it is not the settings screen. Both
      platforms use the same key name, `storyarc.appearance.natural`.

      Search reaches the row by what a reader wants rather than what the screen calls
      it — natural, paper, grain, texture, warm — in both mirrored indexes.

      **Not verified on a screen.** See 7.4.
- [x] **5.3** OLED Dark: true black chrome, reader surface deliberately above
      true black, with the reason surfaced in the setting. **Done.** The tokens already
      carried an `oledDark` palette whose `surfaceReader` refuses to be `#000`, with
      the reason in `color.json` — so this was wiring, not design, and the reason is
      not repeated in code because a reason in two places drifts.

      The reason is now also a *string*, which is what "surfaced in the setting" means:
      `AppearanceMode.localizedNoteKey` is non-nil for OLED Dark alone, and a test
      asserts the other three have none, because an explanation on all four is noise.

      One thing the wiring had to decide: dynamic colour and true black are
      incompatible asks. Material You derives its surfaces from the wallpaper, and a
      wallpaper-tinted "true black" is neither, so the explicit choice wins over the
      automatic one.
- [x] **5.4** Natural grain as procedural noise on reading surfaces only,
      disabled automatically under Reduce Transparency or Increase Contrast, and
      absent below API 33 on Android with the palette retained. **Built on both
      platforms.** 0.5 asked for a prototype and none was made, so the shader and the
      thing it draws landed together — but 0.5's own question is a *judgement*, and
      that still needs a screen. See the parameter table below and 7.4.

      Procedural noise rather than a bundled tile, which is what `design.md` chose:
      cheaper, resolution-independent, no bytes. One hash, two octaves at 2.17× so the
      two lattices never line up, and a warm/dark tint pair rather than symmetric
      grey — grey speckle reads as sensor noise, which is the one thing this must not
      look like. The Metal and the AGSL are one texture expressed twice, down to the
      constants, the way the curl already is.

      **Where it draws.** Between the page and the chrome: over the words, under the
      app bars. On Android it is emitted by `EpubChrome` rather than beside it, and
      deliberately *outside* the visibility that hides the bars — the texture belongs
      to the paper, and paper does not come and go with a tap. It is not interactive
      and not spoken.

      **Three refusals, in one function per platform** so no screen decides for
      itself: Natural off, Reduce Transparency on, Increase Contrast on. The last two
      are not preferences — grain is a per-pixel modulation of the page, so it eats
      contrast from every letterform on it. Android has no transparency switch, an
      absence `DetailAccent` already recorded for the same requirement, so contrast is
      the whole answer there. What Android has instead is the API 33 floor
      `RuntimeShader` imposes, below which the palette stays and the texture goes; the
      level is a parameter so a unit test reaches the comparison, which is the trade
      0.4b made for the curl.

      **The three numbers I am unsure of**, named in one file per platform with what
      each does:

      | Number | Value | Confidence |
      | --- | --- | --- |
      | Peak alpha of a speck | `0.045` | **Lowest.** Move this first. High enough to read as stock, low enough that body text at the smallest step does not sit in it — judged from arithmetic, not from a panel. |
      | Noise cell, in **device pixels** | `1.5` | Below about 1 it aliases against the panel grid and shimmers on a scroll; above about 2.5 it stops being fibre and becomes dots. Device pixels rather than points or dp, so a 2× phone and a 3.5× phone show one paper. |
      | Finer octave's share | `0.35` | Least risky: it changes the *character* of the grain rather than how much there is. |

      A test on each side asserts the three are equal across platforms, so a
      screenshot that moves one moves it in both files or the build says so.

      **What has no grain.** The comic reader: `ReaderFeature` and `feature/reader`
      are outside this change's file set. And the reading theme's own background still
      reaches the page untouched — grain is drawn *over* whatever colour the reader
      chose, never instead of it, which is what keeps "the reading theme is not
      overridden" true.

      **Not verified on a screen, and this is the task that most needs one.** See 7.4.
- [x] **5.5** Opt-in setting linking app appearance to reading theme; off by
      default. **Done on both platforms**, in `settings-and-about-screens` task 5.3 —
      the toggle needed a settings screen to live on.

      Light maps to Paper and every dark appearance to Quiet. Two presets rather than four,
      because the difference between Dark and OLED Dark is the *chrome*'s black point and a
      reading surface is deliberately never pure black — so mapping OLED Dark to something
      darker would undo the reason that appearance exists.

      The shelf's stored theme is not overwritten on open, so turning the setting off brings
      it back. Adjusting a theme while linked does record it, which is the reader changing
      their mind on purpose.

      Verified on the emulator in dark mode: link off kept the page Calm — the spec's own
      default — and link on made it Quiet with Calm still stored.

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
      assets on Android. **The screen that displays them now exists**, in
      `settings-and-about-screens` task 4.3: Settings › About › Acknowledgements lists
      every component from one shared inventory and renders each licence in full. Verified
      on the emulator with the SIL Open Font Licence.

      That closes the gap this note used to record — the files being in the bundle is what
      the licence requires, and the screen is what the spec requires.
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

- [x] **7.1** `pnpm lint` — specs and token contrast, including all six presets.
      Green, and the contrast gate now has a runtime counterpart: `ReadingContrast`
      asserts the same numbers with the same constants, so the gate and the sheet
      cannot disagree (see 3.7).
- [x] **7.2** `pnpm test:ios` and `pnpm test:android`. Green — 305 tests on iOS
      across 37 suites, and the Android twin asserts the same tables.
- [x] **7.3** `pnpm lint:android`, `swiftlint --strict`, both app builds. Green.
      `swiftlint --strict` found two files over the 400-line limit while this change
      was being built, and both were split rather than exempted: `ReaderView` gave up
      its containers and its chrome, and the theme tests gave up the palette and the
      shelf memory.

      These three are re-run on every commit rather than at the end, which is why they
      are ticked here — `pnpm check` runs all of them.
- [ ] **7.4** **Visual proof.** Simulator and emulator screenshots of the theme
      sheet and all six presets, in light and dark, at default and largest text
      size. A `#Preview` is not proof. **Android done; iOS blocked on a device.**

      Four captures in `docs/designs/screenshots`, from a booted emulator:
      `android-theme-sheet-{light,dark}.png` and
      `android-theme-sheet-{light,dark}-largest.png`. All six presets appear in one
      shot rather than six, because the grid previews each in its own colours *and*
      typeface — which is the thing worth proving.

      Two of them are now in the root README as well. An empty library was the whole
      first impression of a project that reads books, curls pages and carries five
      typefaces.

      iOS cannot be captured: the simulator accepts no injected input, so the reader
      cannot be reached to open the sheet. `apps/ios/README.md` records the three
      approaches that were tried.
- [ ] **7.5** Record the curl: a screen recording on each platform, because a
      still frame cannot show interruptibility or finger tracking.
- [ ] **7.6** Accessibility pass: VoiceOver and TalkBack over the sheet, Reduce
      Motion, Reduce Transparency, largest text size. **Two of the four done on
      Android, and each found something.**

      **Reduced motion** — `animator_duration_scale 0` on the emulator. The page-turn
      rows behave exactly as the spec asks: Curl and Pages stay *listed*, marked
      "Unavailable while your system is set to remove animations", and Continuous scroll
      stays available because a scroll is not an animation.

      It also exposed an ordering bug. Reduced motion turns Slide into Fast fade, and
      over reflowable text Fast fade is itself impossible — so with the content check
      *before* the substitution, `effective` named a mode the publication refuses.
      Content is the only constraint nothing can work around, so it is applied last.
      One test each side.

      **Largest text size** — `font_scale 2.0`. Two real defects, both fixed:

      1. **The typeface specimens clipped.** A specimen is a *picture* of a typeface and
         its card is a fixed height, so scaling it with the system text size showed
         *less* of the face the larger a reader needs it. Sized in `dp` on Android and
         `fixedSize:` on iOS.
      2. **The preset grid clipped its labels.** A `LazyVerticalGrid` inside a scrolling
         column needs a fixed height, and at twice the text size the labels fell off the
         bottom. Six known items in a scroll never needed a lazy grid — two `Row`s take
         the height their content asks for, which is less code as well as correct.

      The library also holds at 2×: titles wrap and ellipsise, captions stay top-aligned,
      nothing overlaps.

      **TalkBack driven for real — and it found three defects on its first screen.**
      Enabled on the emulator with `settings put secure enabled_accessibility_services`,
      which changes the interaction model: one tap moves accessibility focus and a double
      tap activates. What it exposed:

      1. **A comic page announced its file name.** TalkBack said "page10.png", which names
         a file inside a CBZ. It says "Page 10 of 12" now, on both platforms.
      2. **The chrome drew a white icon on a 20% white pill, over page art.** Over a white
         manga page that measures 1:1. Every pill and the bottom band carry a scrim now.
      3. **A colour swatch announced its hex.** "Colour #E8EFE6", read one character at a
         time. The names moved from a code comment into core, where both platforms read
         them.

      None of the three was visible in a screenshot, which is why `pnpm a11y:android` now
      exists: it reads the accessibility tree off the device and reports an unnamed
      control, a name that is a raw value, and a target under 48dp. Every settings screen,
      the library, the reader page and the reader chrome report zero problems.

      **The contrast floor moved, and Apple's own audit is why.** `textTertiary` failed
      WCAG AA in 10 of 15 palette and surface combinations. Fixed to exactly 4.5:1, at
      which point `performAccessibilityAudit` reported "Contrast nearly passed" — a token
      sitting on the threshold fails the platform's check while passing ours. Every text
      role now clears 4.9:1.

      **Still open: VoiceOver driven by a person, and Reduce Transparency.** VoiceOver has
      been *audited* — a UI test target runs Apple's own `performAccessibilityAudit` — and
      that is not the same as listening to it. Reduce Transparency has no emulator switch
      that reaches a Compose equivalent, and iOS needs a device. Neither platform has been
      checked by anyone who uses a screen reader daily, which is the actual bar.
- [ ] **7.8** **Compare Readium's pagination across the two toolkits** under
      matched typography, on `fixture.epub`. Added here because this change is what
      unblocked it: [ADR-0005](../../../decisions/0005-format-and-rendering-libraries.md)'s
      spike 4b has been waiting for the type controls, and now the same nine axes can
      be set to the same values on both platforms.

      What matters is not that the page *counts* match — they cannot, since the two
      toolkits lay out in different web views — but that a stored locator resolves to
      the same paragraph, and that a size change moves the reader by a comparable
      amount. A divergence here would undermine `reading-progress`' promise that a
      position is portable between devices.
- [ ] **7.7** `/opsx:sync` to merge the delta specs into the main specs.
      **Partly done: everything that shipped is merged, four things are held.**

      The two links `docs/design.md` was holding now resolve —
      `openspec/specs/reading-themes/spec.md` and
      `openspec/specs/page-transitions/spec.md` both exist.

      Waiting for the whole change to finish had a cost that had grown too large to
      keep paying: `ebook-reader`'s *Theme choice* scenario still named Paper, Sepia,
      Night and High Contrast, three of which have not existed under any name since
      1.5 deleted `ReaderTheme`. Anyone reading the contract alone mis-scored that
      scenario in both directions.

      **Merged**, because it is built on both platforms: both new capabilities
      (`reading-themes` less its *Live preview* requirement, `page-transitions` less
      one scenario); `ebook-reader`'s eleven axes, two-depth sheet, publisher-styles
      coupling, six presets and preset grid; `comic-reader`'s *Reading modes*
      requirement retired in favour of *Page transitions in the comic reader*;
      OLED Dark and the appearance-to-theme link in `settings-and-about`; and
      `native-experience`'s reader chrome material, preset grid and theme-sheet
      reachability.

      **Held back, and why:**

      1. **`reading-themes` › *Live preview*** — task 3.6. There is no preview inside
         the sheet. The preset cards preview each theme's colours and face, which is a
         different thing, and the page *behind* the sheet updates live, which is the
         part that shipped. `ebook-reader`'s *Typography controls* keeps the
         live-preview clause it already carried — it is a promise the spec made before
         this change and this sync neither strengthens nor withdraws it — but it is now
         a separate bullet from the built one, so the two can be scored apart.
      2. **`page-transitions` › *Curl on reflowable content*** — task 4.3b. Curl over
         a reflowable page needs the page rastered first and nothing rasters it. Both
         readers refuse Curl for reflowable content and say why, which is the
         *A mode is unavailable for the content* scenario doing its job.
      3. **`comic-reader` › "a double-page spread curls as one surface"** — the curl
         container takes one decoded page (`ReaderContainers.swift:22`,
         `CurledPages.kt`) and knows nothing about the spread layout the paged and
         scroll containers use. In spread mode a curl turns one page.
      4. **`settings-and-about` › Natural** — tasks 5.2 and 5.4. `naturalLight` and
         `naturalDark` exist in the tokens and on both platforms as generated colours,
         and nothing selects them: `AppearanceMode` has four cases and a test asserting
         Natural is not a fifth. An appearance no reader can reach is not an
         appearance, so the row and the *Natural carries texture* scenario stay here.

      **One clause was added that the delta did not have.** `page-transitions` ›
      *Hardware input* now says that where a platform does not let an app observe the
      volume buttons, no setting is offered and the reason is stated once. That is
      what both apps do — Android offers the switch, iOS's Reading group explains why
      there is none — and without it the scenario reads as a gap on iOS rather than as
      the platform decision it is.

      **Two notes elsewhere in this file were stale when checked against the code**,
      and are corrected in place: 4.9's "currently that is every device", and 4.3b's
      account of Android Fast fade.

      Tick this when 3.6, 4.3b, 5.2 and 5.4 land and the four held items go in.
