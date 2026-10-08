# A PDF on a share is fetched, then opened (iOS) — 2026-10-07

Task 14.15 of `close-the-audited-gaps`, owner decision O4. On iOS the publication page of a
PDF on a share fetches the whole file with progress and opens it in PDFKit. It no longer asks
"Download it first?".

| Frame | What it proves |
| --- | --- |
| `ios-share-pdf-fetching.png`, `-dark.png` | A moment after Read. The page of *Field Notes* is on screen, and a bar along the foot reads "Fetching Field Notes…" with determinate progress. No "Download it first?" dialog. |
| `ios-share-pdf-fetching-later.png` | The same run 15 seconds later. The reader is up and its page shows "This page could not be read" while the 2.6 GB file is still being mapped. Not a regression claim. See below. |
| `ios-share-pdf-opened.png`, `-dark.png` | The PDF open in the reader, on page 1 of 5. |

**The file.** The corpus `Field Notes.pdf` is 2 KB, so the fetch ends before a screenshot. The
frames use a copy padded to 2.6 GB after `%%EOF`, served by `scripts/smb-server.sh --encrypted
<corpus-copy>` on port 4446. The share is the signed-in `127.0.0.1/Comics` that
`SmbEncryptedWalkTests` registers (the fixture on 4445 serves no guest). A copy padded to 300 MB
fetched and opened inside two seconds, with no frame of the bar. The padded copy and the fetched
cache were deleted after the run.

**Observation.** With the 2.6 GB file the reader showed "This page could not be read" for a while
and then drew page 1. The 300 MB copy opened at once. This looks like PDFKit mapping a very large
file. It is recorded, not fixed.

## How to repeat

1. Run `SmbEncryptedWalkTests/testCaptureShareDetailEncrypted` once (it registers the share).
2. `node scripts/capture-ios.mjs --out <dir> --only ShareRowWalkTests/testCaptureSharePdfFetching --device <udid> --appearance light`, and `dark`.
