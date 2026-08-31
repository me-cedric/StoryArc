# The shelf caption, 2026-08-31

Booted iPhone 17 Pro simulator (`11DFC984`, iOS 26.5, 402 pt wide), StoryArc built from
`main`. Appearance and text size set with `xcrun simctl ui <udid> appearance` and
`content_size`; captured with `xcrun simctl io <udid> screenshot`.

The `before-2026-08-31/` set beside this one was taken on the build immediately before the
fixes, on the same device, with the same library.

## What each pair proves

| Pair | Before | After |
| --- | --- | --- |
| `ios-shelf-caption-default-light` | Every cell prints its title twice — `Ashfall #1` in primary over `Ashfall #1` in tertiary, six times in one screen. The guard compared the *bare* series against the title while returning the *composed* `"<series> #<number>"`. | One caption per cover. Where a series line would repeat the title it falls through to the author, exactly as the no-series path already did. |
| `ios-shelf-caption-ax5-light` / `-dark` | Three columns at the largest text size, so `Ashfall #1` hyphenates to `Ash-` / `fall #1` and its neighbours truncate to `Ash-fall…` over a series line of `Ashf…`. The cover is recognisable and the caption is not, which inverts what a caption is for. | Two columns. The caption has roughly double the width and reads in full. The documented 104 / 132 / 158 pt tiers are untouched at every ordinary text size — a host test on each platform pins them. |
| `ios-shelf-caption-default-light` (bottom strip) | "1 couldn't be opened" in `textTertiary` over Liquid Glass — barely present against bright artwork. | `textSecondary`, legible at the default size. |

## One thing these captures also show, which is not fixed here

Look at the bottom strip of **`ios-shelf-caption-ax5-light`**. At the largest text size the
covers are big enough that the strip always sits over one, and the scan summary — a fixed
palette colour — is drawn over glass that has taken on a dark cover behind it. In light
mode it is very nearly invisible. In dark mode at the same size it reads, which is the tell.

The cause is not the token. `storyArcGlass` is untinted on purpose, because
[`design.md`](../../design.md) wants chrome to pick up the cover beneath it, so the
surface's luminance is whatever the artwork is — while a `Color` from the palette cannot
follow. The tab bar's own labels in the same strip stay legible in both appearances because
the platform draws them with vibrancy against the material.

The honest finding underneath it, recorded by the agent that made the token change: **no
text token is contrast-gated against glass at all.** `pnpm tokens:check` measures the three
text roles against `surfaceCanvas`, `surfaceRaised` and `surfaceSunken`. Untinted Liquid
Glass is none of those, and neither is `surfaceOverlay`, its own declared opaque fallback.
`textSecondary` was chosen because it has the most measured headroom of the three
(6.36–8.72:1 against 4.94–5.87:1), not because anything certifies it on this surface.

---

# The same change on Android, 2026-08-31

`storyarc-j6` emulator, 1080 × 2400 at ~400 dp, StoryArc debug built from `main`. Appearance
with `adb shell cmd uimode night yes|no`, text size with
`adb shell settings put system font_scale 2.0`, captured with `adb exec-out screencap -p`.

The before image is `before-2026-08-31/android-shelf-caption-default-light.png`, which is
the committed `after-2026-08-30/android-shelf-no-source-line-light.png` — the defect was
already visible in it and nobody had read it that way: `Harbour Lights #1` printed over
`Harbour Lights #1`. It now reads `Harbour Lights #1` over `Ada Lovelace`.

At `font_scale 2.0` the grid drops from three columns to two and every caption reads in
full, matching iOS.

## Two things these captures show that are not fixed

Both are visible in **`android-shelf-caption-scale2-light`** and neither belongs to the
caption change:

1. **The bottom navigation bar clips its labels.** "Downloads" is cut off at the right edge
   at `font_scale 2.0`. This is the shell, not the shelf, and it fails the `design.md` rule
   that every screen survives the largest accessibility text size.
2. **The filter chip row runs off the edge with no affordance.** "Filter" is half out of the
   window. It may scroll horizontally; nothing on screen says so.

