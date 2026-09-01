# The sort chip says it is an ordering — Android, 2026-09-01

`named-failures-and-quieter-chrome` §3.1. `library-browsing`, *An ordering says that it is an
ordering*: "a reader seeing the field name alone cannot tell a sort from a filter".

## What the pictures show

The library's chip row, before and after, in both appearances and at both ends of the text
scale. Eight files, one condition each.

| | Light | Dark |
| --- | --- | --- |
| **Before**, default text | `before-light-default.png` | `before-dark-default.png` |
| **Before**, `font_scale 2.0` | `before-light-largest.png` | `before-dark-largest.png` |
| **After**, default text | `after-light-default.png` | `after-dark-default.png` |
| **After**, `font_scale 2.0` | `after-light-largest.png` | `after-dark-largest.png` |

**Before**, the row reads `On this device · Title · Filter`. Two of those three chips narrow
what is on the shelf; the middle one orders it. Nothing on any of them says which is which,
and the middle one is the only label that is a bare noun — so *Title* sits between two
narrowing controls looking like a third.

**After**, it reads `On this device · Sort: Title · Filter`.

The change is four strings and one shared label helper. The seven field names are reused
verbatim rather than respelt, because a second wording of *Size on this device* in one app is
how a vocabulary comes apart.

## The row still wraps

`after-*-largest.png` is the half of this that could have gone wrong. The row is a `FlowRow`
and it earned that the hard way — it scrolled sideways once and put *Filter* half out of the
window with nothing on screen saying so. A longer label is exactly the pressure that defect
came from.

At `font_scale 2.0` the row now takes two lines — `On this device · Sort: Title`, then
`Filter` and the layout toggle — with nothing clipped and nothing past the edge. The chip
grows taller rather than wider when a label needs it, because a chip label is ordinary text.

`ListOrderChipsWrapTest` and `ScopeChipsWrapTest` assert the same property in four locales at
320 dp, and both measure the **composed** label now.

## How these were taken, and how the build in them was verified

```bash
pnpm capture:android Library --out <file> [--dark] [--font-scale 2.0]
```

`storyarc-j6`, API 36, started with `-gpu host` — on software GL the app looks broken and is
not.

The emulator is shared, and an install on it can report `Success` and then be discarded when
the device reloads its boot snapshot, which produces a capture of the previous build that
looks perfectly convincing. Two independent checks, not one:

- `dumpsys package app.storyarc.debug` gave `lastUpdateTime=2026-09-01 19:04:51` against a
  device clock of `19:05:21` — the install was thirty seconds old, not this morning's.
- The installed `base.apk` was read back off the device and searched for the German string
  `Sortierung: `, which exists only in this change. It is there. That is a check on the
  *contents* of the build, which no timestamp can give.

The captures are their own third check: a build without this change cannot draw
`Sort: Title`.

## What these pictures do not show

**Dynamic colour is on in every one of them**, which is the default `native-experience` asks
for, so the `+`, the overflow dots and the layout toggle are wallpaper-derived rather than
StoryArc's accent. That is correct behaviour and not the subject here. The brand accent's own
path — dynamic colour off — is `brand-identity-and-app-icons` §1.7.

The failure notice above the chips belongs to §1 and is another agent's work, already merged;
it is in frame because it sits on the same screen, not because it changed here.
