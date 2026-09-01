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
- [~] 1.7 Apply the accent everywhere the review named it missing: tab bars, chips, sliders and
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
      comes from the SVG, so `pnpm brand:check` still passes on 14 assets and only the colorset
      moved. design.md §2's claim that "`AccentColor` holds the same hex the token does" is true
      again; it had quietly stopped being.
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

> **Section 2 landed, and did more than it said.** The generator emits fifteen assets, not
> three: the five iOS faces with their `Contents.json`, the Android adaptive foreground *and*
> its monochrome twin, `AccentColor.colorset`, the SVG and a plateless PNG for the docs.
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
      **Four aliases, not five** — the default is `MainActivity`, per 4.5. Each carries
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
- [~] 4.5 The default is the manifest's own activity rather than a sixth alias, so a fresh
      install and a reset land in the same state.
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
      **This contradicts `design.md`, and the artifact is what is wrong** (AGENTS.md §3b rule
      5). `/opsx:update` has not been run: a planning workflow never edits code and this session
      was implementing. The correction is recorded here and at all three call sites.
      Marked `[~]`, not `[x]`, because the requirement as written is not what shipped.

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
      show all three claims holding; iOS's show the layout holding with the tile artwork still
      missing, which is 5.3's gap rather than this one's.
- [x] 5.7 Both: each option announced by name and by whether it is in use; the tile itself
      decorative, because the name is what identifies it.
      iOS combines the row's children and adds `.isSelected`, so "in use" is a trait rather than
      a second string to translate; Android's existing `selectableRow` already merges and
      announces a `RadioButton` role. The tile is `accessibilityHidden` / `contentDescription =
      null` on each side — a described tile would make every row read "image, Paper" and say
      nothing a blind reader can act on. Two cases added to `SettingsSemanticsTest`, which is
      the only place the question can be asked: a screenshot cannot show what a node merges.

## 6. Proof and close-out

- [x] 6.1 Every face rendered and photographed on a device home screen, both platforms. The
      icon is the deliverable, so a screenshot of the chooser is not sufficient on its own.
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
      **The iOS four show blank tiles, and that is the code's state rather than a bad
      screenshot** — see 5.3. They are kept as the evidence of the gap.
- [~] 6.3 Android: a themed-icon capture, since 4.2 is the reason the monochrome layer exists.
      **A gap, not an exception.** Turning themed icons on could not be automated on this
      emulator in the time available: writing `themed_icons` into the Pixel launcher's own
      preferences read back `true` and changed nothing — every icon in the drawer stayed full
      colour — and `android.intent.action.SET_WALLPAPER` opens a disambiguation dialog rather
      than the Wallpaper & style screen the toggle lives on.
      What is asserted without a device: `AppIconManifestTest` checks that all five adaptive
      icons point `<monochrome>` at the flat art and never at the gradient foreground. That is
      4.2's whole reasoning, but it is not a photograph of it.
- [~] 6.4 Update `docs/design.md`, `docs/openspec/STATUS.md`, and
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
      **Still outstanding**: the §3–§5 sections, which have not been built, and whatever 1.7
      changes on the four control kinds.
- [ ] 6.5 `pnpm lint`, `pnpm check`, `swiftlint --strict --no-cache`, `pnpm gradle`,
      `pnpm build:ios`, `pnpm build:ios:tests`, `pnpm build:android:tests`.
- [ ] 6.6 `pnpm spec:guard:strict`.
- [ ] 6.7 `/opsx:verify brand-identity-and-app-icons`, then `/opsx:sync`.

## A validator gap found while writing this

`openspec validate` **passed** a MODIFIED delta naming a requirement that does not exist in
the main spec — this change's first draft modified "Platform look", which `native-experience`
has never had. Only `openspec archive` would have caught it, at the point where the delta
could no longer be applied. Worth reporting upstream; recorded here so the next author knows
validate is not the check they think it is.
