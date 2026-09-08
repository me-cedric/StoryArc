# The skip interval stops being a setting — Android, 2026-09-08

Visual proof for §14 of
[`../../../openspec/changes/audiobooks-and-playback/tasks.md`](../../../openspec/changes/audiobooks-and-playback/tasks.md).
The owner asked for the default buttons only. The picker is gone.

| Frame | Shows |
| --- | --- |
| `android-player-skip-buttons.png` | The player after the picker was removed. Two skip controls, `15 s` and `30 s` written under the glyphs. The speed slider follows the transport directly, where the two picker rows used to sit. |

## What the device measured

The six-part fixture at `/sdcard/Music/StoryArcTest/` plays six seconds per part. Whole-book
time is `part index x 6000 + offset`. Every reading below comes from
`adb shell dumpsys media_session` while paused.

| Step | Part index | Offset | Whole-book time | Moved by |
| --- | --- | --- | --- | --- |
| Paused in part one | 0 | 1716 ms | 1716 ms | — |
| Skip forward | 5 | 1716 ms | 31 716 ms | +30 000 ms |
| Skip back | 2 | 4716 ms | 16 716 ms | -15 000 ms |
| Skip back | 0 | 1716 ms | 1716 ms | -15 000 ms |

Each skip crossed a file boundary and continued into the neighbouring part. The session also
carries the two names a car and the shade draw: `Back 15 seconds` and `Forward 30 seconds`.
