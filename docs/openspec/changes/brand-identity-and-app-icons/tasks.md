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
      **Still outstanding**: the four control kinds themselves, on both platforms.

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
- [ ] 3.2 One sibling `.appiconset` per alternate face, and
      `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in the project spec. Note this is
      generated by `xcodegen` — the change belongs in `project.yml`, not in the `.xcodeproj`.
- [ ] 3.3 `AppIconChoice` in `StoryArcCore`: the faces, their names, the default, and the
      mapping to asset names. Mirrored on Android.
- [ ] 3.4 `setAlternateIconName` with its completion handler. **The stored choice does not
      move until the platform confirms** — and `alternateIconName` is read on launch to
      reconcile, which is what makes 5.1 implementable.
- [ ] 3.5 Do **not** suppress the system alert. design.md says why: suppression is
      undocumented and rides on a private delegate method.

## 4. Android: activity-alias, because there is no API

- [ ] 4.1 One `<activity-alias>` per face in the manifest, each with its own `android:icon`
      and the launcher intent filter, all but the default `android:enabled="false"`.
- [x] 4.2 Replace `<monochrome>`'s pointer at the coloured foreground with the real
      single-colour art. `ic_launcher_monochrome.xml` is generated; **the manifest still
      points `<monochrome>` at the coloured foreground** and that one-line change belongs
      with §4.1's alias work. A themed icon tints that layer, and a gradient tinted flat loses the
      mark's internal divisions.
- [ ] 4.3 Swap via `setComponentEnabledSetting`, **enable before disable**, both
      `DONT_KILL_APP` — disabling the enabled alias first can close the task.
- [ ] 4.4 A test asserting **exactly one** alias is enabled, over every transition including
      the same face twice and a failure mid-sequence. Zero enabled makes the app vanish from
      the launcher and is unrecoverable without a reinstall, so this is the invariant that
      matters most in this change.
- [ ] 4.5 The default is the manifest's own activity rather than a sixth alias, so a fresh
      install and a reset land in the same state.

## 5. What a reader sees

- [ ] 5.1 Both: the chooser shows what was **applied**, not what was stored, and reconciles
      on launch against the platform's own answer.
- [ ] 5.2 Both: the chooser sits beside Appearance and is reachable by the settings search.
- [ ] 5.3 Both: each option is drawn as the icon it actually is, at home-screen size, current
      one marked, default marked as default.
- [ ] 5.4 Android: the reader is told the change appears the next time the launcher draws its
      list. iOS changes in place. **Do not paper over the difference** — the spec states it
      because the platform does.
- [ ] 5.5 Both: a refusal says the icon could not be changed and names the one still in use,
      and does not retry silently.
- [ ] 5.6 Both: largest accessibility text size — names readable in full, tiles still
      distinguishable, list scrolls.
- [ ] 5.7 Both: each option announced by name and by whether it is in use; the tile itself
      decorative, because the name is what identifies it.

## 6. Proof and close-out

- [ ] 6.1 Every face rendered and photographed on a device home screen, both platforms. The
      icon is the deliverable, so a screenshot of the chooser is not sufficient on its own.
- [ ] 6.2 The chooser captured at default and largest text size, light and dark.
- [ ] 6.3 Android: a themed-icon capture, since 4.2 is the reason the monochrome layer exists.
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
