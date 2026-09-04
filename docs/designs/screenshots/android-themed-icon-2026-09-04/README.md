# The five faces, tinted flat — 2026-09-04

`brand-identity-and-app-icons` §6.3, the Android themed-icon capture. The task was `[~]` — a
named gap, because a previous pass could not turn themed icons on from a shell. **It can be
done**, and the two frames here are the proof.

A themed icon replaces the adaptive icon's own background and foreground with the wallpaper's
tonal palette applied to the `<monochrome>` layer. The reason StoryArc ships real
single-colour art for that layer rather than letting the system flatten the gradient mark is
that a gradient tinted flat loses the mark's internal divisions. These frames are the check on
that claim.

| Frame | Condition |
| --- | --- |
| `android-home-five-faces-own-colours.png` | Themed icons **off** — each face in its own plate |
| `android-home-five-faces-themed.png` | Themed icons **on** — the same five, tinted flat |

Both are `storyarc-j6` (1080 × 2400, 420 dpi, `-gpu host`, Android 16 / API 36), Pixel
launcher, the stock wallpaper the AVD boots with — which is why the tint is navy on pale blue.
The five icons are on the home screen in alias order, left to right then wrapping: **Ink,
Paper, Bloom, Arc, Mono**. Gmail, Photos, YouTube and the hotseat are in both frames as the
control: they change with the same switch, so the frames cannot both be the same state.

## What the frames say

**The divisions survive.** In the themed frame the mark keeps every internal cut — the two
leaf halves of the S, the notch at the lower left, the negative-space gap through the middle.
That is the point of `ic_launcher_monochrome.xml` being its own drawing rather than the
gradient foreground reused: the divisions are carried as holes in the shape, and a hole
survives being filled with one colour. Compare the Ink and Arc faces in the unthemed frame,
where the same divisions are carried partly by the gradient itself.

**Themed mode collapses the five faces into one.** All five themed icons are identical, and
by construction rather than by accident: every one of the five adaptive icons declares the
same layer.

```
$ grep -H monochrome apps/android/app/src/main/res/mipmap-anydpi-v26/*.xml
ic_launcher.xml:        <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
ic_launcher_arc.xml:    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
ic_launcher_bloom.xml:  <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
ic_launcher_mono.xml:   <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
ic_launcher_paper.xml:  <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
```

So a reader who picks *Arc* and turns on **Themed icons** in the system wallpaper settings gets
the same icon as a reader who picked *Paper*. The chooser in Settings still says which face is
selected, and on the home screen it makes no difference. Whether that is a defect or the
correct reading of the platform is a design question, not a bug report: the faces differ in
their plate colour, and a themed icon has no plate to colour. Recorded here so the decision is
made rather than discovered.

**The app drawer is not themed.** Only the workspace and the hotseat are. Searching the drawer
for StoryArc shows the full-colour mark whatever the switch says, so a drawer screenshot is not
evidence either way.

## How themed icons were turned on

Four things were tried, in the order the brief named. What each returned:

1. **`adb shell cmd uimode`** — no. The service offers `night`, `car` and `time` and nothing
   else; there is no themed-icon verb.
2. **`adb shell settings get secure theme_customization_overlay_packages`** — already
   `{android.theme.customization.themed_icon:1}` on arrival. The setting is necessary and was
   not sufficient on its own.
3. **The launcher's `themed_icons` key** — already `true` in
   `/data/data/com.google.android.apps.nexuslauncher/shared_prefs/com.android.launcher3.prefs.xml`,
   left there by the previous pass. **This is where that pass stopped**, having written the key,
   read it back `true`, and seen no change.

   The missing step is that **the launcher caches its icons and does not re-read either flag
   until it restarts**. `adb shell am force-stop com.google.android.apps.nexuslauncher`,
   then `KEYCODE_HOME`, and the themed icons are there. Nothing else was needed.
4. **A wallpaper set through `am start`** — not needed, so not tried. The stock wallpaper
   already supplies a tonal palette.

Placing five icons on one home screen needed the launcher's own database, because
`input draganddrop` does not hold long enough to trip the launcher's pick-up threshold — it
ran and left the home screen unchanged. Rows go into `favorites` in
`databases/launcher_4_by_5.db` (the grid named by `idp_grid_name`), and the five
`<activity-alias>` components have to be enabled together first, since the chooser normally
leaves exactly one enabled:

```sh
pm enable app.storyarc.debug/app.storyarc.MainActivityArc     # ×5
sqlite3 …/launcher_4_by_5.db "insert into favorites \
  (title,intent,container,screen,cellX,cellY,spanX,spanY,itemType,profileId,rank) \
  values ('Arc','#Intent;…component=app.storyarc.debug/app.storyarc.MainActivityArc;end', \
          -100,0,3,2,1,1,0,0,0);"
am force-stop com.google.android.apps.nexuslauncher
```

All of it needs `su 0`, which the emulator grants and a physical device will not.

**The device was put back**: the five rows deleted, the four extra aliases disabled and Ink
re-enabled, `themed_icons` returned to `true` and the secure setting to the exact string it
arrived with. `MainActivity` resumes normally afterwards, which is the check the alias work of
2026-09-04 asks for.
