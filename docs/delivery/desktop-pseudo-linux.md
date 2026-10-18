# Linux pseudo-locale walk

Task 5.13 of `desktop-clients`, lane L, branch `claude/lane-linux-wave56-f27559`, 2026-10-17. The
`localization` scenario *Pseudo-locale testing* asks that under an expanded pseudo-locale no screen
clips, overlaps or hides a control. German is the longest of the four languages the app ships and
is not long enough to prove that on its own, so the walk runs German with every string padded by
half again: `STORYARC_PSEUDO_LOCALE=1` makes `strings::tr` wrap each string as `[text · · ·]`,
the width a translation is allowed to reach (`strings.rs`, `expand`; placeholders survive, so the
counts still fill). The largest size is a text scale of 2.0, set through
`org.gnome.desktop.interface text-scaling-factor` on the keyfile GSettings backend, which GTK reads
as `gtk-xft-dpi`; GNOME's Large Text is 1.25, so this is past what the system offers.

**What the walk is.** `apps/desktop-linux/scripts/headless-proof.sh --walk <dir> pseudo-walk.sh`:
the debug build under cage (headless wlroots, 1280 by 720) in the Ubuntu 24.04 container with GTK
4.14.5 and libadwaita 1.5.0, driven by `wtype` and the walk hooks (`preferences-page`, `about`,
`shortcuts`, `open-reader`), captured by `grim`, with the accessibility tree of each screen dumped by
`scripts/a11y-tree.py`. The frames that back the findings are under
`docs/designs/screenshots/desktop/linux/wave5/pseudo/`. Results use the words of the conformance
walks: pass, seen, **fail**, not proved.

## Screens

| Screen | Result | Evidence |
| --- | --- | --- |
| Home | **fail** | `home.png`: the library header bar does not shrink. Search, *Filtern* and *Sortieren: Titel* keep their natural width, so the window's minimum width passes 1280 and the view toggle and the window's Close button sit off the screen (the tree lists Close as showing; the frame does not). The status page text is cut on the right for the same reason. |
| Library grid | **fail** | `library.png`: the same header; the grid itself wraps its titles in two lines and nothing in it clips. |
| Downloads | **fail** | The same header; the page's own text wraps. |
| Settings, Your libraries | seen | Rows wrap in two lines, the buttons keep their labels. |
| Settings, Appearance | seen | Two rows, both whole. |
| Settings, Reading | seen | `settings-reading.png`: the switch row wraps in two lines, the choice rows keep their values. |
| Settings, Storage | seen | `settings-storage.png`: the description wraps in four lines; the page scrolls. |
| Settings, Privacy | seen | Scrolls. |
| Settings, the view switcher | seen | The five page titles are ellipsized to four letters (`[Ihre B…`): libadwaita's narrow switcher. Readable from the icons, as GNOME's own settings are at this size; not a clip. |
| Keyboard shortcuts | seen | `shortcuts.png`: rows wrap in up to three lines beside their keys; the dialog scrolls. |
| About | seen | `about.png`: libadwaita's own layout; scrolls. |
| Comic reader | seen | `reader.png`: the header and the page line fit; the search bar's entry and count fit on one line. |
| PDF reader | seen | `pdf-reader.png`: the text pane and outline toggles, *Read aloud* and the menu fit. |

## Findings

1. **The library header bar hides the Close button at a text scale of 2.0.** The two labelled
   menu buttons and the search entry have no narrow form, so at 2.0 the header is wider than
   1280 pixels and GTK gives the window that minimum width. Fix for the owner of task 2.35b: the
   Filter and Sort buttons drop their labels for their icons below a width, as the Mac toolbar
   does, or the search entry moves into a `GtkSearchBar` under a toggle. Not fixed here: a
   layout change of the library window is outside this walk.
2. **Strings with no catalogue key show English in every language.** 38 of the commands in
   `commands.rs` carry `None` for their key (*Open File…*, *Refresh Sources*, *Close Window*,
   *Quit StoryArc*, *Next Page*, *Read Aloud* and the rest of the shortcuts dialog and the menus),
   as do the choice labels of Page layout and Fit (`settings.rs`: *Automatic*, *Single page*,
   *Fit page*, *Fit width*, *Original size*) and the Open File dialog's title (`launch.rs`). `tr`
   is never asked, so they stay English and the pseudo-locale cannot pad them either; the
   catalogue already holds `desktop.command.openFile`, unused. The keys belong in
   `packages/desktop-strings` with four translations; listed for the parent, as `strings.rs` says.
3. **Nameless controls** on the accessibility bus, the count `a11y-tree.py` prints: 2 on Home,
   10 in the library grid, 8 on the Reading page, 6 on Your libraries, 4 on Appearance. The
   library window's list rows and the choice rows' buttons; `desktop-a11y-linux.md` already names
   them, and the pseudo-locale adds none.

Not proved: a real session's own text scale through the settings portal; Orca reading the padded
strings; the widest window the detail pane opens at. GTK's own strings (the About dialog's
*Details* and *Credits*, the file chooser) stay English in the container, which has no German
locale installed, and are not the app's.
