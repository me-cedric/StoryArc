# Linux wave 5 — the link, the accent and the click zones

Taken 2026-10-17 on `claude/lane-linux-wave56-f27559` by
`apps/desktop-linux/scripts/headless-proof.sh --walk docs/designs/screenshots/desktop/linux/wave5 wave5-walk.sh`:
the debug build under cage 0.1.5 (headless wlroots, 1280 by 720, pixman) in the Ubuntu 24.04
container (GTK 4.14.5, libadwaita 1.5.0), driven by `wtype` and a second instance of the app,
captured by `grim`, with a session bus and no sound device. The library is the corpus
`packages/test-fixtures/comics`.

## The `storyarc://` link (task 5.8)

A second instance of the app is started with the link on its command line, as the desktop entry's
`x-scheme-handler/storyarc` and `Exec=storyarc %U` would start it, and `GApplication` hands the
link to the running instance through the open signal.

| Frame | What it shows |
| --- | --- |
| `library.png` | The library over the corpus comics, as the walk starts. |
| `link-open.png` | `storyarc://publication/The%20Third%20Chapter`: the title `ComicInfo.xml` gives `manga-metadata.cbz`, open in a reader window at page 1 of 4. |
| `link-unknown.png` | `storyarc://publication/Nothing%20Like%20It`: the toast *Nothing named “Nothing Like It” in your library*, nothing opened. |
| `link-command.png` | `storyarc://settings/reset`: nothing changed; the log holds `link refused: storyarc://settings/reset`. A second link with a command after a name, `.../The%20Third%20Chapter/delete`, was refused the same way. |
| `link-source.png` | `storyarc://source/comics`: the library window on its Library page, the folder library the link named. |
| `storyarc.log` | The app's own output during the walk: the toast's text and the two refusals. |

The crate tests of `link.rs` hold the three scenarios (`cargo test -p storyarc-linux link::`). A file
manager or a browser handing the link over through the scheme handler is owed by a host: the
container has no `xdg-open` session.

## The chrome accent and the click zones (task 5.11)

The container has no settings portal of its own, so `scripts/fake-settings-portal.py` owns
`org.freedesktop.portal.Desktop` on the walk's session bus and answers
`org.freedesktop.appearance` as `xdg-desktop-portal` does: an `accent-color` of
`(0.21, 0.52, 0.89)` for the four accent frames, and no accent at all for the absent frame. The app
reads that key the way it does on a desktop (`portal.rs`), so these frames show the same code path
a GNOME session takes; light and dark are the app's own Appearance choice. The preferences dialog
is opened on a page through the `preferences-page` walk hook: its view switcher takes no key under
cage.

| Frame | What it shows |
| --- | --- |
| `accent-storyarc-light.png`, `accent-storyarc-dark.png` | Accent *StoryArc*: the brand purple on the selected sidebar row, the switcher and the banner behind the dialog. |
| `accent-system-light.png`, `accent-system-dark.png` | Accent *System*: the portal's blue in the same places. |
| `accent-absent.png` | The portal reports no accent, as a session on libadwaita 1.5 with no accent source: the Accent row is absent and the brand colour stays. The container's libadwaita is 1.5.0, the floor itself. |
| `zones-setting.png` | The Reading page: *Turn pages by clicking the edges* on, the default (design Open Question 2). |
| `reader-zones.png`, `reader-zones-next.png` | `natural-sort.cbz` open with the zones on, page 1 then page 2 after Right. A pointer click on the edge is not delivered under cage (`wtype` is keyboard only and `wlrctl` is not in Ubuntu 24.04), so the turn by click rests on `keys::tests` and is owed by a host. |

The tests of 2.35e pass in the same container: `cargo test -p storyarc-linux settings::`
(`the_system_accent_choice_exists_only_where_the_system_offers_an_accent`, `every_choice_has_a_label`,
`the_brand_accent_comes_from_the_generated_tokens` and the preference round trips).
