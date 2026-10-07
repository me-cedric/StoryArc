# A share streams what it can, 2026-10-07

Tasks 14.14 and 14.15 of `close-the-audited-gaps`. A reflowable EPUB, a PDF and a non-solid
CBR open from an SMB share without a whole-file download first. A solid RAR5 is still offered
as a download, with its size.

The share is a guest share served by a copy of `scripts/smb-server.sh` with `guest ok = yes`,
port 4445, over: `Field Notes.pdf`, `Image Pages.pdf`, `Harbour Lights 01.epub`,
`The Long Field.epub` (each EPUB padded to 300 kB, see the iOS note), `Stored Five.cbr` (a
stored RAR5, 3 pages), `Solid Five.cbr` (a solid RAR5), `Tidal Reach 01.cbz`.

## Android, emulator `storyarc-ci`

| Frame | What it proves |
| --- | --- |
| `android-share-rows-light.png`, `-dark.png` | The share rows in the library. |
| `android-share-pdf-page-light.png`, `-read-light.png` | A PDF: the page says "Read" and "not downloaded". The reader opens at page 1 of 5. |
| `android-share-epub-page-light.png`, `-read-light.png` | A reflowable EPUB opens at Chapter 1. |
| `android-share-cbr-page-light.png`, `-read-light.png` | A stored RAR5: "Read", then page 1 of 3. |
| `android-share-solid-page-light.png`, `-offer-light.png` | A solid RAR5: "Download it", with "(1.0 kB)". |

In all three streamed cases the app's `files` directory stayed empty. Nothing was downloaded.

Instrumented tests on the emulator: `RarDecoderInstrumentedTest` (13 cases, both new cases
among them: a non-solid compressed RAR5 entry and a RAR4 entry decode from their own ranged
bytes) and `PdfStreamingInstrumentedTest` (1 case: a remote PDF renders page 1 without a
whole read). All 14 passed.

## iOS, simulator iPhone 17 Pro Max, iOS 26.4

| Frame | What it proves |
| --- | --- |
| `ios-share-epub-page-light.png`, `-read-light.png` | A reflowable EPUB opens from the share. |
| `ios-share-cbr-page-light.png`, `-read-light.png` | A stored RAR5 opens page by page from the share. |
| `ios-share-pdf-page-light.png`, `ios-share-pdf-offer-light.png`, `-dark.png` | A PDF on the publication page: **the app still offers "Download it first?"**. |
| `ios-share-solid-page-light.png`, `-offer-light.png` | A solid RAR5: the download offer, with its size. |

## Findings

1. **The iOS share browser has no way in.** `SmbBrowserView`, which fetches a PDF whole and shows
   a progress bar, is reached only from a search result or from the Kavita offer. No SMB
   source reaches it from the library. So a reader meets the publication page, and that page
   still offers the PDF as a download (frame `ios-share-pdf-offer-*`). Decision O4 is not met
   for a reader until a way in exists, or until the publication page fetches without an offer.
2. **Readium crashes on a small remote ZIP in the simulator.** `ZIPFoundationArchiveFactory`
   subtracts a 64 kB tail length from the ZIP length in unsigned arithmetic when
   `canAllocate` answers no. The simulator always answers no. A ZIP under 64 kB then traps
   with "arithmetic overflow". The corpus EPUBs are 2 to 3 kB, so each EPUB here is padded to
   300 kB. A real device answers yes and is not affected.
3. **No compressed RAR with image pages exists in the corpus.** The compressed fixtures hold
   `.bin` and `.txt` entries. The compressed path is proven by the instrumented tests above and
   by the host tests, and the live frames use a stored RAR5.
4. A frame for the progress bar of an iOS PDF fetch could not be taken, for finding 1.

## How to repeat

```bash
sed -e 's/map to guest = Never/map to guest = Bad User/' -e 's/guest ok = no/guest ok = yes/' \
    -e 's/server signing = mandatory/server signing = auto/' scripts/smb-server.sh > /tmp/smb-guest.sh
/tmp/smb-guest.sh <folder> 4445
# Android
adb shell pm clear com.mecedric.storyarc.debug   # launch once, then:
node scripts/seed-android-sources.mjs --share
# iOS
node scripts/capture-ios.mjs --out <dir> --only ShareRowWalkTests/testCaptureShareEpubStreams --device <udid>
# also testCaptureShareCbrStreams, testCaptureSharePdfFetched, testCaptureShareSolidRarOffered
```
