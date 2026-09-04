# Tasks — brand identity and app icons

Test-first throughout. A visible change owes a before/after capture per
[`AGENTS.md`](../../../../AGENTS.md) §6 — and for this change the *icon itself* is the visible
thing, so a rendered tile at the size a home screen draws it is the proof.

`design.md` carries every measured number: the sampled brand colours, the chosen OKLCH values
with their contrast readings, the rename's 56-reference cost, the mark's proportions, and the
two platforms' mechanisms with the constraints each imposes. Read it before this list.

## 1. The accent moves, and the tokens are renamed to their role

- [x] 1.1 `packages/design-tokens/tokens/color.json`: the eight-token set in design.md's
      table. `ember`/`emberStrong`/`emberMuted` become `accent`/`accentMuted` plus
      `secondary`/`secondaryStrong`; `ink` **retires** — it is Material's `secondary` in
      `Theme.kt` and would sit 20° from the new accent. Add `arcMid`, `arcLate`, `arcEnd`,
      `iconPlate`. Keep every `use` note but rewrite the amber and indigo language.
      **The accent is the violet, not the pink**, and design.md records why the first draft
      had it the other way round: one value clears both themes (4.06 dark / 4.43 light) where
      the pink fails light at 2.48, and "chrome recedes" argues against hot pink on every chip.
- [x] 1.2 Update the contrast gate in `packages/design-tokens/scripts/build.mjs` to the new
      names, and **add a row the old set did not need**: `accent` is gated on *both*
      `dark.surfaceCanvas` and `light.surfaceCanvas`, because it is now one value serving both.
      **Do not relax a threshold.** Every value was chosen so the 3.0 floors pass with margin —
      4.06, 4.43, 7.24, 3.72. If one fails, the value is wrong, not the gate.
- [x] 1.3 `pnpm tokens:build && pnpm tokens:sync`, then `pnpm tokens:check` and
      `pnpm tokens:verify`. Both are in `pnpm lint`.
- [x] 1.4 Fix the hand-written call sites the compiler names: Android `Theme.kt`, iOS
      `Palette.swift`, and the four test files. Seven of the fourteen files are generated and
      must **not** be hand-edited.
      **The compiler named a file this list did not, and two roles nothing was checking.**
      `ink` had a *second* consumer — Android's `NaturalTheme.kt` uses it as Natural's
      Material `secondary` in both variants — so retiring the token forced a decision the
      artifacts do not cover, and `design.md`'s "`brand.ink` is untouched" contradicts its
      own token table. Neither replacement fits: the brand's pink sits 39° from clay, the
      same collision that moved the accent off `ink`, and read across, the other clay
      measures 2.80:1 and 2.99:1 on Natural's own canvases. Each variant's `secondary` is
      now the accent it already gates, with the reasoning and the reversal written at the
      call site. **And `onPrimary` was untested and is now wrong-turned-right**: a
      near-black label measured 6.91:1 on the 70 %-lightness amber and measures **4.06:1**
      on the 58 % violet, under WCAG's 4.5 floor for the normal-size text a button label
      is. Pure white is the only value in the set that clears it, at 4.77, so all three
      brand schemes take it and `ACCENT_PAIRS` gained a row that gates the pair — the token
      table gates the accent against the canvas and never says what may be drawn *on* it.
      Android had **no** test asserting the brand scheme's wiring at all; `BrandSchemeTest`
      is the mirror of iOS's `PaletteTests`, so both platforms' own gates now catch it.
- [x] 1.5 `docs/design.md` — the brand section, including the three `ember` mentions and the
      "reading-lamp amber" direction line. The direction itself does not change: chrome still
      recedes.
- [x] 1.6 Assert the arc's middle stops are not used as chrome. A source-level guard that
      `arcMid`, `arcLate`, `arcEnd` and `iconPlate` appear only in the mark generator, the icon
      assets and brand surfaces — never in a chrome accent position. `accent` and `secondary`
      *are* chrome and are exempt. Mutation-check it.
      **Mirrored, four rules a side**: `ArcStopsAreNotChromeTests` walks the iOS tree and
      `ArcStopsAreNotChromeTest` the Android one, each in its own platform's gate, because
      `pnpm test:ios` would not fail for a Kotlin violation. Shaped on
      `GlassIsUntintedTests`, and on `AdaptiveNavigationTest` for the Android half — the
      Android root is *handed over* by `build.gradle.kts` rather than discovered, since a
      walk up from the working directory escapes a worktree, and every file the guard reads
      is declared a task input or the guard sits UP-TO-DATE while another module gains a
      violation. Verified: all 154 `feature/**` sources are fingerprinted by content in the
      `arcStopsGuardSources` property.
      **Four mutations, and the coverage check failed two of them before it worked.** A
      token used in app code and a token in an accent position inside an allow-listed file
      were both caught naming file, line and token. Renaming `arcMid` in `color.json` breaks
      both guards' **compile** rather than letting them search for a dead name — the tokens
      are referenced beside their names for exactly that. But the coverage rule was useless
      twice over: iOS's floor of "more than twenty files total" survived pointing its
      largest root (331 files) at a missing path, and Android's "at least nine trees"
      survived dropping the whole `feature` family (154 files, and the family where a chrome
      accent lives) because `app` plus eight `core` modules is exactly nine. Both floors are
      now **per root and per group, never summed**, and each catches its mutation by name.