The source chip strip above the shelf (`Attic NAS`, `Reading Room`) also overflows, but that
strip is what task 2.4 of `one-library-three-destinations` asks to be deleted, so it is not
worth fixing where it stands.

## One thing that is not a defect, recorded so nobody chases it twice

Launching this build took **75 seconds** on the emulator started with
`-gpu swiftshader_indirect`, ending back at the launcher with *"Skipped 139 frames! The
application may be doing too much work on its main thread"* in logcat. That reads exactly
like a startup defect and is not one. The same APK on the same AVD started with `-gpu host`
reports `TotalTime: 1483` — one and a half seconds. Software GL cannot keep up with Compose
on this host. **Start the emulator with `-gpu host`**, or measure nothing.

---

# The publication page, reached from a cover, 2026-08-31

The page was built, translated and photographed a wave earlier and reachable from nothing
on either platform. These are the first captures of it as a reader would actually arrive.

| Capture | What it shows |
| --- | --- |
| `ios-detail-from-a-cover-dark` | Tapping `Ashfall #1` on the library shelf. Hero, the wash derived from the cover, the title, one primary action, the overflow beside it, and the series shelf. |
| `android-detail-from-a-cover-light` | The same journey on the emulator. The provenance line reads *From Attic NAS* — the one place in the app that names where a publication came from. |
| `android-library-no-source-strip-light` | The shelf with the per-source chip strip gone, which task 2.4 asked for and only iOS had done. |
| `ios-library-no-accessory-dark` | The library with **no** read-aloud session, proving the tab bar is back to its own height. |

## The before image, and what it caught

`before-2026-08-31/ios-detail-overflow-and-empty-accessory-dark` is the first build with the
page wired, and it carries two defects that only a screenshot could have found:

1. **An empty glass capsule above the tab bar.** The docked transport's slot draws its
   container whether or not the builder produced content, so every destination lost that
   much height while nothing was speaking. `tabViewBottomAccessory(isEnabled:)` is the
   remedy, and it costs the app's only availability branch — iOS 26.1 against a 26.0 floor.
2. **The overflow button half again as tall as *Read*.** A 44 × 44 frame on the label sat
   inside a `.large` control, so the disc was the glyph plus a hit target plus the control's
   own padding. Removing the frame alone made it too small; the row now fixes its own height
   and the circle fills it.

## One thing the Android capture shows that is not fixed

`android-detail-from-a-cover-light` is task 2.4's degenerate case — a publication with no
cover, no series, no year and no description — and **the composition does not hold up**.
The wash card fills most of the window with a format glyph in the middle of it and the
action pinned to the foot, so roughly three fifths of the page is empty. Task 2.4 asks in as
many words whether "the composition has to hold up with a title and a placeholder". On this
evidence it does not, and that is a layout decision rather than a bug to patch.

---

# What Apple's audit found, and what it looks like fixed

The iOS UI-test target had never built — `project.yml` gave it no `Info.plist` and did not ask
Xcode to generate one, so `xcodebuild test` failed before a single test ran and the
`XCTExpectFailure` it carried had never once been evaluated. Its first real run reported
**nineteen issues** across the three destinations.

| Capture | What it shows |
| --- | --- |
| `ios-downloads-ax5-{light,dark}` | Downloads at the largest text size. The audit reported **five `Text clipped` findings** here — captions handed an 18.0 pt frame for two lines of text. The shelf held a private copy of the cover-width rule that ignored the reader's text size and never measured its own width, so a lazy grid sized each cell against the column's *maximum* and drew it at the column's *real* width. It asks the shared rule now; Downloads went from seven audit issues to one. |
| `ios-coverless-well-ax5-light` | A publication with no cover art, at the largest text size. Its well used to shrink the title with `minimumScaleFactor(0.6)` — which `design.md` §3 forbids in as many words — and the audit called it *"Dynamic Type font sizes are partially unsupported"*. The well now carries the format alone and the title is stated in full underneath, at the size the reader asked for. |

