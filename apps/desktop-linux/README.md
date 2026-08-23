# StoryArc for Linux — planned, not implemented

**Status:** documented only. No code, and the framework question is **open** —
deliberately, because it depends on the Windows outcome. See
[ADR-0004](../../docs/decisions/0004-desktop-strategy.md).

## Two coherent answers

### GTK4 + libadwaita

What actually looks native on GNOME, where most desktop Linux users are.
Adwaita styling, GNOME HIG behaviour, a proper `.desktop` entry, Flatpak
distribution.

**Cost:** a third implementation, in a third language (Rust with `gtk4-rs`, or
Vala). This is the expensive answer.

### Avalonia, shared with Windows

One implementation covering both desktops. It will not look like a GNOME app —
but Linux users tolerate a non-native toolkit far more readily than macOS or
Windows users would, and the ecosystem is used to it.

**Cost:** near zero if Windows already picked Avalonia. Prohibitive if it did
not.

## The decision is downstream of Windows

- Windows spike picks **Avalonia** → Linux follows for nearly free. Question
  closed.
- Windows spike picks **WinUI 3** → Linux becomes a separate decision on its own
  merits, and GTK4 is the honest answer to "should it look native".

## Open questions beyond the toolkit

1. Can a Linux build carry the same format support without re-solving EPUB and
   PDF rendering from scratch?
2. Flatpak only, or Flatpak plus distro packages? Flatpak sandboxing complicates
   arbitrary folder access, which is the primary source type.
3. Is a desktop app the right shape at all for Linux users, most of whom already
   run the *server* side — or would a self-hosted web reader against the same
   sources serve them better for a fraction of the work?

Question 3 is not rhetorical. It may be the answer.

## Do not start this

Until both mobile apps have shipped a 1.0, and until Windows has chosen.
