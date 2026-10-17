# desktop-strings

The strings only a desktop needs, in the four languages, as one Apple string catalogue.

| File | What it holds |
| --- | --- |
| `Localizable.xcstrings` | Keys the Windows and Linux shells read and the iOS catalogues do not define: menu and shortcut labels, the folder prompt, the appearance notes. |

`scripts/strings-desktop.mjs` reads this catalogue beside the iOS ones and writes the
Windows `.resw` and the Linux `.po` files from both; `pnpm strings:desktop:check` fails
`pnpm lint` when the outputs drift. Keys are dotted like the iOS keys, so the `.resw` name of
`settings.transparency.note` is `settings_transparency_note` and a `%@` placeholder becomes
`{0}` there and `%s` in the `.po`. A key the iOS catalogues already define must not be
repeated here; the generator keeps the first and prints the collision.

The macOS app does not read this file: its own strings live in
`apps/desktop-macos/App/Localizable.xcstrings`.

Test: `pnpm strings:desktop:check` and `pnpm strings:desktop:selftest`.