## The contrast findings that remain, and why they stand

Nine of the nineteen were `Contrast failed` and every one was judged a false positive, with
the reasoning recorded in the test's own expectations rather than here:

- **Home's three** are cover cells, and `.accessibilityElement(children: .combine)` makes the
  artwork and the caption one element — so the check samples a frame that is seven-eighths
  photograph. Un-combining would clear the report and hand VoiceOver an unlabelled decorative
  image per cover: a green audit bought with a real reader's experience.
- **The rest sit in the last 134 pt of the window**, under the floating glass bar. Untinted
  glass takes its luminance from whichever cover is passing, so contrast under it is not a
  bounded quantity. The proof is positional rather than argued: the same text role and colour
  failed at y 813 and passed at y 395 and y 604 in the same run, and when the layout reflowed,
  the findings moved with the elements rather than staying with the palette.

The palette itself is not in question — `textPrimary` on `surfaceCanvas` measures 16.9:1 in
light and 16.8:1 in dark, and the worst pair anywhere in the set is 4.97:1.

---

# The Android navigation bar at the largest text size

`android-navbar-scale2-light` against `android-shelf-caption-scale2-light` in the same
directory, which is the before: "Downloads" was cut off at the right edge at
`font_scale 2.0`, failing `design.md` §3's rule that every screen survives the largest
accessibility text size.

The answer turned out to be Material's own. `NavigationBarItemView.setTextAppearanceWithoutFontScaling`
removes font scaling from a navigation label, and `labelFontScalingEnabled` defaults to
**off** — which is why every stock Material app draws small nav labels at a large font
scale. Compose's `ShortNavigationBarItem` has no equivalent, because the label is the
caller's composable, so the shell carries the rule instead. Material closes the other three
doors itself: a navigation label must not truncate, must not wrap, and must not be dropped.

It is scoped to the bar and the collapsed rail. The expanded rail has room and keeps the
reader's chosen size.

**Still visible in this capture and not fixed:** the filter chip row above the shelf runs
off the window with no affordance that it scrolls. It is recorded as its own item.

---

# The shelf's notice: a capsule, with a gap, that recedes

`before-2026-08-31/ios-notice-band-dark` → `ios-notice-capsule-dark` → `ios-notice-receded-dark`,
all on the booted iPhone 17 Pro in dark mode at the default text size.

The first is a full-bleed band pinned across the window, which was the only rectangle in an
app whose every other piece of chrome — the tab bar, the search field, the shelf's toolbar
group — is a floating capsule. It cut the covers either side of it in half.

The second is the same sentence as a capsule that hugs it, with a gap above the tab bar so
it reads as its own thing rather than a second row of one.

The third is the same screen nine seconds later. It has gone. This is news about a scan that
has finished, and `native-experience` asks chrome to recede — a sentence parked above the tab
bar for the rest of the session is furniture, not news.

**Except under VoiceOver**, where it stays. A sentence that fades is a sentence a reader who
has not yet swiped to it never hears, and the count is stated nowhere else in the app. A
sighted reader gets a glance and their artwork back; a VoiceOver reader keeps the fact.

---

# The Android tablet, seen on a device at last

This was one of the three follow-ups the previous session left open: the tablet layouts
were merged and gated, and only iOS had been driven. `adb shell wm size 1600x2560` and
`wm density 200` put the emulator over Material's expanded breakpoint; `wm size reset` and
`wm density reset` put it back.

| Capture | What it shows |
| --- | --- |
| `android-tablet-rail-home-light` | The expanded `WideNavigationRail`, labelled, carrying five destinations — the three the phone has plus Shelves and Settings, which is the point of the extra room. |
| `android-tablet-empty-pane-light` | The library as two panes with nothing chosen, and the sentence that was written for it this wave: *"Choose a cover to see what it is and where it came from."* iOS wrote that sentence a wave earlier and has no pane to put it in; Android had the pane and no sentence. |
| `android-tablet-two-panes-light` | A cover chosen. The shelf keeps its scroll and its filters; the page fills the second pane with its hero, its one action and its provenance line. |

