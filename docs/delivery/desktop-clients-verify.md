# Verifying `desktop-clients` — 2026-10-18

Task 6.9, the verification step, run before any archive. The change is checked for completeness
(its tasks), correctness (its delta spec, `specs/desktop-experience/spec.md`, against the platform
records under `docs/delivery/`) and coherence (its `design.md` against what was built). The
archive is not run: the result below says why.

**Verdict: not ready to archive.** The Mac, the shared core and the Linux crate are built through
wave 5 and green on this Mac and on CI; Windows compiles and its interop tests are green on CI.
What remains is of three kinds: work no machine here can prove (the host pass at the end of this
page, by the owner's decision of 2026-10-17), four owner decisions, and features the specs name
that are **not built** on the Mac. The last kind is real work for a session, not a host's.

## Completeness: the tasks

| State | Tasks |
| --- | --- |
| Ticked | 110 of 184 |
| Built, owed by a host | 1.7, 1.16, 2.25 to 2.35e, 2.37 to 2.47e, 3.3, 3.9, 3.17 to 3.19a, 3.21 to 3.23a, 4.4, 4.10, 4.13, 4.14, 4.16, 4.17, 4.19, 4.20, 4.22, 5.5, 5.8, 5.9, 5.11, 5.13, 6.1, 6.2, 6.7 |
| Not built, needs a host to start | 1.17, 1.19, 1.20, 5.2, 5.3 |
| Waiting on the owner | 1.25, 5.4 (Finder after signing), 5.7, 6.5, 6.8 |
| Deferred to the iOS owner | 1.30, 5.12 |
| Open on this Mac | 5.10 (the grid resizes at 19 fps), 6.9 (this page) |

Every open task carries a dated note under it saying which of these it is (commit
`docs(desktop): reconcile the desktop-clients tasks with what main holds`).

## Correctness: the requirements

43 requirements, 168 scenarios. A requirement counts as recorded on a desktop when that desktop's
conformance, accessibility, budget or spike record names it or one of its scenarios.

| Recorded on | Requirements |
| --- | --- |
| macOS, Linux and Windows | 30 |
| macOS and Linux only | 8 (supported systems, accent and appearance, spreads, keeping the display awake, text size and motion, display servers, About, cold start, visual proof) |
| macOS and Windows only | 1 (media keys and system media controls) |
| macOS only | 3 (each system's idiom, covers in file views, a book stays off the network) |
| none | 2 (opening a link or a command; Handoff and Spotlight) |

**Failures a host cannot explain.** The records list scenarios that do not hold on a desktop
today because the feature is not there:

- **The Mac, wave 4** (`desktop-conformance-macos-wave4.md`, 5 of 92 after 2026-10-18's work,
  42 before): typography, scroll mode, contents, bookmarks, highlights, footnotes, theme swatches,
  a way back after an internal link, a confirmed link out, the sleep timer, chapter marks, the
  headphones pause, the compact bar, the coverless artwork and the page's chapter list are built.
  What fails: the bundled typefaces, and four read-aloud scenarios (the spoken sentence in the
  page, returning at the sentence spoken, the voice in the full player, and the notice when
  another book stops the voice).
- **The Mac, wave 3** (`desktop-conformance-macos-wave3.md`, none of 190 after 2026-10-18's work,
  18 before): a source window now hosts the phones' browser for OPDS, Kavita and shares, sources
  rename and reorder, a search scoped to a Kavita server offers to ask it, and an *All Shelves*
  window lists server collections and lists.
- **Linux, wave 2** (`desktop-conformance-linux-wave2.md`, 3 of 484), named in that record.
- **Windows** has walked no screen: every Windows scenario is *wired, not proved* until a desktop.

## Coherence: the design

`design.md` carries an "As built" note for each lane of each wave, and they agree with the code
and the records. Where the build moved off the plan, the design says so:

- the vendored SMB client encrypts, so the encryption refusal task 3.10 expected does not exist;
- the Windows EPUB host serves `connect-src 'self'`, not `'none'`, because the renderer fetches
  chapters from the manifest's origin;
- Explorer thumbnails are out of the first release (Open Question 15);
- the Mac keeps copies of iOS shell code until the parent edits 1.30 and 5.12;
- a Debug build on the CI runner (Xcode 26.6) carries no Metal library, so the curl is absent there.

## Findings

**Critical** (block the archive)

1. 74 tasks are open; `/opsx:archive` must wait for the host pass and the owner's decisions.
2. The Mac lacks the ebook-reader and audio-playback features listed above, which the main specs
   require; the change claims those capabilities on every desktop.
3. *Opening a link or a command* is built and tested on all three desktops (task 5.8) but no
   conformance record walks it; the wave 5 records should.

**Warning**

1. No `desktop-conformance-linux-wave4.md` or `desktop-conformance-windows-wave4.md` exists (task
   4.22); Linux walked wave 4 headless without writing the record.
2. The Mac grid resizes at 19 fps at 5,027 publications (`desktop-budgets-macos.md`), and every
   launch rescans the whole folder, about eight minutes for 5,027 archives.
3. Resolved 2026-10-18: the Windows app files EPUB and PDF progress by the core's file identity,
   records narrated listening positions, and renders PDF pages to the view (run 39110775472).
4. Two Mac snapshot references drift by under 1 % in some local runs (`player`,
   `shelf-collection.dark`).

**Suggestion**

1. Give the Linux and Windows wave 4 walks their records before the host pass, so the host pass
   only fills in rows.
2. Cache a file's metadata by modification time and size in StoryArcKit, as the core does, so a
   launch does not re-read every archive.

## The host pass

One checklist for the owner's final pass, by machine. Each line names its task.

**A Linux machine** (GNOME, KDE Plasma, Hyprland, COSMIC; Wayland and X11)

- the walks and captures of waves 2 to 4 on a real session (2.25 to 2.35e, 3.17 to 3.19a, 4.10,
  4.13, 4.14), the Hyprland `hyprctl clients` capture (1.16), and the visual matrix (6.2);
- WebKitGTK 2.44 at the floor and the Flatpak runtime for the EPUB egress test (4.10);
- the Secret Service with and without a daemon and in a Flatpak (3.3, 3.18), a phone tether
  (3.9), a sound device and media keys with another player running (4.13, 4.14);
- Orca on GNOME and Hyprland, and no accessibility service (6.1);
- a file manager showing covers for a source build (5.5), a browser handing a `storyarc://` link
  (5.8), the cold launch at 5,000 (5.9) and the grid at 10,000 (5.10);
- the curl spike on Wayland and X11, then the curl (1.17, 5.2).

**A Windows 11 desktop**

- the walks of waves 2 to 4 (2.37 to 2.47e, 3.21 to 3.23a, 4.16, 4.17, 4.19, 4.20) and the
  conformance record for wave 4 (4.22);
- RAR on MSVC (1.7), the build without Visual Studio (1.20), the Store dry run (6.7);
- Narrator (6.1), the transport controls with another player running (4.19), the link and the
  command line (5.8), the budgets (5.9, 5.10), the visual matrix (6.2);
- the curl spike on D3D11 at 120 Hz, then the curl (1.19, 5.3).

**This Mac or the owner's**

- a VoiceOver session by hand on the library, a reader and the player (6.1);
- a frame with a named system accent (5.11);
- Finder covers once the build is signed (5.4).

**The owner**

- the question to Flathub (1.25), then the Flatpak release (6.5);
- the Apple Developer Program and notarisation, and the Windows signing identity (6.8);
- Handoff from an iPhone once both apps share a team (5.7);
- the iOS parent edits (1.30, 5.12).

## Commands

| Command | Result |
| --- | --- |
| `pnpm test:desktop:core` | passed, 510 tests |
| `pnpm strings:desktop:selftest` | passed, 11 checks |
| `pnpm spec:guard` | passed, one warning: the main spec `opds-catalog` is named by no change |
| `pnpm lint` | passed |
