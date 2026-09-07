# Tasks

## iOS

- [x] 1. `about.author` reads `By @me-cedric` in English, and the same handle after the
      translated preposition in German, Spanish and French.
- [x] 2. The byline in `AboutSettings.swift` is a `Link` to `BuildInfo.author`.
- [x] 3. The `about.authorLink` row is removed from `AboutSettings.swift`, and its key is
      removed from `Localizable.xcstrings` in all four languages.
- [x] 4. A test asserts the byline names the handle and opens the author URL, and that the
      screen carries exactly one control to that address.

## Android

- [x] 5. `about_author` reads `By @me-cedric` in English, and the same handle after the
      translated preposition in German, Spanish and French.
- [x] 6. The byline in `AboutGroup.kt` is a `LinkRow` to `https://github.com/me-cedric`.
- [x] 7. `about_author_link` is removed from `AboutGroup.kt` and from `strings.xml` in all
      four languages.
- [x] 8. A test asserts the byline names the handle and that the screen carries exactly one
      control to that address.

## Both

- [x] 9. `pnpm lint` passes, including the string checks, which count the keys each platform
      declares against the keys it draws.