- [x] 1.7 Apply the accent everywhere the review named it missing: tab bars, chips, sliders and
      progress ticks, on **both** platforms. The compiler finds the token rename; it does not
      find a surface that was never accented, so this is a pass over those four control kinds
      rather than a rename follow-up.
      **One part of this was not a missing surface but a live contradiction, and it is fixed.**
      `AccentColor.colorset` is `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`
      (`apps/ios/project.yml:176`) — the tint every unstyled control on iOS draws itself in.
      It is generated by `scripts/brand-mark.swift`, whose own `Palette` held
      `accent = #FF6B9D` and `accentStrong = #DA497D`: after 1.1 those two hexes are
      `brand.secondary` and `brand.secondaryStrong`, so the generator's names meant the
      **opposite** of the token names and the app shipped the pink as its platform tint while
      `Palette.accent` was the violet. That is the "brand/tint mismatch" the design review
      opened with, and it survived the rename because no compiler reads an asset catalogue.
      Now one universal entry, `#8A4DF0`, no light/dark split — the split existed because the
      old amber needed a darker twin on paper, and the violet clears both canvases with one
      value, which is the entire argument for choosing it. The pink pair is gone from the
      generator rather than left unused. **The icons are byte-identical**: the mark's gradient
      comes from the SVG, so `pnpm brand:check` still passed and only the colorset
      moved. (It said "14 assets" here and the generator's count was never 14 — see the note
      at §2, and design.md, both corrected to 24 on 2026-09-04.) design.md §2's claim that "`AccentColor` holds the same hex the token does" is true
      again; it had quietly stopped being.

      **Both halves landed on 2026-09-02, from two agents that could not see each other's
      work.** Each note below says the other platform was outstanding, which was true when it
      was written; they are kept as written rather than reconciled into one voice, because the
      two platforms reached the same requirement by genuinely different routes and flattening
      that would lose the reason. iOS's is first, Android's second.

      **Three of the four were already accented on iOS, by one line.** `ThemeResolver` applies
      `.tint(theme.accent)` once at the root of every window and presentation, and every
      unstyled control on this platform draws itself in the environment's tint. So the tab
      bar's selected item, the reader's page slider, the adjustment sliders and every
      determinate `ProgressView` took the accent before this task started. That line is now
      pinned by `AccentReachesTheControlsTests`, because nothing in the build would have
      noticed it going: the app keeps compiling and all of those controls quietly return to
      system blue.

      **This paragraph cited two screenshots that have never existed, and a verification pass
      caught it on 2026-09-04.** It named
      `docs/designs/screenshots/named-failures-2026-09-01/ios-library-before*.png` and
      `ios-search-before.png` as "the pictures prove it". That directory holds a README and ten
      PNGs, every one of them named `*skipped*`; `git log --all --diff-filter=A` finds neither
      filename anywhere in the repository's history. **The claim cited itself** — a repo-wide
      grep for either string returns only the lines of this task. The tick stood on nothing.

      What is provable, from files that do exist, and it is two claims rather than one:

      - **The mechanism**, proved by
        `named-failures-2026-09-01/ios-skipped-toast-before.png`: the tab bar's selected
        *Library* item and all six toolbar glyphs are **ember**, not system blue. One line
        reaching every unstyled control is exactly what that frame shows. It cannot support
        the word *violet*, because it was shot before the palette moved — which is the honest
        version of what this paragraph was reaching for. The controls were already accented;
        the palette move is what made the accent violet.
      - **The result**, proved by `ios-sweep-2026-09-02/ios-search-at-rest.png`: the tab bar's
        selected *Search* item is violet, in the shipped build. The same frame carries the
        evidence for the deliberate omission below, which is why it replaces the second
        citation rather than a third being invented.

      There is no picture of a violet progress fill and no *before* of the cover rail, and this
      task is not going to manufacture one: a "before" cannot be re-captured once the palette
      has moved. The rail is covered by `AccentReachesTheControlsTests` instead, which is the
      exception AGENTS.md §6 asks to be named rather than left implied — the same treatment the
      sliders already carry two paragraphs down.

      **The fourth was genuinely unaccented, and it is the one a compiler could never find.**
      A cover's progress bar drew its rail as `.black.opacity(0.35)` — a scrim, not a colour.
      `design.md` gives `accentMuted` exactly this job, "accent at rest: progress rails,
      unselected indicators", and **nothing in the app was doing it**: the token's only
      consumer was a Settings row highlight. So the rail varied with the artwork under it,
      reading as mid-grey on a pale cover and disappearing on a dark one — which is precisely
      where a reader needs to see how much of the bar is *not* filled. It is
      `theme.palette.accentMuted` now, the same colour twice at rest and in use, and it
      follows Natural, whose palette maps that role to clay.

      **What was deliberately left, and why.** iOS's segmented control — `SearchAtRest`'s scope
      statement and the field's own `.searchScopes` bar, which is what plays the part Android's
      filter chips play — stays neutral. Three reasons, in order: it is the platform's own
      control and neutral by design, which is what `native-experience` asks the app to follow;
      `connected-button-groups` decided in its own `design.md` that "iOS's segmented control is
      current and idiomatic on that platform" and is not being replaced; and the only mechanism
      that would colour its selected segment is `UISegmentedControl.appearance()`, a global
      UIKit proxy that cannot follow the Natural theme's *two* accents and so would be right in
      three appearances and wrong in two.
      `docs/designs/screenshots/ios-sweep-2026-09-02/ios-search-at-rest.png` is the picture of
      it — *Everywhere* / *On this device* as a grey pill, four inches above a violet *Search*
      in the tab bar, in the same frame — filed as evidence for the decision rather than as a
      defect. It replaces a citation to `ios-search-before.png`, which never existed.
      Also left: the unfilled halves of `ThumbnailStrip` and `PickMark`, which sit on artwork
      and on a page, where a neutral is right and where `theme.accent` already carries the
      selected half; and the reader's own sliders, which take the tint and would defer to a
      cover-derived accent the moment `SwiftUI/View/coverAccent(_:)` reaches the reader — it
      reaches only `PublicationDetailView` today, which is a gap in §7 of `docs/design.md` and
      not this task's to close.
      **Not proved by a picture:** the sliders. No capture in `ScreenshotTests` reaches the
      comic reader's menu or the adjustments sheet, so the claim that they take the app's tint
      rests on the one guarded line rather than on a photograph. Said rather than skipped.
      **The Android half of the four control kinds is done. iOS's half is another agent's and
      is still outstanding**, which is why this stays `[~]`.
      **All four turned out to be one unset role, and the design document's account of the
      review's item was incomplete.** design.md answers "Android runs blue/purple" with "the
      purple was the wallpaper" — true of the screenshot the reviewer saw, and not the whole
      story. `darkColorScheme()` and `lightColorScheme()` fill **every role the caller omits**
      from Material's baseline palette, which is lavender; the brand schemes set eleven roles
      and omitted the rest. So with dynamic colour *off* — the path design.md correctly names
      as the one to fix — the app still drew Material's own `#4A4458` and `#E8DEF8`. Two
      independent causes of the same complaint, and only the second was ours.
      **Measured, not assumed.** Against `MaterialExpressiveTheme(colorScheme =
      brandDarkScheme())`, `secondaryContainer` was read by: a selected `FilterChip`'s
      container (**chips**), `NavigationBar`'s selected indicator (**tab bars**), `Slider`'s
      inactive track (**sliders**), and both progress indicators' tracks (**progress ticks**).
      `onSecondaryContainer` was the chip's selected label and the selected navigation icon.
      The four control kinds the review named are four faces of one role nobody had set. The
      accent already reached the *active* half of a slider and a progress bar through
      `primary`; what stayed Material's was everything at rest and everything selected.
      **Fixed in `Theme.kt`, three call sites, no new token.** `secondaryContainer =
      brand.accentMuted` and `onSecondaryContainer = light.surfaceRaised`, on
      `brandDarkScheme`, `brandOledDarkScheme` and `brandLightScheme`. `accentMuted`'s role in
      design.md's own token table is **"rails at rest"**, which is exactly a slider track and a
      progress track, and the same muted violet does a container's job behind a selected chip
      or a navigation indicator. Its only previous reader was the settings-search highlight.
      **One value on all three appearances, and the alternative is named rather than ignored.**
      A light theme conventionally wants a pale tint here with dark text; no such tint exists
      in the token set, and adding one means a new token with a gated pairing in
      `packages/design-tokens`, which is a palette decision rather than a wiring one. So a
      selected chip is *filled* rather than tinted on paper, and the pair measures **7.76:1** —
      one calculation that holds on every canvas instead of two to keep true. This is the same
      argument the accent itself won on.
      **Dynamic colour was not touched, weakened, or removed.** These three functions are the
      `useDynamicColor == false` branch; `dynamicDarkColorScheme` / `dynamicLightColorScheme`
      still return the reader's wallpaper scheme in full. On a Material You device nothing in
      this change is visible. With dynamic colour off, or on OLED Dark and Natural which
      decline it, the four control kinds are the brand's.
      **The `TextButton` question is answered at the scheme, once, and no `TextButton` was
      touched.** Another agent reported the failure notice's two labels drawing "Material's
      default `primary` (blue on this emulator's dynamic colour)" and matching every other
      `TextButton` in the app. The brand scheme's `primary` **already is** the accent, so every
      `TextButton` already follows it — photographed with no code change in
      `before-light-home-buttons.png`, where *Add a folder* is violet and *Open a comic* is a
      violet filled button. The blue was the wallpaper doing what `native-experience` requires.
      Hard-coding `palette.accent` at those sites would override the reader's Material You
      choice on a chrome control, which the chrome/content rule on `LocalStoryArcPalette`
      forbids, and would answer a scheme-level question one call site at a time.
      **Asserted, and the assertion fails on the defect.** `AccentReachesTheControlsTest` reads
      the real `FilterChipDefaults`, `NavigationBarItemDefaults`, `SliderDefaults` and
      `ProgressIndicatorDefaults` rather than restating them, so a material3 upgrade that moves
      one of these defaults fails the build instead of quietly un-accenting a control — the
      1.5.0-alpha pin is already a recorded risk. Removing the two lines from `brandDarkScheme`
      fails all five of its tests, each naming its own control kind. Each assertion also checks
      the value is **not** Material's baseline, which is what proves the role is set rather
      than coincidentally agreeing.
      **Photographed**, dynamic colour off, before and after, light and dark —
      `docs/designs/screenshots/android-accent-2026-09-01/`. Its README records the
      **third** shared-emulator trap, which cost one discarded capture: not a boot-snapshot
      rollback and not a broken `/sdcard` mount, but **another agent installing their build
      over mine between the install and the shutter**. The `after` captures are sandwiched
      between two checks of the installed APK's *contents*, not just its timestamp.
      **Two things are not proved by a picture, and are named rather than implied**: the slider
      and the progress track, which share the role but were not on screen (no download in
      progress; the `Comic reader > chrome` route reproducibly shoots after the reader's chrome
      auto-hides), and Natural, which has the identical hole and is left to whoever owns that
      theme because closing it means choosing a clay-family value with a gated pairing.
      **Also found and deliberately not fixed**: `primaryContainer`, `tertiary`,
      `tertiaryContainer`, `surfaceVariant`, `inversePrimary` and the `surfaceContainer` family
      are still Material's baseline in the brand schemes — `inversePrimary` is literally
      Material's `#6750A4`. None is read by the four control kinds §1.7 names, so none is in
      this pass; the list is here so the next reader has it rather than rediscovering it.

## 2. The mark, generated from one definition

- [x] 2.1 `scripts/brand-mark.swift`: the geometry once — a 2×3 grid of petals, each a square
      with one corner rounded to a quarter-circle per design.md's table, the lower-left one
      carrying the bookmark notch. 4:5 proportion, 3.5% gaps.
- [x] 2.2 Emit the SVG first, because it is the output a human can inspect. Commit it to
      `docs/designs/brand/storyarc-mark.svg` and eyeball it before generating anything else.
- [x] 2.3 Emit the iOS PNGs — 1024×1024 per face — and the Android `<vector>` foreground.
      Verify two runs produce byte-identical files; the probe already showed CoreGraphics
      does, and a generator that loses that property is a generator that churns the repo.
- [x] 2.4 `pnpm brand:build` and `pnpm brand:check`, the latter in `pnpm lint`. `--check`
      compares committed bytes and **never re-renders**, for the reason the audio fixtures
      give: the renderer is macOS-only and the output is committed, so nothing that reads it
      needs the tool.
- [x] 2.5 A test that the mark's own geometry is sane — six petals, no overlap, the notch
      inside its petal — so a bad edit fails before it is looked at.
      Runs in **both** modes, before anything is written or compared: a generator that can
      write a wrong mark is worse than one that cannot run, because the wrong mark gets
      committed and then gated as correct. Eight mutations, each caught and each naming its
      own defect.
      **The first version of the check was useless and the file says so.** It sampled filled
      area and demanded 0.5…0.95 coverage; measured across the whole radius sweep, coverage
      only moves from 0.86 to 0.68, so any band admitting a correct mark also admitted the
      chamfer that started this. And the gap check was tautological — it compared the measured
      gap to the declared one, so zeroing the declaration passed. Replaced by parameter bands
      plus the structural checks, and both gaps are now compared to each other as well.

> **Section 2 landed, and did more than it said.** The generator emits **twenty-four** assets,
> not three: per face an `.appiconset` PNG with its `Contents.json` *and* an `.imageset` PNG
> with its `Contents.json` — 5 × 4 = 20 — then `AccentColor.colorset`, the Android adaptive
> foreground *and* its monochrome twin, and a plateless PNG for the docs. This said fifteen
> and omitted the five `.imageset` tiles, which are the artifact §5.3 added because an
> `.appiconset` cannot be drawn by `UIImage(named:)` and a chooser needs something to put in
> its rows. Counted from the generator's own `written` list and checked against the files on
> disk, 2026-09-04.
> `AccentColor` is generated for the reason the rest is — it holds the same hex the token
> does, and a hex typed twice is a hex that will disagree once. That makes 4.2 and part of
> 3.2 already true; both are ticked where they are.

## 3. iOS: the icon set and the alternates

- [x] 3.1 Fill `AppIcon.appiconset`, which currently declares a 1024 slot and holds **no
      image at all**.
- [x] 3.2 One sibling `.appiconset` per alternate face, and
      `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in the project spec. Note this is
      generated by `xcodegen` — the change belongs in `project.yml`, not in the `.xcodeproj`.
      **The five sets already existed; the setting did not, which made four of them dead
      weight.** `AppIcon-{Paper,Bloom,Arc,Mono}.appiconset` were committed with §2 and no
      build setting named them, so they were not compiled into the app at all and
      `setAlternateIconName` would have failed at run time on every one — with an error no
      compiler could have warned about, because no compiler reads an asset catalogue.
      **Ink is deliberately absent from the list.** It is
      `ASSETCATALOG_COMPILER_APPICON_NAME`, and UIKit spells the primary icon `nil` rather
      than by name; listing it and passing `"AppIcon"` both fail. `AppIconChoice`'s
      `alternateIconName` is that rule, and `AppIconChoiceTests` asserts it.
- [x] 3.3 `AppIconChoice` in `StoryArcCore`: the faces, their names, the default, and the
      mapping to asset names. Mirrored on Android.
      **And it answered a question the artifacts left open: where the choice is stored.**
      Nowhere. `alternateIconName` on iOS and a component's enabled setting on Android both
      persist across launches by themselves, so neither `AppSettings` nor `AppSettings.kt`
      gained a field — a preference beside either would be a second answer to a question the
      platform already answers, and 5.1 asks the chooser to show what was *applied*, which is
      the platform's answer and never a stored intention. The type is still `Codable` /
      `@Serializable` so a diagnostic can name a face, and both suites assert the wire form.
      The two forms differ in case (`"ink"` / `"INK"`), which `AppearanceMode` already does
      for the same reason: nothing crosses between the platforms.
- [x] 3.4 `setAlternateIconName` with its completion handler. **The stored choice does not
      move until the platform confirms** — and `alternateIconName` is read on launch to
      reconcile, which is what makes 5.1 implementable.
      **There is no stored choice to move, which is the stronger form of the same rule.**
      `AppIconStore` holds `applied`, read from `UIApplication.alternateIconName`, and it moves
      only inside the completion handler. `AppIconStoreTests` drives a platform that has not
      answered yet and asserts the chooser has not moved — the failure that would otherwise be
      invisible, because a store that moved on the *call* looks right whenever the call
      succeeds. Nine tests, including that a refusal is asked once and never again.
- [x] 3.5 Do **not** suppress the system alert. design.md says why: suppression is
      undocumented and rides on a private delegate method.
      Nothing overrides anything: `AppIconPlatform.uiKit` calls `setAlternateIconName` and
      reads the error. The one thing the app *does* avoid is presenting the platform's alert
      for a change nobody made — choosing the face already in use asks the platform nothing,
      which `AppIconStoreTests` asserts by counting the calls.

## 4. Android: activity-alias, because there is no API

- [x] 4.1 One `<activity-alias>` per face in the manifest, each with its own `android:icon`
      and the launcher intent filter, all but the default `android:enabled="false"`.
      **Five aliases, one per face** — and this line read "four aliases, not five — the default
      is `MainActivity`, per 4.5" until 2026-09-04, which the paragraph four lines below has
      contradicted since the day a device disproved it. One ticked task holding both statements
      is worse than either, so the first is now the corrected one and the second keeps the
      story of how it changed. Each carries
      **only** the launcher filter: the VIEW and SEND filters stay on the activity, because
      they are how a file reaches the app rather than anything about an icon, and five copies
      of them would list StoryArc five times in "open with" the moment more than one component
      were enabled. `AppIconManifestTest` asserts that too.
      **The set became five aliases, not four, and a device is what forced it.** See 4.5 below:
      switching to any face but the default meant disabling `MainActivity`, and an alias whose
      *target* is disabled stops resolving — the app becomes unlaunchable while the launcher
      goes on drawing the icon it cached. So `MainActivityInk` exists, `MainActivity` carries no
      launcher filter and no `android:enabled`, and `AppIconManifestTest` asserts both.
      **The alias needed an adaptive icon each, which the generator does not write.** It emits
      one coloured foreground and one monochrome twin; the *plates* are resource literals,
      because an adaptive icon's background has to be a resource and a resource XML cannot
      reference a token. So `mipmap-anydpi-v26/ic_launcher_{paper,bloom,arc,mono}.xml` and
      three colours join generated art to a plate — no new art, and Mono differs only in
      pointing its foreground at the flat mark it already shares with `<monochrome>`.
      **That put the same hex in two languages, so it is gated.**
      `AppIconManifestTest` reads `colors.xml` and `scripts/brand-mark.swift` and fails when a
      plate drifts, because that script renders the *iOS* faces from its own `Palette` and a
      drift would ship a different Paper on each platform. Mutation-checked: Paper's plate off
      by one digit and Arc's alias missing `enabled="false"` were each caught by name.
- [x] 4.2 Replace `<monochrome>`'s pointer at the coloured foreground with the real
      single-colour art. `ic_launcher_monochrome.xml` is generated; a themed icon tints that
      layer, and a gradient tinted flat loses the mark's internal divisions.
      **This task's own note was stale and is corrected rather than deleted.** It said "the
      manifest still points `<monochrome>` at the coloured foreground". The manifest points
      `<monochrome>` at nothing — `mipmap-anydpi-v26/ic_launcher.xml` does, and it already
      named `@drawable/ic_launcher_monochrome`, with the reason written beside it. Nothing was
      outstanding here. The four new faces each point at the same flat art for the same reason,
      and the guard asserts it per face: a themed icon takes its colour from the wallpaper, so
      every face's themed form is the same mark.
- [x] 4.3 Swap via `setComponentEnabledSetting`, **enable before disable**, both
      `DONT_KILL_APP` — disabling the enabled alias first can close the task.
      `AppIconSwitcher` is a thin executor over `AppIconAliases`: the ordering and the
      invariant belong to the planner, and this is the part that touches the platform. Two
      seams — read and write — so `AppIconSwitcherTest` drives the whole sequence on the JVM.
      **It stops at the first failure, and the ordering is what makes that safe.** A refusal on
      the enable disables nothing, so the launcher still draws what it drew; a refusal later
      leaves two enabled, which the reader does not see and the next plan settles. Asserted at
      each of the five writes, each with its recovery.
      **Every way `PackageManager` refuses is caught rather than thrown.** A `SecurityException`
      or an `IllegalArgumentException` reaching the UI would be a crash for a reader who tapped
      an icon; the spec asks for a refusal instead, and the test asserts nothing escapes.
- [x] 4.4 A test asserting **exactly one** alias is enabled, over every transition including
      the same face twice and a failure mid-sequence. Zero enabled makes the app vanish from
      the launcher and is unrecoverable without a reinstall, so this is the invariant that
      matters most in this change.
      **And the invariant held for every write the app makes, while leaving the app unable to
      recover from the state it is about to describe.** A verification pass on 2026-09-04 asked
      what happens when *zero* are enabled by something outside the app —
      `COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED`, or a `pm disable` over ADB; stock Settings
      offers no per-alias toggle, so a reader cannot reach it unaided. `applied()` was
      `firstOrNull { isEnabled } ?: DEFAULT`, so the chooser marked Ink as in use, and
      `if (applied != face)` then refused a press on Ink as a press on the face already drawn.
      **The one press that would put the launcher entry back was the press the app refused.**
      Fixed by making `applied()` nullable: `null != face` is true for every face, so every row
      becomes pressable and none is marked. No second condition was needed. A refusal with
      nothing enabled cannot name a face still in use, so it carries its own string — built in
      each locale from the first sentence of that locale's existing refusal, so no new prose was
      translated — and the delta's refusal scenario now covers that state instead of requiring
      a name there is none of. `AppIconSwitcherTest`'s "a platform that will not report a
      component reads as the default" was **kept unchanged**: a platform that cannot report a
      state is one where nothing has changed it, so the default is honest there. The
      all-disabled *device* is two new tests beside it.

      **`AppIconManifestTest`'s foreground assertion could not fail, for any face.** It accepted
      a `<foreground>` of either `ic_launcher_foreground` or `ic_launcher_monochrome` — and
      every one of the five mipmaps carries
      `<monochrome android:drawable="@drawable/ic_launcher_monochrome" />`, which satisfies the
      second half of that disjunction whatever the `<foreground>` says, or whether one is
      written at all. Not merely permissive for four faces: **vacuous for five**. Narrowed so
      Mono may point its coloured layer at the flat art and the other four may not, and
      demonstrated by pointing Paper's at it and watching the test fail by name.
      **This is the third check in this repository that could not fail**, after the two named in
      `scripts/delta-drop-check.mjs`'s own docstring — which is why every gate here now ships
      with a self-test that mutates a passing tree.

      **Asserted against a modelled device rather than by reading the sequencing.**
      `AppIconAliasesTest` starts from the component states a *fresh install* has — every face
      at `DEFAULT`, not "Ink enabled and the rest disabled", which would quietly make the
      starting state a result — applies each plan one write at a time, and checks after
      **every single write** that something is still on the launcher. Twenty-five transitions,
      the same face twice, and a failure at each of the five writes of each plan, each
      followed by the recovery that makes the half-applied state tolerable.
      **Two properties carry it, and both are the planner's rather than the caller's.** The
      plan is **total** — it names every face's state, not only the two that change — which is
      what makes it land correctly from a state an earlier failure left behind, and it is
      **idempotent**, so a double tap cannot open a window with none enabled.
      **Five mutations, each caught and each naming its own defect.** Disable-before-enable
      (5 of 6 tests, the message printing the device at the write that emptied it), a plan that
      only writes what it thinks changed (4), an explicit `ENABLED` where the manifest's own
      `DEFAULT` belongs (**exactly 1** — the 4.5 test and nothing else), one face left enabled
      beside the target (5), and the target itself disabled (5).
- [x] 4.5 A fresh install and a reset land in the same state — **and the default is its own
      alias, not the manifest's activity.** The task's original wording asked for the opposite;
      the device disproved it and the artifacts now say so.
      **The requirement's reason is met. Its mechanism is wrong on this platform, and the
      device proved it.** `AppIconAliasState` has three values rather than two: a component
      whose wanted state is already the manifest's is written back to
      `COMPONENT_ENABLED_STATE_DEFAULT`, so choosing Ink returns every component to exactly what
      a fresh install holds — the same states, not equivalent ones. An explicit `ENABLED` would
      look identical on the launcher and leave an override a fresh install does not have; that
      is mutation 3 above, and the 4.5 test is the only one that catches it.
      **But making the default *be* `MainActivity` bricks the app.** Choosing any other face
      then disables `MainActivity`, and an `<activity-alias>` whose target is disabled does not
      merely lose its icon — it stops resolving. Measured on an emulator, same command either
      side: `am start -n .../MainActivityArc` with the target enabled starts a process, and with
      the target disabled reports "Starting" and leaves none; the MAIN/LAUNCHER intent answers
      **"unable to resolve"**. The launcher goes on drawing the icon it cached, so the only
      symptom is an icon that does nothing — a reader would reinstall.
      **So every face is an alias of its own, `MainActivity` is never written to, and it keeps
      no launcher filter.** `AppIconChoice.TARGET_ACTIVITY` names it and two tests refuse to let
      a face claim it: one in `AppIconChoiceTest`, one reading the manifest. Verified after the
      change on the same device — choose Arc, force-stop, and the app starts through the alias.
      **This contradicted `design.md`, and the artifact was what was wrong** (AGENTS.md §3b
      rule 5). The update ran on 2026-09-04, and a verification pass first named exactly which
      sentences the device disproved so it could be precise rather than broad:

      - `design.md`'s bullet "the default alias is the manifest's own activity, not a sixth
        alias" is **replaced**, keeping the half that was the reason it existed — a fresh
        install and a reset landing in the same state, which `stateFor`'s three-valued write
        is what delivers.
      - the launcher-filter bullet **gains the sixth component**: the activity the aliases
        target carries no filter, is never written to, and disabling it stops all five
        resolving at once.
      - `design.md`'s "one `<activity-alias>` per face" needed no correction — it became
        *literally* true when the set went to five, having meant four aliases for five faces
        before.
      - task 4.1's opening line said "four aliases, not five" four lines above its own
        correction; the first is now the corrected one.

      **No delta spec sentence needed changing, and that is what made the sync safe.** Neither
      delta names a mechanism: `settings-and-about`'s reset scenario says only "by the same
      route as any other choice", and `native-experience` does not mention aliases. The whole
      conflict lived in `design.md` and `tasks.md`, and neither of those syncs.
      It was `[~]` while the requirement as written was not what shipped; the `/opsx:update`
      of 2026-09-04 made the artifacts say what shipped, and it is `[x]` above.

## 5. What a reader sees

- [x] 5.1 Both: the chooser shows what was **applied**, not what was stored, and reconciles
      on launch against the platform's own answer.
      **There is nothing stored to disagree with it**, which is the strongest form this can
      take: iOS reads `UIApplication.alternateIconName` on every appearance and Android asks
      `getComponentEnabledSetting` per face. Both are re-read *after* a refusal too, which is
      what lets the message name the face still in use without the screen remembering anything.
      `AppIconStoreTests` drives an icon changed outside the chooser and a platform that has
      not answered yet; `AppIconSwitcherTest` drives a component changed under the app's feet.
- [x] 5.2 Both: the chooser sits beside Appearance and is reachable by the settings search.
      **Inside Appearance rather than beside it as a group**, which is the reading the spec's
      own sentence asks for: "it sits beside Appearance, because both answer *what does the app
      look like*". A group of its own would be beside Appearance in a list; a section inside it
      is beside the appearance rows themselves, and it costs no third navigation level on
      Android. `SettingsAnchor.appIcon` / `APP_ICON` makes search point at it and the existing
      highlight machinery light it up — mirrored term for term, six terms a side, and both
      platforms' "every anchor is reachable by search" tests now cover it.
      **"paper" is deliberately still Natural's**, although Paper is also a face: a reader who
      types it means the reading theme far more often than the tile.
- [x] 5.3 Both: each option is drawn as the icon it actually is, at home-screen size, current
      one marked, default marked as default.
      **Android draws the component's own launcher icon rather than rebuilding it.** The plates
      and the mark live in `:app`'s resources, which a feature module cannot reference at all,
      and an `<adaptive-icon>` is not something `painterResource` can draw even where it can see
      one. So the tile is `ActivityInfo.loadIcon` with `MATCH_DISABLED_COMPONENTS` — four of the
      five components are disabled at any moment — rasterised at 56dp. That means a face whose
      manifest entry is wrong looks wrong *here*, rather than looking right here and wrong on the
      home screen. iOS draws at 60pt with iOS's own squircle corner and the same hairline.
      **The hairline is there because the first capture found the defect it fixes**: Paper's
      plate is `#F8F6F4` and the settings surface is a warm off-white too, so its tile had no
      boundary at all and read as a plateless mark beside four plated ones — the one face a
      reader could not see.
      **iOS's tiles were blank until the generator emitted them, and the captures are what found
      that.** An `.appiconset` compiles to an *Icon Image* in `Assets.car`, and an icon asset is
      not fetchable by name — `Image(_:)` and `UIImage(named:)` both answer nothing, which draws
      an empty tile and is an error nowhere, so no test could have failed on it.
      `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS` emits no loose file, and listing the
      generator's own PNG a second time as a resource makes XcodeGen write a flattened path that
      does not build. `xcrun assetutil --info` on the built catalogue settled it.
      **Fixed in `scripts/brand-mark.swift`**: each face is now emitted **twice from one render at
      one inset** — the `.appiconset` the platform installs, and an `.imageset` named
      `AppIconTile-<Face>`, which is the name `AppIconChoice.tileResourceName` declares and
      `AppIconChoiceTests` asserts, so the two sides cannot drift. One render rather than two is
      what keeps the tile a reader picks from disagreeing with the icon they get. 180 px at `3x`,
      because that is a 60 pt home-screen icon.
      **Verified in the built catalogue rather than by eye**, since a blank tile is invisible to
      every gate: `xcrun assetutil --info` on `main`'s own `Assets.car` reports all five as
      `AssetType: Image` at 180 px, where the `.appiconset`s remain `Icon Image`. That inspection
      is worth doing carefully — the first attempt read the newest `Assets.car` by modification
      time and got **another worktree's build**, which reported zero tiles and would have been
      filed as a failure of this fix.
- [x] 5.4 Android: the reader is told the change appears the next time the launcher draws its
      list. iOS changes in place. **Do not paper over the difference** — the spec states it
      because the platform does.
      Two different sentences, in four languages each. Android's names the launcher's own
      schedule; iOS's names the system confirmation it is about to see, which is the other thing
      that platform does and this one does not.
- [x] 5.5 Both: a refusal says the icon could not be changed and names the one still in use,
      and does not retry silently.
      The refusal **replaces** the section's note rather than joining it — a reader who has just
      been told the change failed does not need the general note underneath — and it names the
      face still in use, because "it could not be changed" alone leaves them guessing what they
      are now looking at. Nothing retries: `AppIconStoreTests` counts the calls across two
      reconciles, and every way `PackageManager` refuses is caught on the Android side rather
      than reaching the reader as a crash. **`applied()` catches a failed *read* too**, and that
      one is reachable in ordinary use: it runs while the screen is being composed, where a
      throw is a blank screen rather than a message.
- [x] 5.6 Both: largest accessibility text size — names readable in full, tiles still
      distinguishable, list scrolls.
      The tile is a fixed 60pt / 56dp and the name takes the remaining width and wraps, so the
      row grows taller instead of truncating. A tile that grew with the text would push the name
      it exists beside off the row, and the requirement is about the *names*.
      **Photographed on both platforms, both appearances** (6.2). Android's largest-text shots
      show all three claims holding, and so do iOS's — this line said iOS showed "the layout
      holding with the tile artwork still missing", which was true of the frames it was written
      against and not of the re-take that replaced them the same night. Corrected 2026-09-04
      with 6.2.
- [x] 5.7 Both: each option announced by name and by whether it is in use; the tile itself
      decorative, because the name is what identifies it.
      iOS combines the row's children and adds `.isSelected`, so "in use" is a trait rather than
      a second string to translate; Android's existing `selectableRow` already merges and
      announces a `RadioButton` role. The tile is `accessibilityHidden` / `contentDescription =
      null` on each side — a described tile would make every row read "image, Paper" and say
      nothing a blind reader can act on. Two cases added to `SettingsSemanticsTest`, which is
      the only place the question can be asked: a screenshot cannot show what a node merges.

## 6. Proof and close-out

- [x] 6.1 Every face rendered and photographed **where the system itself draws it** — iOS's
      home screen, Android's All Apps list. The icon is the deliverable, so a screenshot of the
      chooser is not sufficient on its own.
      This asked for "a device home screen, both platforms", and the Android five are not home
      screens: they are the All Apps pane with "storyarc" typed, two search suggestions and the
      keyboard filling the lower half, so the icon occupies about a tenth of the frame. The
      face is correctly drawn and circle-masked in every one — what the task claims is proved,
      by a surface the headline named wrongly. The sentence four lines down had it right all
      along ("the launcher's own All Apps list filtered to StoryArc"), and so does the
      directory's README; only the headline overstated it. Reworded rather than re-captured,
      because a launcher's All Apps list is a place the system draws the icon from the same
      component state a home screen does.
      Ten captures in `docs/designs/screenshots/app-icon-chooser-2026-09-01/`, five a side, each
      driven through the app's **own** chooser rather than set behind its back.
      **iOS waits for the mark, not for a duration.** The chooser only marks a row once
      `setAlternateIconName` has confirmed, so a mark means the platform agreed and a timeout
      means it did not — which is what stops the home-screen shot catching the previous icon
      mid-crossfade. The walk also answers the system alert, and that it has to is itself proof
      the app does not suppress it (3.5).
      **Android asserts exactly one enabled component before every shot**, printed in the run
      log, and photographs the launcher's own All Apps list filtered to StoryArc.
      **One test per face, because six walks in one test is six chances to wedge.** The first
      version looped all five and reset, and was killed at fourteen minutes with `signal kill`
      and no message, throwing away the five screenshots it had already taken.
      **And a trap the harness warns about caught this run**: `--only AppIconCaptureTests` is
      prefixed with `ScreenshotTests/`, matched nothing, and xcodebuild exited **0**. The
      harness's own "attached nothing" line was the only clue.
- [x] 6.2 The chooser captured at default and largest text size, light and dark.
      Eight captures, four a side. At the largest size the names stay readable in full, the
      tiles stay the size a launcher draws them, and the list scrolls.
      **The iOS four used to show blank tiles, and the four on disk are the re-take.** This
      line said the blanks were "kept as the evidence of the gap" — written at 01:27, six
      minutes before the re-take landed at 01:29–01:33, and never revisited. That directory's
      own README says so ("the four iOS pictures here are the re-take"). All five rows draw the
      mark on its plate — Ink near-black, Paper off-white with its hairline, Bloom lavender, Arc
      violet, Mono white on black — with Ink check-marked in violet and labelled *Default*.
      An unusual staleness, because the tick made the change look **worse** than it was; still
      stale evidence a reader would have acted on, and the only reason 5.6 read as half-failed.
- [x] 6.3 Android: a themed-icon capture, since 4.2 is the reason the monochrome layer exists.
      **Taken on 2026-09-04**, in `docs/designs/screenshots/android-themed-icon-2026-09-04/`:
      all five faces on one home screen, themed and in their own colours.
      **This was recorded as a gap that could not be closed, and it was one launcher restart
      away.** The earlier pass had already got both flags right — the secure setting
      `theme_customization_overlay_packages` was `{android.theme.customization.themed_icon:1}`
      and the launcher's own `themed_icons` key read `true` — and concluded from unchanged
      icons that the toggle had not taken. It had. The launcher caches its icons and re-reads
      neither flag until it restarts: `am force-stop com.google.android.apps.nexuslauncher`
      then `KEYCODE_HOME`, and the themed icons are there. Nothing else was needed, and no
      wallpaper had to be set — the stock wallpaper already supplies a tonal palette.
      `cmd uimode` is a dead end for this: it offers `night`, `car` and `time` and no
      themed-icon verb. **Worth generalising**: two passes read a flag back, saw no change on
      screen, and drew opposite conclusions about the same true value. The flag was never the
      question; whether anything had re-read it was.

      **What the frames settle, and it is 4.2's premise.** Every cut, notch and negative-space
      gap in the mark holds when the layer is tinted flat — which is what shipping real
      single-colour art for it is *for*, and what `AppIconManifestTest`'s exact-string match on
      all five `<monochrome>` elements could assert the wiring of but never the look of.

      **And one design question the frames raise rather than answer.** All five adaptive icons
      declare the same `@drawable/ic_launcher_monochrome`, so **themed mode collapses the five
      faces into one** — Arc and Paper draw identically once tinted. That is correct for a
      themed icon, whose whole point is to take the wallpaper's colour rather than its own, and
      it does mean a reader who picks a face and turns themed icons on stops seeing their
      choice. Recorded here, not fixed: five monochrome variants would differ only in shape,
      and the chooser does not say the choice is conditional. Whether it should is a question
      for `settings-and-about`, not for this task.
- [x] 6.4 Update `docs/design.md`, `docs/openspec/STATUS.md`, and
      `packages/design-tokens/README.md` if it names the accent.
      **§1's share is done, and the list was two files short.** `docs/design.md` and
      `packages/design-tokens/README.md` landed with 1.5 — including two numbers that were
      *already* stale before this change: the README and design.md both claimed 37 gate pairs
      against 56 actual (58 now), and design.md still described `textTertiary` at a 3:1 floor,
      which it left when the gate moved every text role to 4.5. `STATUS.md` has a
      `brand-identity-and-app-icons` section, a corrected "last updated", and a note that its
      `library-browsing` row describes a shape the app has left.
      **Two files this task did not name, and one judgment.** The **root `README.md`** said
      "the accent is **ember** — the colour of a reading lamp" in its Design section, which is
      the most-read description of this palette anywhere in the repository; it also carried the
      stale 37. And **`CHANGELOG.md`** had no `### Changed` section at all, so a palette move
      and two contrast defects had nowhere to be recorded — it has one now, plus the two fixes
      and a `### Tooling` section.
      **The in-app what's-new log is deliberately *not* touched, and that is the answer rather
      than an omission.** `WhatsNew.swift`/`WhatsNew.kt` hold four notes for `0.1.0`, and their
      own comment says four is the shape "Apple's own What's New uses, because a reader who
      opens a reading app is there to read". `0.1.0` has not shipped, so nobody has seen the old
      accent; a fifth line telling a first-ever reader that a colour they have never seen has
      changed is exactly the clutter that decision was made against. Recorded here so the next
      session does not "fix" it.
      **Closed on 2026-09-04, and the sentence that used to end this task was wrong twice
      over.** It said "still outstanding: the §3–§5 sections, which have not been built, and
      whatever 1.7 changes on the four control kinds" — §3, §4 and §5 were built, and §1.7 was
      ticked. What was actually outstanding was the *documentation* of them, and it is written
      now:

      - **`STATUS.md`'s own section was the most wrong document in the repository**, and this
        task is what claimed credit for adding it. It said the icons had not shipped, that the
        accent reached no control on either platform, and that none of §3–§5 was built, at 7 of
        36 tasks. `CLAUDE.md` tells every agent to read that file *before* claiming a
        capability is missing, so the likely cost of leaving it was somebody building the
        chooser a second time. Rewritten, with the two device findings that changed the design
        and the one gap that remains.
      - **The asset count was fifteen in three places and twenty-four on disk.** Corrected in
        `design.md`, in §1.7 and in the §2 note, with the reason a face needs its art twice —
        an `.appiconset` cannot be drawn by `UIImage(named:)`, so a chooser has nothing to put
        in its rows.
      - **`pnpm brand:build` and `pnpm brand:check` were documented nowhere durable** — one
        incidental mention in a status document. On archive this change's `design.md` moves and
        the generator would have lost its only real description. Now in the root `README.md`
        and in `packages/design-tokens/README.md`, beside the `tokens:*` scripts it has to
        agree with.
      - **Natural's flattened `accentMuted` had no `CHANGELOG` entry.** It is a real palette
        consequence decided during implementation — retiring `ink` took a token Natural was
        also reading — and it was reasoned only at the call site. Recorded, with why inventing
        a `clayMuted` no gate covers was the worse trade.

      **Nothing is outstanding here now.** This said "still outstanding, and it is only §6.3",
      and §6.3 closed the same day the themed-icon frames landed.
- [x] 6.5 `pnpm lint`, `pnpm check`, `swiftlint --strict --no-cache`, `pnpm gradle`,
      `pnpm build:ios`, `pnpm build:ios:tests`, `pnpm build:android:tests` — all green on
      2026-09-04, on `main` with every one of this change's commits merged. 1857 iOS tests in
      235 suites; SwiftLint 0 violations in **658** files, the same count the cached run inside
      `pnpm check` reports. That agreement is the point of running the no-cache pass separately:
      SwiftLint silently reads no config when the working directory has drifted into
      `apps/ios/Packages/StoryArcKit`, and then reports 759 files and hundreds of phantom
      violations. A file count that does not match the last run is measuring a different thing.
- [x] 6.6 `pnpm spec:guard:strict` — 0 errors, 1 warning, and that warning is the pre-existing
      orphan list (six main specs named by no change, none of them this one's).
- [x] 6.7 `/opsx:verify brand-identity-and-app-icons`, then `/opsx:sync`.
      **The verify pass of 2026-09-04 said *not safe to sync* and it was right on four counts.**
      The delta's mechanics were clean — a strict superset of the main spec, a subset of
      `publication-detail`'s block, the order recorded — and its *content* was not:

      - **Two clauses this change's own screenshots disprove.** "Each option is shown as the
        icon it actually is" and "the app SHALL never claim an icon is in use that the launcher
        is not drawing" are both false on Android with themed icons on, because all five faces
        declare the same monochrome drawable and collapse to one. §6.3 had recorded that as "a
        design question for `settings-and-about`" — and this change **is** what publishes
        `settings-and-about`'s requirement, so deferring it meant shipping the contradiction.
        Both now carry a qualifier, and there is a scenario for the tinted case saying what is
        true and checkable rather than what would need a themed-mode detector no app is given.
      - **The requirement promised a case no scenario specified.** The rewrite that replaced
        "The platform stops honouring it" was justified only by its unimplementable third
        clause — the stored preference — and quietly took two implementable ones with it,
        while the requirement statement went on promising survival of "everything short of the
        platform withdrawing the ability". `supportsAlternateIcons` appeared nowhere in the
        tree. **Built rather than narrowed further**: `AppIconPlatform` gained an `isOffered`
        question, the chooser draws no rows and says why on a device that offers no choice, and
        two tests assert both that the store reports it and that `choose` asks such a platform
        nothing — because a store that reported it and still called `apply` would raise the
        platform's own alert for a change it was about to refuse.
      - **One clause read as cross-platform and is Android-only**: "where no icon is in use at
        all" is structurally unreachable on iOS, where the absence of an alternate icon *is*
        the default. Qualified.
      - **`STATUS.md` had gone stale again**, in the same pass that fixed it everywhere else:
        the heading still said "one gap left", the §6.3 paragraph still said the premise was
        "neither tested nor photographed" two commits after the photographs landed, and the
        count still read 31 of 36. Corrected.

      Also from that pass, none of it reaching a main spec: §4.5's note said it was marked
      `[~]` while ticked `[x]`; §6.4 closed saying §6.3 was still outstanding; two
      `StoryArcCore` files still said the chooser tiles did not exist, three days after they
      shipped and beside a capture showing all five drawn; and `AGENTS.md` named a SwiftLint
      file count that had gone stale under a sentence telling every agent to compare against
      it — 611 against a tree now at 660, so the rule would have condemned a correct run.

## A validator gap found while writing this

`openspec validate` **passed** a MODIFIED delta naming a requirement that does not exist in
the main spec — this change's first draft modified "Platform look", which `native-experience`
has never had. Only `openspec archive` would have caught it, at the point where the delta
could no longer be applied. Worth reporting upstream; recorded here so the next author knows
validate is not the check they think it is.
