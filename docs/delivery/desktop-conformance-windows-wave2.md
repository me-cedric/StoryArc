# Windows wave 2 conformance, part one

Status: written without a .NET SDK and without Windows. Nothing here has compiled or run. The Desktop Windows
workflow is the first compiler, and a walk on a Windows 11 machine (task 2.48) is the only proof of a screen.
Each row says what is pure and tested, what is wired and unwalked, and what is not started.

| Scenario (capability desktop-experience) | Where | State |
| --- | --- | --- |
| The window model: a reader window per publication, a second open finds the first | `WindowRegistry`, `AppHost.OpenReader`, `ReaderWindow` | pure part tested; windows wired, unwalked |
| Windows come back after a quit or a crash | `SessionState`, `RestorationPlan`, `SessionRecorder`, `WindowPlacement` | pure part tested; restore wired, unwalked |
| A display that is gone | `WindowFrame.FitTo` over `DisplayArea.FindAll` | pure part tested; wired, unwalked |
| A publication that cannot be reopened | `RestorationPlan` | tested; the app passes "every reader reopens" until the library seam (task 2.1) can answer |
| Every command is in a menu | `CommandTable`, `MenuBuilder`, `AppMenu` (MenuBar, "..." under 720) | table tested; menus wired, unwalked |
| The standard shortcuts: Control and W closes, Quit in File with no key, Alt and F4 is the system's | `CommandTable`, `CommandRouting` | tested; wired, unwalked |
| A command that does not apply | disabled entries, same menu shape | tested (scope and routing); unwalked |
| A shortcut while typing | plain keys are never window accelerators | by construction; unwalked |
| Full screen reading: enter, leave with Escape or the key, size restored | `FullScreenState`, `ReaderWindow` with `AppWindow.SetPresenter` | pure part tested; wired, unwalked |
| A system that refuses full screen | `FullScreenState.Refused`, entry shown disabled | wired; the grey sentence is not shown (see below) |
| The interface accent and the system appearance | `ChromeAccent`, `AccentApplier`, `AppearanceTheme`, `SettingsStore`, `PreferencesPage` | pure part tested; wired, unwalked |
| Searching the preferences | `PreferencesIndex`, `PreferencesPage` | pure part tested; page wired, unwalked |

## Not done in this part

- Menu commands other than close, quit, settings and full screen are listed and shown disabled: each later task adds its id to `CommandRouting`.
- The full-screen refusal says nothing in words: the sentence needs a catalogue string that `pnpm strings:desktop` has not generated.
  The strings `settings_transparency_note` and `settings_appearance_pending` are English fallbacks in code for the same reason.
- The pointer is not hidden at rest in full screen (`CursorHider` is ready); only the menu bar hides.
- The reader window shows its publication id and page number. The page view (2.40), opening files (2.42), folders (2.43),
  the library views (2.47a to 2.47d) and the walk (2.48) wait for the seam.
- OLED Dark and Natural are saved and shown with a note; the chrome takes the nearest theme until their token dictionaries are drawn.
- The preferences rows without a setting behind them (sources, downloads, language and the rest) show their title only.
- The page uses a `Border` row, not Community Toolkit `SettingsCard`, because the lane adds no package.
