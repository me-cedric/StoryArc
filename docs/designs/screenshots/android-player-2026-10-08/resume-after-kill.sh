#!/bin/bash
# 3.6: play Sea Room, pause at 2000 ms, kill the process, press play from outside, photograph the shade.
A=~/Library/Android/sdk/platform-tools/adb; P=com.mecedric.storyarc.debug; OUT=$1
cd /Users/mecedric/Documents/Projects/StoryArc/.claude/worktrees/waves-branches-worktrees-5df2cb
$A shell am force-stop $P
pnpm -s capture:android "Player > Sea Room paused" --out /tmp/_discard.png >/dev/null 2>&1
$A shell input swipe 540 1900 540 700 300; sleep 1; $A shell input tap 400 1772; sleep 1
$A shell cmd media_session dispatch pause; sleep 1
echo "before kill:"; $A shell dumpsys media_session | grep -A12 "$P/" | grep -E "state=PlaybackState" | cut -c1-110
$A shell run-as $P cat shared_prefs/app.storyarc.playback.memory.xml | grep -E 'name="(position|index|title)"'
$A shell am force-stop $P; sleep 1
echo "after kill, pid=[$($A shell pidof $P)] sessions=$($A shell dumpsys media_session | grep -c "package=$P")"
$A shell cmd media_session dispatch play; sleep 1.2; $A shell cmd statusbar expand-notifications; sleep 1.2
$A exec-out screencap -p > "$OUT"
echo "after play, pid=[$($A shell pidof $P)]:"; $A shell dumpsys media_session | grep -A14 "package=$P" | grep -E "state=PlaybackState" | cut -c1-120
