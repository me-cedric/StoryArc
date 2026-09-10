**What a tick means.** The code exists and something asserts it. For the shader
that means a pixel assertion at a stated progress, not a screenshot alone; for
the gesture, a unit test over `CurlTurn`. A tick does not mean the turn feels
right — that is what the device captures in section 5 are for, and they name the
device and the refresh rate they were taken at.

## 1. The turn has a sign

- [x] 1.1 Extend `CurlTurnTest` (`apps/android/feature/reader/src/test/.../CurlTurnTest.kt`) and its Swift twin: a backwards drag from flat gives a negative progress, the range clamps at `-1f` and `+1f`, a right-to-left publication mirrors both signs, and a backwards flick completes a backwards turn. Red before 1.2.
- [x] 1.2 Make `CurlTurn.progress` signed and clamp to `-1f..1f` (`CurledPages.kt:213`), and mirror the change in `CurledPages.swift`. Verify 1.1 passes on both.
- [x] 1.3 Assert that with no previous page the negative range collapses to zero, so the first page cannot turn backwards, and with no page beneath the positive range already does — one test naming both ends. Verify: the *Turning back from the first page* scenario has a test that fails if either guard is removed.

## 2. The previous page reaches the shader

- [x] 2.1 Write the test that `CurledPages` binds `previous` as the turning sheet and `current` as the page beneath when progress is negative, and the reverse when positive. Red before 2.2.
- [x] 2.2 Add `previous: Bitmap?` and `onTurnedBack: () -> Unit` to `CurledPages` (`CurledPages.kt:43`) and the Swift counterpart, and pass `modelIndex(paging.current - 1)` with `turn(paging.current - 1)` from `ReaderScreen.kt:873`. Verify 2.1 passes and the forward path's existing tests are untouched.
- [x] 2.3 `CurlSheetWiringTest` names the three cache reads, and one case more than was asked for: `modelIndex` answers 0 for a display position with no slot, so a bare `current - 1` handed the first page itself as its own previous. Guarded on both platforms.

## 3. The sheet rolls

- [x] 3.1 Write the pixel test for the roll, one per platform, sampling the same points at progress 0.25, 0.5 and 0.75: a point inside the curved band is neither the flat face nor the flat back; the silhouette across the band is not a vertical line; the shadow's leading edge is not a vertical line. Red before 3.3.
- [x] 3.2 Write the counterpart test that fails when the two shaders disagree: the same sample points at the same progress must match between AGSL and MSL within a stated tolerance. Red before 3.3.
- [x] 3.3 Add `R_MAX` beside `CREASE`, `SHADOW` and `BACK` in both files, and implement the bend: remap the texture coordinate across `[f - πr/2, f]` by arc position, ramp the back-face dimming with the surface normal, and follow the curve with the cast shadow. `r = R_MAX * sin(π * progress)`. Verify 3.1 and 3.2 pass on both platforms.
- [x] 3.4 Keep the wrong-side case as a test: assert the page beneath is *not* drawn at rest, which is how ADR-0009 records the first attempt announcing itself.

## 4. It still holds the refresh rate

- [x] 4.1 Record a baseline with `FrameProbe`/`FrameTicker` before section 3 lands: frames and dropped frames for ten forward turns on the OnePlus 7T Pro (`f7cee850`, 90 Hz) and on the slowest simulator device the project supports. Commit the numbers.
- [x] 4.2 Re-record the same ten turns after the roll, plus ten backwards turns, on the same devices. Verify: no more dropped frames than the baseline. If there are, reduce `R_MAX` and re-record; if it still drops, stop and report rather than shipping a curl that stutters.

## 5. Seen on a device

- [x] 5.1 Capture a forward turn mid-gesture at progress ≈ 0.5 on the phone, light and dark, default and largest text size. Control: the same page at the same progress with the fold, captured before section 3, same device and appearance.
- [x] 5.2 Capture a backwards turn mid-gesture, both appearances. Control: the same drag today, which moves nothing — the control is the point.
- [ ] 5.3 **Not captured.** A mid-gesture frame needs the finger held still, and the simulator's injected touches complete the drag before a `simctl` screenshot lands — three attempts produced the page before the turn and the page after it. `PageCurlShaderTests` asserts the Metal is the same code as the AGSL, and `PageRollTests` asserts the same arithmetic; the screenshot README says plainly what has not been seen.
- [x] 5.4 Write the screenshot README naming the device, the refresh rate, the progress each frame was taken at, and what each control proves.

## 6. The record

- [x] 6.1 Mark the *"It is a fold, and the crease draws nothing"* section of `docs/decisions/0009-page-curl-as-a-fragment-shader.md` superseded, pointing at this change, with one sentence saying the argument holds for a crease of no radius and not for a bend of finite radius. Do not delete the section. Verify: the ADR still states what was decided and why it changed.
- [x] 6.2 `pnpm test:android`, `pnpm test:ios`, `./gradlew lint` and `pnpm lint` green.
- [ ] 6.3 `pnpm spec:validate && pnpm spec:guard` green for this change.
