## Context

`Theme.kt` already decides the scheme correctly. Its branch order is: true black wins, then
Natural, then dynamic colour, then the brand light or dark scheme. Both values of the flag
already work and are already tested. The only thing wrong is which value a fresh install
starts with.

So this change is one boolean, one sentence in four languages, one test, and the frames that
prove it. There is no new code path, and no new type.

## Goals / Non-Goals

**Goals.** One accent on both platforms for a reader who changes nothing. Keep Material You
reachable in one tap for a reader who wants it.

**Non-Goals.** Removing dynamic colour. Touching the cover-derived accent. Touching iOS, which
has no wallpaper scheme to opt out of. Changing the order of the branches in `Theme.kt`.

## Decisions

### An existing install keeps its own answer

`SettingsStore` reads a stored `AppSettings`. A reader who already used the app has a stored
record, and that record says `useDynamicColor = true` whether they chose it or merely accepted
it. Changing `Defaults` does not rewrite a stored record, so their app does not change colour
under them on an update. That is the behaviour we want, and it is also what the code does with
no extra work — but it must be stated, because it means the owner will **not** see this change
on a device that already has StoryArc on it. Frames come from a fresh install.

A reset writes `Defaults`, so a reset after this change moves a reader to the brand palette.
`DynamicColourSettingTest` already asserts that reset restores `Defaults`, which is why that
test is the one that has to change.

### The note stops naming a default

`appearance_dynamic_colour_note` currently reads "On by default. Turn it off for StoryArc's own
palette. Covers keep their neutral ground either way." The first sentence becomes false. The
replacement says what the switch does rather than what the default is, so the string does not
have to change again if the default ever moves back:

> "Turn it on to take the colours of your wallpaper. Covers keep their neutral ground either
> way."

Four locales, because `pnpm lint` checks that and because a half-translated note is worse than
an untranslated one.

### Why not remove dynamic colour entirely

It was asked for by `native-experience`, it is an Android platform affordance, and some readers
run their whole phone on it. The owner asked for the brand colour by default, not for the
feature to go. Removing it would also delete the OLED Dark and Natural interaction notes, which
are two real decisions recorded in `Theme.kt`.

## Risks / Trade-offs

**An Android reader loses the system-wide look they expect.** Material You is the platform
convention and a reader who likes it now has to find a switch. Mitigated by leaving the switch
where it is, in Appearance, one tap from the top of Settings.

**The two active changes touch one requirement.** `publication-detail` also carries a MODIFIED
delta for `native-experience`'s *Dynamic colour*, and it is at 12 of 16 tasks. This change's
delta is written on top of that one: it keeps `publication-detail`'s added chrome-versus-artwork
clause word for word and changes only the default. Whichever archives second must still read
the other's delta before it syncs. If `publication-detail` changes that requirement again
before either archives, this delta has to be re-read against it.

## Migration Plan

None for data. The stored settings record is unchanged in shape and in meaning; only the value
a fresh record starts with moves.

## Open Questions

None. The owner asked for the default to be the brand palette, and the switch stays.