## Two things these show and this wave does not fix

1. **The detail pane draws a back arrow.** With the list permanently beside it there is
   nothing to go back *to*, and Material's own `ListDetailPaneScaffold` hides that
   affordance when both panes are visible. Here the pane is hand-composed, so it does not.
2. **Home on a tablet is mostly empty.** One shelf of five covers across the top and
   nothing under it. That is open question §8.3 of the direction document — *what fills
   Home on day three* — showing itself at a width where there is much more day three to
   fill.

---

# The download facet, in the filter menu

`ios-filter-downloaded-facet-dark` — *Downloaded or not*, second in the library's filter
menu, on the booted iPhone 17 Pro. `library-browsing`'s *Filtering offline* scenario was
scored **missing on both platforms**, and its recorded blocker — that the library is
assembled from a scan which never consults the record of downloaded files — was already gone.

**It is not the availability scope said twice, and the spec is what settles that.** The
scope in the toolbar asks *will this open on a plane*: a folder the reader picked answers
yes, as much as a download the app fetched. The facet asks the narrower question
`offline-downloads` owns — *did this app fetch it and is it keeping it* — which is a path
comparison against the download store's own directory, the same line the shelf already
draws for the mark on a cover. A file a folder walk found answers yes to the first and no
to the second, and the difference matters exactly when the card is pulled, the grant lapses
or the folder is unmounted.

So the facet's result is a strict subset of the scope's, which keeps *Filtering offline*'s
clause true of it while the two controls answer different questions.

---

# Both in-repo servers, connected from the app

`scripts/opds-server.mjs` and `scripts/kavita-server.mjs` serve the fixture corpus and had
never been reached from the app on a device — the source stack was proven by unit tests and
by `curl`, and not by a reader typing an address.

| Capture | What the server saw |
| --- | --- |
| `ios-opds-connected-dark` | *Connected to StoryArc Test Catalogue.* Two `200 GET /opds` in the server's log — the app fetched the feed and read its title out of it. |
| `ios-kavita-signed-in-dark` | *Signed in as ada · Kavita 0.8.3.* `POST /api/Plugin/authenticate?apiKey=…&pluginName=StoryArc` then `GET /api/Server/server-info`. Both the username and the version come from the mock, so this is the real handshake and the real version floor, not a hard-coded string. |
| `ios-search-remote-and-away-dark` | A search with both servers configured. The local match is listed under *Titles*; the unreachable share reads **"Attic NAS didn't answer — Try again"** in grey with a retry, which is non-negotiable #3 held on a device: an unreachable source is grey, never red, and the library stays browsable. The server's log shows `GET /opds/all?q=Fine%20Print` arriving. |

## What the third capture proved was missing — and what was done about it

The catalogue was queried, answered, and **its results were not on the screen.** Only the
local match was. That is `library-browsing`'s *Mixed local and server search* — server and
local results merged into one ranked list, each labelled — which `STATUS.md` scored as
missing on both platforms.

**It was built the same day, and the capture is what made the cause findable.** The merge
half was not missing: `LibrarySearch` already fanned one query out to every library and
already merged the answers. What was missing was the scenario's other two words — *ranked*,
and *each labelled* — and the symptom had a precise cause: the merge folded any remote row
whose title matched a row already on screen, **across libraries**. The feed returns exactly
one entry titled `Fine Print`, the device held a book of that title, so the catalogue's
entire answer was folded out of existence with nothing on screen to say a catalogue had
replied.

What shipped: a ranking that scores title strength first and place only as a tie-break —
because the reader asked for a book, not for a place — applied per answer as it lands and
never across answers, so a late server reply cannot reorder what the reader is already
reaching for. A row says where it came from when **more than one place could have
answered**, which is a different question from the shelf's "more than one source is
configured": one library answering both locally and remotely is still one place, because a
download carries its library's identity.

