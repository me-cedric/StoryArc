# Border trim on iOS, 2026-09-28

The iOS image adjustments sheet, light and dark, on an iPhone 17 Pro simulator (iOS 26.5), taken by `SweepComicReaderTests/testCaptureComicAdjustments` after `close-the-audited-gaps` wave 0.

Before this change, the sheet declared the per-page trim binding and drew no control for it, so no reader could turn border trimming on. The switch now sits in the second group of the sheet, below Greyscale and Invert colours. The frames show the sheet at its medium height, so that group starts at the bottom edge. Unit tests on both platforms prove the switch drives the trim: `AdjustmentsSheetTests` and `ImageAdjustmentsTests`.
