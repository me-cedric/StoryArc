# A third of the screen turns the page — 2026-09-10

The tap zones and the setting that turns them off, on a OnePlus 7T Pro
(`f7cee850`) and an iPhone 17 Pro simulator. Change:
`a-third-of-the-screen-turns-the-page`, tasks 3.1 to 3.3.

## The setting

| Frame | Platform | Theme |
| --- | --- | --- |
| `android-reading-setting-light.png` | Android | light |
| `android-reading-setting-dark.png` | Android | dark |
| `ios-reading-setting-light.png` | iOS | light |
| `ios-reading-setting-dark.png` | iOS | dark |

*Tapping the page turns it*, on by default, beside the volume row, with the
note that says what the thirds are.

## The zones on, which is the control

- `android-zones-on-before.png` → `android-zones-on-right-turned.png`: a tap
  in the trailing third turned the page.
- `android-zones-on-centre-chrome.png`: a tap in the middle third brought the
  controls back, on the same page.
- `ios-zones-on-before.png` → `ios-zones-on-right-turned.png`: the same, on
  the simulator.

## The zones off

- `android-zones-off-before.png`, then a tap in each third:
  `android-zones-off-left.png`, `-right.png`, `-centre.png`. The page is the
  same in all four; the controls come and go. That is what `page-transitions`
  asks for — "a tap anywhere toggles the chrome, and no tap turns a page".
- `ios-zones-off-before.png` → `ios-zones-off-right.png`: the page is
  unchanged.

## What the iOS frames found

**The setting did nothing on iOS, and every suite was green.** With the zones
off, a tap in the trailing third still turned the page. The reader read
`@Environment(\.turnPagesByTappingTheEdges)` inside the closure a
`UITapGestureRecognizer` calls, and a `@Environment` property read outside a
body pass returns its *default* — `true`. Every unit test passed because a
unit test calls the rule, not the closure.

`tapHandler` now reads the flag during the body pass and captures the `Bool`;
`handleTap` takes it as a parameter. `TapZoneWiringTests` is the tripwire for
the next edit that moves the read back inside a closure.

## Not shown

The iOS controls do not appear in any frame taken after a tap. They toggle —
the page does not turn, which is the assertion — but they fade out faster than
a `simctl` screenshot arrives. Android's `android-zones-on-centre-chrome.png`
is the frame that shows the controls.
