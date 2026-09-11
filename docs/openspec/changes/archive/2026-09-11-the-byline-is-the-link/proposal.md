# The byline is the link

## Why

About shows the author's legal name as plain text, and offers a separate row called
*The author on GitHub* that opens <https://github.com/me-cedric>. Two rows carry one fact,
and the row a reader looks at is the one that does nothing.

The owner asked for the byline to name the handle and to open the profile itself.

## What changes

The byline reads **By @me-cedric** and opens <https://github.com/me-cedric>. The separate
author row goes, because the byline now satisfies the clause that asked for the link.

Nothing else on the screen moves. The version row above it and the free statement below it
are unchanged, and the repository, licence, support and report rows keep their order.

## Impact

- Specs: `settings-and-about`, the `About` requirement, the *About contents* scenario.
- iOS: `AboutSettings.swift`, `Localizable.xcstrings` in `SettingsFeature`.
- Android: `AboutGroup.kt`, `strings.xml` in four languages.
- One string is removed on each platform, so the translation count falls by four per platform.
