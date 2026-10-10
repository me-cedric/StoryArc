# App Store listing — English (default)

App Store Connect's fields, not Play's: there is no feature graphic, the marketing icon
comes out of the binary, and *Subtitle*, *Promotional text* and *Keywords* have no Play
equivalent. The other three files in this folder are translations of this one.

`scripts/store-listing-ios.mjs --verify` counts every field against Apple's limit.

## App name

```
StoryArc
```

## Subtitle

```
Comics, books, audiobooks
```

## Promotional text

`170 characters. Changeable without submitting a new build, so this is the field for what is new.`

```
Reads CBZ, CBR, CBT, EPUB, PDF and audiobooks from your own folders, network shares, OPDS catalogues and Kavita servers. No account. No analytics. No ads.
```

## Keywords

`100 characters, comma-separated, no spaces after the commas.`

```
comic,cbz,cbr,manga,epub,ebook,pdf,audiobook,opds,kavita,smb,offline,reader,library
```

## Description

```
StoryArc is a reader for the comics, books and audiobooks you already have.

Point it at a folder on your iPhone, a share on your home network, an OPDS catalogue or your own Kavita server, and your library appears. There is no sign-up, no subscription and no upload step. Your files stay where you put them.

WHAT IT OPENS

• Comics — CBZ, CBR (RAR4 and RAR5) and CBT
• Books — EPUB 2 and EPUB 3, reflowable and fixed-layout
• Documents — PDF, including scanned, image-only ones
• A plain folder of numbered images, read as one publication
• Audiobooks — M4B, M4A, MP3, AAC, FLAC, Opus, Ogg and WAV

The format is decided by what is inside the file, not by its extension, so a mis-named download still opens.

WHERE YOUR LIBRARY CAN LIVE

• A folder you choose on this device
• A share on your home network, over SMB
• Any OPDS catalogue
• Your own Kavita server, with reading progress kept in step both ways

A READER THAT GETS OUT OF THE WAY

The artwork is the interface. Controls appear when you ask for them and hide again while you read, and they never tint the page.

• An interactive page curl that follows your finger, with a slide and a fast fade if you would rather it did not
• Double-page spreads are recognised and shown whole, never split across two turns
• Pages are decoded again at full resolution when you zoom, so small lettering stays readable
• Where you stopped is remembered per publication, and picked up on the page you left

Reflowable books get their own typography: size, typeface, bold text, line, character, word and paragraph spacing, margins, alignment, hyphenation, background colour and brightness. The typeface list includes the publisher's own fonts, the system serif and sans, three bundled reading serifs, and Atkinson Hyperlegible. Reading themes can be set for one series and left alone everywhere else.

LISTENING, AND BEING READ TO

Audiobooks play with chapter navigation, variable speed and a sleep timer, and they carry on with the screen off. A book can also be read aloud, and the voice keeps going past the end of the page. Audiobooks appear in CarPlay.

BUILT FOR BEING OFFLINE

An unreachable server is a normal state here, not an error. Your library stays browsable, everything you have downloaded stays readable, and reading progress is recorded on the device and reconciled when the source comes back. Downloads can wait for Wi-Fi and stay inside a storage budget you set.

FINDING THINGS AGAIN

Series are grouped into one cell instead of filling the shelf. Shelves and reading lists are yours to arrange, in your own order. Sort by title, series, date added, date released, last read, progress or file size. Filter by read state, download state, format, source or language, and combine as many filters as you like. Search covers titles, series, authors, publishers and tags, across every source you have added.

PRIVACY, PLAINLY

StoryArc has no account, no backend, no analytics and no crash reporting. Data leaves your device only to the libraries you set up yourself. Server credentials go to the keychain — never to preferences, logs or backups — and they are removed from the diagnostic export before it is shown to you.

FREE AND OPEN SOURCE

No paid tier, no in-app purchases, no advertising. The app is open source, and the full licence text of everything it ships is readable inside it.

MADE FOR IPHONE AND IPAD

SwiftUI throughout. On iPad the library and a publication share the window as two columns, and the sidebar carries your shelves. Light and dark follow the system. Every screen works at the largest Dynamic Type size and with VoiceOver. English, French, German and Spanish, and the app's language can be set on its own without changing the system's.

Requires iOS or iPadOS 26.1.
```
