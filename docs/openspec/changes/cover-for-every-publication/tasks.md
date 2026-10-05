A ticked box here means: the code exists on every platform the task names, a test that fails
without it landed, and any frame the change needs exists. A tick does **not** mean a person
watched it on a device.

## 1. The rungs that need no network

- [ ] 1.1 **Finish embedded artwork on the Android Storage Access Framework paths** (android).
  Task 16.9 of `close-the-audited-gaps` covers every path that holds a real file. It is open
  where Android indexes audio through SAF, because neither the single-file nor the folder SAF
  path can reach a file to read. Two call sites in `LibraryScanner.kt`, one reader for a SAF
  child. Write the extracted image to the data directory, not the caches directory.
- [ ] 1.2 **A loose cover image beside the file becomes the cover** (both). `cover`, `folder`
  or `poster`, in the publication's own folder or an audiobook's folder, when the file carries
  no artwork. This is the cheapest rung after the bytes themselves and it is common in ripped
  audiobook folders.
- [ ] 1.3 **One place answers "what is this publication's cover"** (both). The shelf, the
  player, the media session and the publication page each resolve covers today. The ladder has
  to be one function they all ask, or a later rung reaches three of the four. Keep
  `CoverCache`'s key and size behaviour.

## 2. The reader's own picture

- [ ] 2.1 **A cover-override store, keyed by content digest** (both). Outside the caches
  directory. Falls back to the stable identifier for a publication with no digest, and records
  which key it used so the app can say what moving it costs.
- [ ] 2.2 **The system picker sets a cover** (both). `PHPickerViewController` on iOS, the photo
  picker on Android. No permission prompt on either, which is the reason for choosing these two
  over a file-read. Crop to the cover shape before storing.
- [ ] 2.3 **The coverless well offers it** (both). `CoverlessWell` draws a glyph and a format
  name and offers nothing. It becomes the entry point.
- [ ] 2.4 **Removing a chosen cover falls back down the ladder** (both), and deletes the image.
- [ ] 2.5 **A chosen cover survives a cache clear** (both). A test that runs
  `StorageUsage.clearCache` and asserts the cover is still there.
- [ ] 2.6 **Frames**: the coverless well before, and a publication with a chosen cover after, on
  both platforms, light and dark, default and largest text.

## 3. The lookup, off until it is turned on

- [ ] 3.1 **A setting that names its providers** (both), off by default, stating that one
  identifier and nothing else leaves the device.
- [ ] 3.2 **Lookup by identifier** (both): Open Library by ISBN, Cover Art Archive by MBID,
  Audnexus by ASIN. One request per publication. Every answer cached to disk.
- [ ] 3.3 **Lookup by title shows candidates and waits** (both). Never adopts a match on its
  own. Open Library `search.json`, AniList for manga, MangaUpdates — all keyless.
- [ ] 3.4 **A refusal is quiet** (both). 403, 404, 429 or silence leaves the cover as it was,
  shows the reader no error for something they did not ask about, and does not retry in a loop.
- [ ] 3.5 **The egress rule holds** (both). A test that asserts no cover request is made while
  the setting is off.
- [ ] 3.6 **Frames**: the setting, and the candidate chooser.

## 4. The web hand-off

- [ ] 4.1 **The system browser opens an image search for the title** (both).
  `SFSafariViewController` on iOS, a Custom Tab on Android. Not a `WKWebView`, not a
  `WebView` — see design.md, which records why at length.
- [ ] 4.2 **A test asserts the app reads nothing from that browser** (both): no capture, no
  injected script, no image received. The only route in is the picker of task 2.2.
- [ ] 4.3 **Frames**: the hand-off, and the publication afterwards with its new cover.

## 5. Writing back where it works

- [ ] 5.1 **A cover set on a Kavita reading list the reader owns may be written back** (both).
  One POST per client, base64, an 8 MB guard. The confirmation says it changes the cover for
  everyone who can see that list.
- [ ] 5.2 **Nowhere else offers it** (both). A test that asserts no write action appears on a
  Kavita series, chapter, collection or library, nor on any OPDS row, so the feature cannot
  drift into offering a 403.
- [ ] 5.3 **Check the live server** (owner step, android and ios). The repo's Kavita client was
  built against documentation rather than a live instance for some routes. The owner has a
  Kavita server; the upload shape needs one real call before this is claimed to work.
