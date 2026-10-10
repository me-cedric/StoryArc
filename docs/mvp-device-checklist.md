# Device checklist

Rewritten 2026-10-10, at the end of the close-all-yellow goal. Each step is one that a
simulator, an emulator or a mock server cannot answer. Each line names the task that
records the result. When a step passes, tick its task and remove the line.

Steps that a wave proved on a simulator, an emulator or a live server are removed. Git
holds the earlier version of this page, with the reason for each step. Work that needs
only a free simulator or emulator is not here: `pnpm partial:tasks` lists it.

Kavita and SMB steps need the owner's servers. Run each on both phones.

## Android phone

- Drag a finger down the A to Z rail. Feel one tick for each new letter. Task: `close-the-audited-gaps` 24.6.
- With TalkBack in French, swipe once on a file that did not open. Hear the name and the reason together. Task: `one-vocabulary-in-four-languages` 1.8.
- With TalkBack, check that each sleep-timer chip (5, 15, 30 and 45 min) is read once. Task: `audiobooks-and-playback` 8.1.
- On the phone that froze, record a Perfetto trace or `adb shell dumpsys gfxinfo` while the library rotates. Task: `close-the-audited-gaps` 21.1.
- Read in sunlight and at night. Judge the themes, the brightness and the paper grain in light and dark. Task: `reader-theming-and-page-transitions` 0.5.
- Start a second drag while a curl settles. The page does not snap. Task: `reader-theming-and-page-transitions` 7.5.
- Listen with TalkBack over the reader theme sheet. Task: `reader-theming-and-page-transitions` 7.6.
- Turn pages with the volume buttons, with the setting off and on. Task: `reader-theming-and-page-transitions` 4.6.
- Start read-aloud, back out of the reader, and hear the voice continue. Task: `read-aloud-beyond-the-reader` 0.2.
- During read-aloud, take a call and hang up. The voice resumes; after a pause it stays silent. Task: `read-aloud-beyond-the-reader` 4.1.
- Play an audiobook, open an EPUB, start read-aloud, take and end a call. Only the voice speaks. Task: `audiobooks-and-playback` 6.1.
- Play a book over headphones and disconnect them. The audio pauses and does not restart on reconnect. Task: `audiobooks-and-playback` 3.9.
- In "Your libraries", open a row's overflow menu, and drag a row to a new place. Task: `close-the-audited-gaps` 27.3.
- Pick a Google Drive folder as the sync place. Sync, relaunch, and see the file on the other device. Task: `library-sync` 2.3.
- Turn sync on, read to a new page, lock the phone for 20 to 30 minutes. Device B shows the position. Task: `library-sync` 4.3.
- Export the library, and import the file on another device. Task: `library-portability` 2.5.
- Add a file to a picked folder from another app. The library shows it. Task: none.
- Use the manual library refresh. It does what its label says. Task: none.
- With TalkBack, hear what the web view on the publication page says. Task: none.
- Kavita: add the server from the app, end to end. Task: none.
- Kavita: reorder a reading list, and check the order on the server. Task: `close-the-audited-gaps` 7.4.
- Kavita: add a publication to a server collection. Task: none.
- Kavita: send a cover to a list you own, and check the web interface. A list of another user shows no button. Task: `cover-for-every-publication` 5.3.
- SMB: add a share by a bare host name. The message does not say that the share is missing. Task: none.
- SMB: cut the network while a page loads. See the 2 s and 60 s notices, then the read resumes. Task: `close-the-audited-gaps` 5.4.
- SMB: scan a share with 10000 files. The scan finishes and the list stays responsive. Task: `close-the-audited-gaps` 22.1.
- SMB: open a folder with no read permission. The message names the cause. Task: none.

## Android tablet

- On a 10-inch tablet in landscape, check the 840 dp cover tier and the two-pane layout. Task: `publication-detail` 4.2.
- On a foldable at half-open (a Pixel Fold AVD also answers it), open a publication in the library pane. Task: `one-library-three-destinations` 4.2.

## iPhone

- Start a download, leave the app and lock the phone. After the transfer window, the download is complete. Task: `close-the-audited-gaps` 1.3.
- Turn Wi-Fi off: the download queue holds. Turn Wi-Fi on: the queue resumes. Task: `close-the-audited-gaps` 1.3.
- Measure the curl frame rate on the oldest supported iPhone and on a 120 Hz iPhone. Task: `reader-theming-and-page-transitions` 0.3.
- Read in sunlight and at night. Judge the themes, the brightness and the paper grain in light and dark. Task: `reader-theming-and-page-transitions` 0.5.
- Start a second drag while a curl settles. The page does not snap. Task: `reader-theming-and-page-transitions` 7.5.
- Listen with VoiceOver over the reader theme sheet. Task: `reader-theming-and-page-transitions` 7.6.
- Drag a finger down the A to Z rail. Feel one tick for each new letter. Task: `close-the-audited-gaps` 24.6.
- With VoiceOver in French, swipe once on a file that did not open. Hear the name and the reason together. Task: `one-vocabulary-in-four-languages` 1.8.
- Open the cover menu on a publication page. The subtitle of the web row wraps fully. Task: `close-the-audited-gaps` 24.1.
- Share a real CBZ and a real EPUB from Files, Mail and another app. Each one arrives. Task: none.
- Start read-aloud, close the reader, lock the phone, and hear the voice continue. Task: `read-aloud-beyond-the-reader` 0.1.
- During read-aloud, take a real call and hang up. The voice resumes and keeps its position. Task: `read-aloud-beyond-the-reader` 4.2.
- Pick an iCloud Drive folder as the sync place. Sync, relaunch, and see the file on the other device. Task: `library-sync` 2.3.
- Turn sync on, read, lock the phone for 20 to 30 minutes. The background refresh writes the position. Task: `library-sync` 4.3.
- Export the library, and import the file on another device. Task: `library-portability` 2.5.
- Add a file to a picked folder from another app. The library shows it. Task: none.
- Kavita: add the server from the app, end to end. Task: none.
- Kavita: reorder a reading list, and check the order on the server. Task: `close-the-audited-gaps` 7.4.
- Kavita: add a publication to a server collection. Task: none.
- Kavita: send a cover to a list you own, and check the web interface. A list of another user shows no button. Task: `cover-for-every-publication` 5.3.
- SMB: add a share by a bare host name. The message does not say that the share is missing. Task: none.
- SMB: cut the network while a page loads. See the 2 s and 60 s notices, then the read resumes. Task: `close-the-audited-gaps` 5.4.
- SMB: scan a share with 10000 files. The scan finishes and the list stays responsive. Task: `close-the-audited-gaps` 22.1.
- SMB: open a folder with no read permission. The message names the cause. Task: none.

## iPad

- Put StoryArc in Split View beside another app. Drag the divider narrow, then wide. One pane, then the same publication in both. Task: `one-library-three-destinations` 4.1, 4.3; `publication-detail` 4.1.

## Apple Developer team

- Set `DEVELOPMENT_TEAM` in `apps/ios/project.yml` and install. Add the widget, read a book, check cover, title and part read. Task: `close-the-audited-gaps` 20.1.
- Get the `carplay-audio` entitlement and build for a device. In a car, take the four steps of the design note. Task: `audiobooks-and-playback` 12.6.
- Notarise the macOS desktop app. Task: `desktop-clients` 6.8.
