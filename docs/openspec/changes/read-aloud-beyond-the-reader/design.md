# Design — read-aloud beyond the reader

Small change, one hard part: **who owns the session**.

## The session has to change owner

Everything else follows from this, so it goes first.

| | Today | After |
| --- | --- | --- |
| iOS | The session belongs to the reader's model, and the reader is presented as a full-screen cover over the app. Dismissing the cover ends it. | The session belongs to something that outlives any screen, and the reader observes it rather than owning it. |
| Android | The session already belongs to a foreground service of type `mediaPlayback` holding a `MediaSession`, on its own notification channel, posting a media-style notification. | Unchanged. |

That asymmetry is the whole shape of the change: **Android's ownership is already
correct and only its in-app presentation is unspecified; iOS needs the ownership
moved.**

What iOS already has and keeps: `MPNowPlayingInfoCenter` and
`MPRemoteCommandCenter` are wired, and `AVAudioSession.interruptionNotification`
is already the interruption contract, with a recorded decision not to claim the
now-playing entry is a live stream. None of that moves. What moves is the object
that holds the synthesiser and the sentence cursor, and the point at which the
reached position is written to the progress store — today implicitly on the
reader going away, after this explicitly when the session ends.

**Assumed, and it is the one thing to prove before building:** that speech
started from a screen that is then dismissed keeps running for the whole time the
app is foregrounded, with the audio session category the app already uses and no
background mode beyond what read-aloud already declares. Nobody has run it. Task
0.1 answers it.

## The iOS transport

`tabViewBottomAccessory` on the shell's `TabView`, with placement read from
`tabViewBottomAccessoryPlacement` so the control renders above the tab bar at
full size and inline when the bar is minimised. The glass capsule comes with the
slot; nothing here draws its own material.

**Two constraints from this codebase, both already learned the hard way:**

1. **No glass inside the accessory.** `ReadAloudBar.swift` carries a comment
   recording that four glass buttons on a glass surface made three glyphs vanish
   — glass-on-glass observed on a device. The slot is already a glass surface, so
   its contents use plain controls. This is also the platform's own rule about
   nesting the material.
2. **The slot does not exist without the shell.** There is no `TabView` in the
   app today; it arrives with `one-library-three-destinations`. Until it does, the
   capability can be built and has nowhere to dock.

**Versions.** iOS floor is 26.0
([ADR-0003](../../../decisions/0003-platform-floors.md)) and both accessory APIs
are iOS 26. Android needs nothing new: the service, the session, the channel and
the notification are all in `feature/epubreader` already.

## Why Android adds no bar

Material has no persistent accessory slot above a navigation bar, and Android
already has a better answer to the same question — a media notification and
lock-screen controls that survive the app being backgrounded, which an in-app bar
cannot. Adding a bar would be inventing a control the platform does not have, in
order to make two screenshots match. Direction §4.9, divergence 2.

The Android work is therefore not "build a transport" but "make sure the existing
one is correct when the reader is gone rather than only when the app is
backgrounded", and that returning from the notification lands in the publication
at the spoken sentence rather than at the app's launch destination.

## Accessibility consequences

- **A transport that takes focus when it appears is a defect, not a courtesy.**
  Speech starting must not move a screen-reader user's focus out of what they are
  reading, so the delta forbids it and the tests check it.
- **Every action carries its own label.** Pause, resume, skip a sentence and end
  are four verbs; a transport whose control reads only as the publication's title
  gives a screen-reader user no way to know what tapping does.
- **What is playing must be in text.** A listener using a screen reader gets the
  publication and the chapter from the transport's label, not from a marquee or
  an animation.
- **The way back must be reachable by keyboard and switch**, because a session a
  person can start and cannot return to is worse than no session.
- **Voice Control and hardware media keys already work through the platform
  centres** on both sides; nothing in this change may bypass them by handling
  transport actions only inside the app's own control.
