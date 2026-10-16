# macOS wave 1 — the shell

Taken 2026-10-16 from the ad-hoc build of `apps/desktop-macos` on macOS 26, Xcode 27.1,
with no source configured. Task 1.14 of `desktop-clients`; the base window owed by task 0.10
is the same window and is covered here.

| File | What it shows |
| --- | --- |
| `library-light.png` | The library window, light. Sidebar of the four destinations, Home selected, the *No sources yet* page with its one action, the search field in the toolbar. |
| `library-dark.png` | The same, dark. |
| `library-narrow-light.png` | The library window at its documented minimum, 640 × 440 points, light. |
| `library-narrow-dark.png` | The same, dark. |
| `settings-light.png` | The Settings window, light: six toolbar tabs, Sources first, a grouped form with one grey sentence. |
| `settings-dark.png` | The same, dark. |

## How they were taken, and what that means

`screencapture -l <windowid>` returns "could not create image from window" in this session,
as it did for task 0.10: the process running it has no Screen Recording grant. The frames
were taken instead by `CaptureTests` inside the app itself
(`TEST_RUNNER_STORYARC_CAPTURE=1 xcodebuild test -scheme StoryArc -destination 'platform=macOS'`),
which asks the window server for the app's own windows and writes PNGs into the sandbox
container. Every frame here came back marked `window-server`, so these are the pixels the
display shows, sidebar material included. Dark is the app's own appearance
(`NSApplication.appearance`), not the system's, which was left alone.

Three things to read with that in mind:

- **The window is inactive in every frame**: grey traffic lights, grey title, and the
  prominent button drawn dimmed. A test host launched by `xcodebuild` is refused
  activation on macOS 26, by `activate()`, by Launch Services and by `open` from a shell.
  The real button is the accent colour; the dark frames show its shape.
- **The wide frames are 1800 × 1072 points, not the 1100 × 720 default**: Amethyst, a tiling
  window manager, runs on this Mac and fills the screen with every resizable window. The
  narrow frames exist because the size was locked (non-resizable) for the length of one
  capture, which Amethyst leaves alone.
- **No "largest text size" row.** macOS has no system text size for apps
  (`docs/designs/desktop/macos.md` section 10), so the `desktop-experience` visual-proof
  matrix has only the default size on this desktop. Increase Contrast and Reduce
  Transparency are owed by the design's review checklist and are not here.
