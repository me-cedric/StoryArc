# The reference sweep

This directory is empty on purpose. It holds the baseline that
[`scripts/capture-compare.mjs`](../../../../scripts/capture-compare.mjs) compares a fresh
sweep against, and `native-experience`'s **Screen change** scenario is the requirement it
serves.

**Taking the baseline is the owner's decision.** It needs a booted simulator and a running
emulator, it takes minutes, and it writes hundreds of PNGs that every later comparison is
measured against. No agent takes it without being asked. A wrong baseline is worse than no
baseline, because every frame after it inherits the mistake.

## What goes in it

One PNG for each frame of a full sweep, at every condition in
[`scripts/device-matrix.mjs`](../../../../scripts/device-matrix.mjs). Print the table:

```bash
node scripts/device-matrix.mjs
```

The file name carries the condition, so a light frame and a dark frame of one screen cannot
overwrite each other. `capture-compare.mjs` pairs a fresh frame with a reference frame by
name, so a renamed frame is a frame with no reference.

| Platform | Conditions | Frames |
| --- | --- | --- |
| Android | light and dark, font scale 1.0 and 2.0 | 4 per route, and `pnpm capture:android --list` prints 96 routes |
| iOS | light and dark | 2 per walk. The largest text size is not a condition here: the walks set it themselves and attach those frames under names ending `-ax5` |

## The commands that fill it

Seed the devices first. A sweep of an unseeded device photographs empty screens, and
`AGENTS.md` section 5 measured that cost: 42 skipped and 11 failed cases of 107.

**iOS.** Build the UI tests, seed the simulator, then sweep both appearances.

```bash
pnpm build:ios:ui
pnpm seed:ios:ui
pnpm capture:ios --out docs/designs/screenshots/reference --matrix
```

**Android.** Seed the emulator, then sweep every route in every condition.

```bash
node scripts/corpus.mjs --simulator <udid>
pnpm capture:android --list | while read -r route; do
  pnpm capture:android "$route" --out docs/designs/screenshots/reference --matrix
done
```

## Comparing against it

```bash
pnpm capture:compare --fresh <a fresh sweep directory>
```

The command exits non-zero when it compared nothing. An empty reference directory is the
normal state of a fresh checkout, and a tool that answered "no differences" to it would pass
a comparison that never happened.

## Refreshing it

Replace a frame when the change that altered it is approved, and in the same commit as that
change. A reference frame updated on its own is a regression nobody will find, because the
next comparison measures against the new picture.
