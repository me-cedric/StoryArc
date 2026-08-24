# StoryArc for macOS — planned, not implemented

**Status:** documented only. No code. See
[ADR-0004](../../docs/decisions/0004-desktop-strategy.md).

## Shape

Not a separate app. `apps/ios` becomes a multiplatform SwiftUI target: the same
`StoryArcKit` packages, with Mac-specific presentation on top.

This is the cheapest desktop target by a wide margin, because it reuses the iOS
domain, design system and feature modules wholesale.

## What macOS needs that iOS does not

| Area | Work |
| --- | --- |
| Navigation | `NavigationSplitView` with a persistent sidebar; no tab bar |
| Windows | Multiple windows, one reader per window, restored on relaunch |
| Menu bar | Real `File`, `Edit`, `View`, `Go`, `Window` menus with keyboard equivalents |
| Toolbar | Native toolbar with customisation, not an iOS bar in a window |
| Keyboard | Full keyboard navigation, arrow-key page turns, `⌘F` search |
| Pointer | Hover states, right-click context menus, scroll-wheel and trackpad zoom |
| Drag and drop | Drop a `.cbz` on the window or the Dock icon to read it |
| Files | Direct file-system access; no security-scoped bookmark dance for user-chosen folders |
| SMB | The system already mounts SMB volumes — the app can read them as paths |
| AppKit interop | `NSOutlineView`-class controls where SwiftUI has no desktop equivalent |

## What it inherits unchanged

`StoryArcCore`, `DesignSystem`, the format layer, the connector layer, and the
progress store. The specs in [`docs/openspec/specs`](../../docs/openspec/specs) are
already platform-neutral.

## Open questions

1. Is the page curl right on a desktop, or does a Mac reader want a different
   default transition?
2. Does the reader belong in its own window, or as a mode inside the library
   window?
3. Mac App Store, or direct distribution with notarisation only?

## Do not start this

Until both mobile apps have shipped a 1.0.
