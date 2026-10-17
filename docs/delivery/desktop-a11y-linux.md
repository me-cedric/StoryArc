# Linux screen reader walk

Task 4.15 of `desktop-clients`, lane L, branch `claude/lane-linux-wave4-1025c5`, 2026-10-17. The
scenarios are those of `desktop-experience`, Screen readers on each system, and of `audio-playback`,
Reaching the player without sight, with the focus hand-off of Full keyboard navigation for the EPUB
window. Results use the words of the wave 2 walk: pass (a named test asserts it), seen (the walk
showed it), **fail**, later, not proved.

**What the walk is.** Orca was not run: the container has no Orca and no GNOME session. What the
container can prove is the tree Orca reads. The debug build ran under cage (headless wlroots) in the
Ubuntu 24.04 container with a session bus and an accessibility bus (`at-spi-bus-launcher
--launch-immediately`, `GTK_A11Y=atspi`), and `apps/desktop-linux/scripts/a11y-tree.py` read every
StoryArc window through pyatspi after each step of `scripts/wave4-walk.sh`: the library, the EPUB
window, the PDF window with its search bar, and the library with the mini player. Each dump lists
every accessible object with its role, name, description and states, and counts the controls that
have neither a name nor a description. The dumps are committed beside the captures in
`docs/designs/screenshots/desktop/linux/wave4/a11y-*.txt`.

**What the first dump found and this branch fixed.** The three sidebar sections (Home, Library,
Downloads), the folder rows and the network rows were `list item: ''`: GTK gives a `GtkListBoxRow`
no accessible name of its own, so Orca would have read each row as nothing. `library_window::
named_row` now gives each row the name of its label. The shelf rows are built elsewhere and keep
the gap (below).

## Screen readers on each system

| Scenario | Result | Evidence |
| --- | --- | --- |
| Controls in the library | seen (partly) | Every header control has a name (`Search`, `Filter`, `Sort: Title`, the view toggle, `Main menu`); each cover cell carries the title, series, progress and source as its accessible label (`library::entry::accessible_description`, wave 2) and the index rail is a named group. Sidebar section and folder rows are named since this branch. Shelf rows (*New collection*, *New reading list*) are still nameless: see Remaining. |
| A page turn | pass, not proved aloud | The page surface is an `image` whose label is the position (*2 of 3*) and, for a PDF with text, the text pane shows the page's text as a selectable, readable `text` object; the EPUB window's position line is a label the walk saw change from *1 of 2* to *2 of 2*. Whether Orca announces the change as a live region is owed to a session. |
| A page with no text | pass | A PDF without a text layer offers no text pane and no search, and says in one sentence that the file is images of pages (`pdf_ui::install_no_text_note`); the page is announced by its position alone, as the comic pages are. |
| What could not be opened | pass | A refused file is the same grey sentence in the toast and in the cell's description (wave 2); a PDF without the engine is refused by name (`bytes_that_are_not_a_pdf_are_refused_by_name`). |
| Orca without an accessibility bus | seen | Every walk of waves 2 and 3 and the gate's tests ran with no accessibility bus and the app ran as usual; this walk ran with one and the app ran the same. |

## Reaching the player without sight

| Scenario | Result | Evidence |
| --- | --- | --- |
| Labels and values | seen | The mini player's tree: `Now playing` group; `15 s back`, `Play` or `Pause`, `30 s forward`, `Stop` as named push buttons; the slider named `Position` with the clock as its value text; the title and the subtitle as labels; the cover named `Cover`. |
| The compact bar under a screen reader | seen | The bar is one group with the publication's title and the state, and its controls are reachable by Tab after the library's content. The full player is not built on Linux. |
| At the largest text size | not proved | No settings portal in the container; the bar wraps in two rows so the clock and the slider keep their own line. |

## The EPUB window

| Scenario | Result | Evidence |
| --- | --- | --- |
| Leaving a book's text (Full keyboard navigation) | **not proved** | The web view appears as an empty `text` object: WebKitGTK's web process exposes the page through its own AT-SPI connection, and in the container the web process ran with its sandbox off and no a11y bus address of its own, so the book's markup was not in the tree. The header's `Read aloud` button and the position line are named. A real session owes the hand-off into the book and back. |

## What Orca on GNOME, on Hyprland and the no-service case still owe

- **GNOME with Orca:** every scenario above heard rather than read from the tree; the announcement
  of a page turn (whether the label change is spoken, or needs a live region); the EPUB content
  through WebKitGTK's own AT-SPI connection; the mini player's slider spoken with its value text;
  the shelf rows once named.
- **Hyprland with Orca:** Orca runs where an accessibility bus runs; `xdg-desktop-portal-hyprland`
  does not start one, so the walk documents the launcher the user installs (`at-spi2-core`) and
  whether `GTK_A11Y=atspi` is needed where no session starts the bus.
- **No accessibility service:** proved here as far as the app's own behaviour goes (it runs);
  what is owed is a run on a desktop with `GTK_A11Y=none`, which GNOME sets nowhere by default.
- **Remaining in the tree:** the shelf rows' names, and the EPUB web view's content. The PDF
  outline popover's rows carry their entry's title as their name.
