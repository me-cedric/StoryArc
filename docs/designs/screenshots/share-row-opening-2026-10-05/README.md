# A share row opens from the library — tasks 5.13 and 7.7

Evidence for `close-the-audited-gaps` tasks 5.13 (a share row in the library opens its
share-relative path as a local file) and 7.7, second half (a bulk download skips share
items silently).

Captured on 2026-10-05, iPhone 17 Pro simulator, iOS 26.2, against a real SMB 2 server:
`scripts/smb-server.sh`'s fixture corpus served read-only to a guest on `127.0.0.1:4447`,
added in the app as a library.

| Frame | What it shows | Appearance | Text size |
| --- | --- | --- | --- |
| `ios-share-pdf-page-light.png` | The publication page of a share-hosted PDF, with a primary action. Before this change `file` asked the filesystem about `smb://nas/Comics/Field Notes.pdf`, got no, and the page drew no action at all and the sentence *This one has to be on your device before it opens* | light | default |
| `ios-share-download-first-light.png` | The same row tapped: `publication-formats`' offer, naming the file and stating the 2 kB the share's own directory entry reported | light | default |
| `ios-share-pdf-kept-dark.png` | After the offer was accepted. The chunked copy landed and the provenance line now reads *On this device, readable with no network · Also in 127.0.0.1/Comics* | dark | default |
| `ios-share-cbz-streams-light.png` | A share-hosted CBZ, which **streams**: the same tap opens page one over SMB with no dialog and no transfer | light | default |

The series screen behind two of these reads **1 of 2 on this device** with the share row
present, which is task 5.13's *do not count it as on the device*.

The copy was checked on disk as well as on screen: the app's download store holds
`Downloads/path-smb---127.0.0.1-4447-Comics-Field-20Notes.pdf/Field Notes.pdf` at 2038
bytes, byte-for-byte the length of the file on the share.

## Android is not photographed here, and this is why

The Android twin of this change could not be reached on an emulator. Opening *Add a
library → A computer on your network* starts SMB discovery, and the app dies before the
sheet is usable:

```
FATAL EXCEPTION: ConnectivityThread
java.lang.IllegalArgumentException: listener already in use
    at android.net.nsd.NsdManager.putListener(NsdManager.java:1194)
    at android.net.nsd.NsdManager.resolveService(NsdManager.java:1650)
    at app.storyarc.core.smb.SmbDiscovery$hosts$1$listener$1.onServiceFound(SmbDiscovery.kt:64)
```

`SmbDiscovery.hosts` builds **one** `NsdManager.ResolveListener` and hands that same
object to `resolveService` for every service `onServiceFound` reports. `NsdManager`
refuses a listener that is already in use, so the second SMB host on the network kills the
process. It is reproducible on `storyarc-ci` with two hosts advertising, and it is not
this change's doing: `apps/android/core/smb/` is untouched on this branch, and the line
has been there since `3346073e`.

A share added before that crash still works — the crash is in discovery, not in the share
— so the Android frames are owed the moment a device can add a share again.