Four cross-platform divergences were found by measuring rather than by reading, and all
four are now pinned by mirrored tests: Swift's `String <` orders by unicode scalar and
Kotlin's `compareTo` by UTF-16 unit; `.whitespacesAndNewlines` strips non-breaking spaces
where `String.trim()` keeps them; `String.folding` case-folds `Straße` to `strasse` where
Kotlin's `lowercase` cannot; and one length key counted grapheme clusters against UTF-16
units. The same search term ranked differently on the two platforms in each case.

**This capture is still the "before".** The "after" — two rows under *Titles*, one reading
*From Attic NAS* and one *From StoryArc Test Catalogue* — is owed and not yet taken.

## One environment note

Typing into the simulator on this machine goes through the host's French keyboard layout —
`http://127.0.0.1:4444/opds` arrives as `httpM==&éè:à:à:&M''''=opds`. Use
`xcrun simctl pbcopy <udid>` and then Cmd+A / Cmd+V driven at the Simulator process. A long
press does not raise the paste menu reliably on iOS 26.

---

# A fixed-layout book that could never be opened

Found by opening `Bright Panels` on the simulator — a publication the shelf labels EPUB.
It landed on **"This comic has no pages StoryArc can show."**
(`before-2026-08-31/ios-fixed-layout-refused-dark`.)

The routing was right. `ebook-reader` sends a fixed-layout EPUB to the image reader, and
that is where it went. **The fixture was not a fixed-layout book.** `scripts/corpus.mjs`
wrote the same wall of sentences whether `fixed` was set or not and only added
`rendition:layout` to the metadata — a pre-paginated *text* book, which is legal EPUB and
is nothing like what an image reader exists to draw. The refusal was therefore correct:
there really were no images in it.

The consequence is the part that matters. **The fixed-layout path had never once been
exercised against anything it could draw** — not in a test, not on a device, not in any of
the 130-odd captures in the directories beside this one.

| Capture | What changed |
| --- | --- |
| `ios-fixed-layout-cover-dark` | The shelf. `Bright Panels` had been a blank grey card, because a book with no images has no cover to take one from. It has a cover now. |
| `ios-fixed-layout-opens-dark` | The book, open, showing its first plate letterboxed on black. |

The refusal itself was also reworded. The image reader serves fixed-layout books and PDFs
as well as comics, and telling someone who opened a book about "this comic" is wrong in all
four languages. It says there are no pages *here* now, which is true whatever was opened.

---

# Natural, and the reader's system bars

## Natural

`android-appearance-natural-{off,on}-light`, on the emulator at the default text size.

Natural is a **theme**, not an appearance: it has its own light and dark and follows the
four radio rows above rather than replacing them. Turning it on turns the whole surface to
warm paper stock with a clay accent — and turns the *wallpaper* row off and disables it,
with its reason rewritten to say why: "Natural brings its own warm accents: a wallpaper tint
beside them would be two themes at once." Two dynamic-colour systems at once is not a
preference anyone holds.

**One defect these show and this wave does not fix:** in the third row, *Match the reading
theme to the app*, the description runs **under** its switch — "a paper-white page" ends
beneath the toggle's left edge. The two rows above it stop short of theirs. It is the row's
text having no width to yield with, and it is at the default text size, so it is worse at
larger ones.

## The reader's system bars

`android-reader-immersive-light` and `android-reader-chrome-back-light`. The system bars
leaving with the reader's chrome shipped earlier today and merged with **no capture at all**;
these are it, on a device.

The first is a page with nothing over it — no clock, no battery, no signal, no gesture pill.
The second is the same page after a centre tap: the reader's own controls return, and the
system bars stay away, which is the point — the chrome that comes back is the app's.

Android showed its own *"Viewing full screen — to exit, swipe down from the top"* sheet the
first time, which is the platform confirming the mode is really on rather than the app
drawing over the bars.

**Still owed:** the paper grain. Grain is confined to reading surfaces, and the comic reader
has none — its own slice named that as out of its file set. Judging it needs the EPUB reader
with Natural on, in both appearances, and again with Reduce Transparency on, where the
texture must vanish and the palette must stay.
