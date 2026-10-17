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
