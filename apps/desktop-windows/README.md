# StoryArc for Windows — planned, not implemented

**Status:** documented only. No code. The framework choice is **Assumed**,
pending a spike. See [ADR-0004](../../docs/decisions/0004-desktop-strategy.md).

## Leading candidate: WinUI 3 (Windows App SDK)

WinUI 3 is Microsoft's own framework for native Windows desktop apps. It gives
the current Fluent controls and modern windowing directly rather than through an
abstraction. For an app whose premise is looking stock on each platform, using
the platform vendor's own toolkit is the consistent choice.

**Cost:** a net-new implementation, in C#, of the connector layer, the format
layer, the download queue and the progress store. That is the real price of
Windows, and it is why Windows waits.

## Runner-up: Avalonia

Avalonia draws every pixel itself through Skia rather than delegating to native
widgets. That is the right trade for an app that wants one identical look
everywhere — and the wrong trade for StoryArc, which wants to look different on
each platform on purpose.

It stays on the table for one reason: **it would cover Linux from the same
codebase.** If the spike picks Avalonia, the Linux question closes for free.

## Rejected

| Option | Why |
| --- | --- |
| .NET MAUI | On Windows it renders through WinUI 3 anyway — an extra layer, no extra capability |
| Electron / Tauri + web UI | Fails the native-feel requirement, and a web reader cannot do a 120 Hz finger-tracked page curl convincingly |
| WPF | Maintenance mode for new Fluent work |

## The spike must answer

1. **Does the page curl hold 120 Hz?** It is the reader's signature interaction,
   and a bad one is worse than none. This is the question that decides the
   framework.
2. What reads CBZ, CBR, CB7, CBT, EPUB and PDF on .NET, and under what licences?
   See [ADR-0005](../../docs/decisions/0005-format-and-rendering-libraries.md)
   for the RAR licensing problem, which is not platform-specific.
3. SMB: does the app need a client library at all, or is a mapped network drive
   enough on Windows?
4. Packaging: MSIX and the Microsoft Store, or a plain installer?

## Do not start this

Until both mobile apps have shipped a 1.0.
