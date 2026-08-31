# The third batch of 2026-08-31, after

Same devices and same commands as [`before-2026-08-31c/`](../before-2026-08-31c/README.md),
which carries the setup and the caveats. This is what changed.

## What each pair proves

| Pair | Before | After |
| --- | --- | --- |
| `ios-home` | Search is a circular button on the trailing edge, **outside** the capsule and drawn unlike anything beside it. It leads nowhere: tapping it morphs the bar into a text field in place. | Search is the fourth tab **inside** the capsule, with a magnifier and the label *Search*, drawn exactly like Home, Library and Downloads. The detached button is gone, and the bar no longer changes shape under the reader's thumb. |
| `android-home-default-light` | Three destinations. Search is not in the navigation at all — it is a field on the library screen. | Four destinations, with *Search* last. |
| `android-home-default-dark` | Three, dark. | Four, dark. |
| `android-home-scale2-light` | Three at the largest accessibility text size. | Four at the same size, **every label still legible and unclipped**. This is the shot that matters most: the bar splits its width equally between destinations, so a fourth cut each share from 360 dp to 270 dp on this device. `NavigationLabelFontScale` holds the labels to their design size and it still holds at four. |
| `android-search-destination` | — | The destination itself, reached by tapping *Search*: the bar at the top, *Search* selected in the navigation, and the body empty. |
| `ios-search` | — | The iOS search page at rest, which **had no before shot because it had no before**: `Tab(role: .search)` morphed the bar into a field in place, so there was no screen to photograph. Recent searches with a clear action, *Pick up where you left off*, and *You have never opened these*. |

`ios-search.png` is also the proof of a rule rather than only of a screen. There is no *Next
in a series you have read* heading in it, and there should not be: the fixture library has no
series with a finished volume and an unread one after it. `navigation-shell` asks the screen
to say so in one sentence "rather than drawing empty headings", and a section with nothing in
it being **absent** rather than present-and-empty is what that looks like. A shot with three
headings and one run of covers would have been the failure.

Taken by `ScreenshotTests.testCaptureSearch`, which is new and could not have been written
before this change: `destination("Search", in: app)` finds a tab, and until now search was a
role rather than a tab.

## The empty body is deliberate, and is not finished work

The Android search page has nothing under its bar yet. That is section 2 of
`quiet-shell-and-search` — the at-rest offer of something to continue, something never
opened and a next volume — and the source says so where the space is left. Section 1 moved
search onto a page; it does not get to claim the page's content.

The screen is usable meanwhile: the bar expands to full screen on a tap and carries recent
searches and results exactly as it did on the shelf.

## The divergence, photographed

The two platforms disagree about the container, and the pictures are the evidence that it is
deliberate rather than an oversight. iOS floats a capsule inset from the edges, which is what
iOS 26 draws. Android's bar spans the window edge to edge with no capsule, no inset and no
rounding — `ShortNavigationBar` exposes no `shape` parameter at all, verified with `javap`
over `material3.aar` at 1.5.0-alpha26, so the capsule there is not discouraged but
inexpressible. [ADR-0001](../../../decisions/0001-independent-native-cores.md) working as
intended.

## The Android search bar, section 2

| Shot | What is in it |
| --- | --- |
| `android-search-expanded` | The expanded bar with nothing typed. The **back arrow** has replaced the magnifier — hand-written, because Material requires that "the back icon releases focus" and no API supplies it. The scope is **filter chips**, not a segmented control: Material retired that component in the Expressive update and its replacement is specified for a fixed set of two to five views, which our sources are not. And the bar **covers the navigation bar** with no code asked to hide it, which is the whole reason none was written. |
| `android-search-typed` | The same bar with a term in it. The **clear icon** has appeared — also hand-written, because `SearchBarDefaults` publishes no clear affordance of any kind — and it appears only now, because a permanent one is a control that does nothing most of the time. Underneath: *Still looking…* while the fan-out runs, and *Reading Room didn't answer / Try again* in grey rather than red, per `sources`. |

Both taken by hand with `adb input tap` and `adb exec-out screencap`, because
`pnpm capture:android`'s route table has no entry that opens the search bar. Adding one is
worth doing and is not done here.

## What these do not prove

The bar at `ShortNavigationBarMedium` — horizontal items, centred arrangement — is not in
any of these. Every shot is a compact phone window, where the correct answer is the vertical
item the bar already drew. `AdaptiveNavigationTest` asserts the medium branch instead, and
nothing has photographed it.
