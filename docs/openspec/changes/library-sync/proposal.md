## Why

A reader with a phone and a tablet reads on both and keeps neither in step. `library-portability`
gives them a document they can carry by hand. This makes carrying it automatic.

## What Changes

- **The sync document lives in a place the reader already configured** — a network share they
  already added, or a folder they pick once with the system picker. StoryArc writes a file
  there and reads it back. No new account, no new service, no SDK.
- **Kavita stays the hub for what Kavita owns.** Reading progress on a Kavita publication
  already synchronises to that server, and that stays the route for those rows; the document
  carries what Kavita cannot hold.
- **Merging reuses ADR-0006's rule**: the furthest position wins, finished is sticky.
- **"Automatic" is defined honestly** and the app does not claim more: on foreground, when the
  reader leaves a publication, and opportunistically in the background within what each
  platform grants.
- **BREAKING, and it is a bug fix**: the sync watermark is never written by production code
  today, so every conflict notice the app shows is false. That is fixed here, because sync
  cannot be built on it otherwise.

## Capabilities

### New Capabilities

- `library-sync`: where the sync document lives, when it is written and read, how two devices
  that both moved are reconciled, and what the app may honestly call automatic.

### Modified Capabilities

- `reading-progress`: the watermark that decides a conflict is specified there, and today
  nothing writes it. The requirement gains a clause that it is written whenever a position is
  synchronised, which is what makes a conflict notice true.

## Impact

**What was asked for, and what this proposes instead.** The ask named iCloud and Google as
possibilities. Neither is proposed as the primary route, and the reasons are not preferences:

- **iCloud never reaches Android.** Apple ships no iCloud app for Android, and a browser at
  icloud.com is not a route an app can drive. iCloud would synchronise an iPhone with an iPad
  and nothing else.
- **Google Drive would work on both**, over plain OAuth with no SDK, but it adds a Google
  account — and `AGENTS.md` non-negotiable 2 is "No backend, no account", with the standard
  "Data leaves the device only to sources the user configured". A folder the reader picked, or
  a share they already added, *is* a source they configured. A Drive account is not.
- **A service the owner runs is rejected outright** by the same non-negotiable.

So the route that fits the project's own contract is also the one that costs the least and
works across platforms. A reader who wants their file on Google Drive or iCloud Drive can pick
that folder in the system picker, and the app never knows the difference — which is the
cleanest way to honour the original ask.

- `ProgressMerge`, `ProgressPull` and `ShelfMerge` exist on both platforms and are reused.
- **`STATUS.md` records the watermark bug**: production never writes it, so every conflict
  notice is false today. Prerequisite.
- SMB write is needed; the share client reads today.
- Android's shortest periodic background work is 15 minutes. iOS grants a background refresh it
  may skip entirely. The spec says what each platform can honestly promise rather than
  promising the same on both.
