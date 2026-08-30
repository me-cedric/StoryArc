# Source connection states

Companion to [`source-connection-states.mmd`](source-connection-states.mmd).

The four states the `sources` capability requires, and every move between them.
Board for the `source-lifecycle` change, requirement 3 (Connection state).

## Read from

| File | Symbols |
| --- | --- |
| `apps/android/core/model/src/main/kotlin/app/storyarc/core/model/Source.kt` | `SourceConnectionState`, `ReconnectBackoff` |
| `apps/android/core/model/src/main/kotlin/app/storyarc/core/model/SourceProbe.kt` | `stateForStatus`, `stateForFailure`, `isRemote` |

Both paths and all five symbols were re-checked against the tree at the time of
writing.

## What the diagram does not say

**A local folder never enters this machine.** `SourceProbe.isRemote` answers
false for `LOCAL_FOLDER`, because whether a folder is readable is a question for
the filesystem rather than one to back off from.

**State is never persisted.** It describes a network, and a state read back from
disk is a claim about the past — so something re-probes after a launch.

**Connected is the only state that can serve a title which is not already
downloaded.** `canFetch` is true there and nowhere else.

**Unreachable is a neutral indicator, never a red error badge.** Offline is a
normal state, not a failure. Downloads stay readable; titles that are not
downloaded are dimmed and not openable.

Backoff starts at 5 s and doubles to a 5 min cap
(`ReconnectBackoff.INITIAL_DELAY_MILLIS` is `5_000`,
`MAXIMUM_DELAY_MILLIS` is `300_000`). The retry on network-regained or
foreground fires immediately, once — which is why two arrows leave Unreachable
for Connecting rather than one.

**404 lands in Unreachable on purpose** rather than in a fifth "gone" state: a
catalogue that has moved is, to a reader, a catalogue that is not answering, and
a reconnect may still fix it.

**Unauthorized is the only state the reader has to act on** — `needsUserAction`
is true. RECONNECT re-opens the sheet the source was added through, address
filled in and secret blank. What comes back carries the same identifier, so
`SourceRegistry.replacing` puts it back with its position, its downloads and the
reader's own name for it intact. "Remove and re-add" loses all three.
