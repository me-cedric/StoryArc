# A volume that is not one — 2026-09-11

The chapter list of a Kavita series that has no volumes, on a OnePlus 7T Pro
(`f7cee850`, 1440 × 3120), against the owner's own server
`kavita.cedricmeyer.eu`. Series: *00 - Brightest Day Main Event*, 25 loose
chapters, no volumes, no specials.

## What a reader met

`android-loose-chapters-after.png` — the heading reads **Chapters**.

Before the fix it read **-100000**. There is no "before" frame, because the
defect was found by walking the live app and the phone was upgraded in place
before a frame was taken. What stands in its place is the accessibility dump
of that same screen, taken minutes earlier on build `969632ce`:

```
'Status: Ongoing' [70,352][395,380]
'-100000' [70,436][268,506]
'0' [70,520][1370,688]
'1' [70,688][1370,856]
```

and the same dump after:

```
'Status: Ongoing' [70,352][395,380]
'Chapters' [70,436][285,506]
'0' [70,520][1370,688]
'1' [70,688][1370,856]
```

Same screen, same server, same series. Only the heading changed.

## Why one guard was not enough

`KavitaChapter.issueNumber` had already been taught that `-100000` is a
sentinel. The volume beside it had not. `KavitaVolume.isLooseChapters` tested
`number == 0`, which is what an older Kavita wrote; a current server writes
`-100000`, so the test failed and the screen fell through to drawing the
number.

Quoted from Kavita's own `Kavita.Models/Constants/ParserConstants.cs`:

```csharp
public const int LooseLeafVolumeNumber = -100_000;
public const int SpecialVolumeNumber = 100_000;
```

**The specials number is positive.** A guard written against negative
sentinels — which is what the chapter fix was — cannot catch it. That is the
reason the volume heading needed its own rule rather than a reuse of the
chapter's.

## Not shown

**Specials.** No series on this server has any, so no frame proves that a
specials volume is now headed *Specials* rather than *100000*.
`VolumeSentinelTest` and `VolumeSentinelTests` assert the rule on both
platforms, and this paragraph is the record of what no frame covers.

**iOS.** The simulator has local fixtures and no server, so it has no Kavita
volume to head at all. The twin is `KavitaChapterList.heading(_:)`, asserted
by `VolumeSentinelTests`.
