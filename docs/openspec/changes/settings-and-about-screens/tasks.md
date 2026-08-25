# Tasks — Settings and About screens

## Phase 1 — The store and the appearance

- [ ] **1.1** A settings store on both platforms, beside `ReaderPreferences` and
      `LibraryPreferences` rather than inside either: appearance, language
      override, and the reading defaults, with the same "unreadable stored data
      reads as no data" rule the theme store already uses.
- [ ] **1.2** Extend `AppearanceMode` to System / Light / Dark / OLED Dark on both
      platforms, with the OLED reader surface deliberately above true black and the
      reason stated in the setting. This is
      `reader-theming-and-page-transitions` 5.1 and 5.3, and it lands here because
      that change has nowhere to select it.
- [ ] **1.3** Appearance applies without a restart and follows the system while
      backgrounded. Verified by capture on the emulator, both directions.
- [ ] **1.4** Appearance leaves the reading theme alone — the spec's own scenario,
      and a test rather than an observation, because the two stores are separate and
      it would be easy to make one write the other.

## Phase 2 — Organisation

- [ ] **2.1** The seven groups, each with a summary row stating its current value.
      Sources and Downloads carry their group and summary only; their rows arrive
      with the connectors and `offline-downloads`.
- [ ] **2.2** Search across settings, listing each match with its group path, and
      navigating to it highlighted.
- [ ] **2.3** Reading defaults: the *global* half of
      `reader-theming-and-page-transitions` 3.10. Changing one must not overwrite a
      per-series choice already made — `ShelfMemory.settingDefault` already
      guarantees that by construction, so this is the screen for it plus the test
      that says so through the store.
- [ ] **2.4** Reset to defaults, confirming first and stating explicitly that
      sources, downloads and reading progress are untouched.

## Phase 3 — Privacy

- [ ] **3.1** The privacy statement: no account, no backend, no analytics, no crash
      reporting, and that data leaves the device only to sources the reader
      configured. Written once and quotable, because it is a claim the app has to
      keep.
- [ ] **3.2** Individually clearable cache, reading history and downloads, each
      stating what it removes and how much space it frees.
- [ ] **3.3** Diagnostic export: shown before sharing, with every credential, token
      and server hostname redacted. The redaction is a tested function, not a
      regex written at the call site.

## Phase 4 — About

- [ ] **4.1** Version and build, the author, the repository link, the licence.
- [ ] **4.2** The free-and-open statement, and one Ko-fi link that appears only
      here — never as a prompt, an interstitial or a nag.
- [ ] **4.3** Acknowledgements, with every third-party licence in full. This is
      what `format-scope-and-libraries` 6.1 and `reading-themes` are waiting on:
      the five bundled OFL notices already ship inside both apps, and nothing shows
      them.
- [ ] **4.4** Report a problem: opens the issue tracker with version, platform
      version and device class pre-filled, and no personal data.

## Phase 5 — Unblocking what waited

- [ ] **5.1** Volume-button page turns, off by default —
      `reader-theming-and-page-transitions` 4.6, which was held because volume keys
      that silently stop changing the volume are a defect rather than a feature.
- [ ] **5.2** A custom reading colour for comics, so the matte around a fixed-layout
      page has a value to take — that change's 3.11.
- [ ] **5.3** Natural as a theme with its own light and dark variants, and its grain
      on reading surfaces only — that change's 5.2, 5.4 and 5.5, which need an
      appearance setting to hang from.

## Phase 6 — Validation

- [ ] **6.1** `pnpm check` green: specs, tokens, tests and both lints.
- [ ] **6.2** Emulator and simulator captures of every screen, light and dark, at
      default and largest text size.
- [ ] **6.3** Accessibility pass over the lists and the search.
- [ ] **6.4** `/opsx:sync`, if any requirement turned out to need changing — and if
      none did, say so, because "the spec was right" is worth recording.
