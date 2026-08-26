# StoryArc for Linux — planned, not implemented

**Status:** documented only. No code, and the framework question is **open** —
deliberately, because it depends on the Windows outcome. The open questions
have now been researched on paper (August 2026); the findings below change the
weights without closing the question. See
[ADR-0004](../../docs/decisions/0004-desktop-strategy.md).

Confidence labels follow
[ADR-0005](../../docs/decisions/0005-format-and-rendering-libraries.md):
**Known** is verified against the vendor's own documentation or source,
**Reported** is a credible secondary source, and nothing below is **Proven**
until a spike runs it on real hardware.

## What research changed

Two findings move the needle, in opposite directions:

- **GTK4 lost its scene-graph shader API — and the curl survives anyway.**
  `GskGLShader` was deprecated in GTK 4.16 and its only host renderer was
  removed in 4.18, with no replacement through 4.20 (**Known**). The supported
  path for [ADR-0009](../../docs/decisions/0009-page-curl-as-a-fragment-shader.md)'s
  two-texture fragment shader is an app-owned GL context — `GtkGLArea`, or an
  FBO wrapped via `GdkGLTextureBuilder` with dmabuf interop under the default
  Vulkan renderer (**Known**). A GTK developer confirms above-60 FPS is a
  Wayland matter, with 120 FPS measured on GTK4/Wayland while X11 sessions sat
  near 60 (**Known**). So the ADR-0009 escape hatch gets its second consumer:
  **curl present on Wayland, absent on X11** — absent, never degraded.
- **Avalonia's "Linux for nearly free" is weaker today than ADR-0004 assumed.**
  Its native Wayland backend shipped only in 12.1 (July 2026), explicitly
  experimental and opt-in; until it matures, an Avalonia StoryArc runs through
  XWayland — blurry fractional scaling and weaker frame pacing exactly where
  the curl needs 120 Hz (**Known**). Meanwhile GNOME 50 enabled fractional
  scaling and VRR by default and X11 sessions are being retired (**Reported**):
  Wayland-first is settled, and today that favours GTK4.

## Answer one: GTK4 + libadwaita, in Rust

What actually looks native on GNOME, and better precedented than expected:
Papers (GNOME's document viewer since 49) is a Rust/GTK4 rewrite, Komikku is a
libadwaita manga reader, Foliate a WebKitGTK ebook reader (**Reported**) — the
HIG accommodates an artwork-first, chrome-recedes reader without friction.
`gtk4-rs` is actively maintained (**Known**). The cost is unchanged: a third
implementation in a third language — a **fourth mirror** of the
[ADR-0008](../../docs/decisions/0008-ranged-reads-and-own-zip-reader.md)
format layer if Windows went WinUI 3.

### The format layer in Rust

| Need | Answer | Licence | Confidence |
| --- | --- | --- | --- |
| ZIP (CBZ, EPUB container) | **Our own reader**, mirrored: ranged reads are idiomatic Rust, and `rc-zip` proves the sans-IO random-access shape | — | **Known** |
| TAR (CBT) | **Our own `TarReader`**, mirrored | — | **Known** |
| RAR (CBR) | **libarchive** — every distro ships it, or vendor as on mobile — via direct FFI with read/seek callbacks bridging `RandomAccessSource` (`compress-tools` exposes streams only) | BSD-2-Clause | **Known** — same library, same reasoning as mobile |
| 7-Zip (CB7) | — | — | **Not supported**, per ADR-0005 |
| EPUB | **WebKitGTK** (`webkitgtk-6.0`, actively maintained with prompt CVE handling) hosting **foliate-js** (MIT, CFI locators) or **Readium Web** (BSD-3) — inside the one sanctioned web-view exception | LGPL runtime; MIT / BSD-3 renderer | **Known** — Foliate is the working precedent; foliate-js declares its API unstable, so the commit gets pinned |
| PDF | **pdfium** via the `pdfium-render` crate (active through 2026); bundled, since distros do not package pdfium | BSD-3 + MIT/Apache binding | **Known** |
| Image decoding | glycin / gdk-pixbuf cover the basics; AVIF/JXL need bundled decoders (libavif BSD-2, libjxl BSD-3); HEIC drags in libheif (LGPL) **and** patent-encumbered HEVC — may be refused by name like CB7 | mixed, listed | **Inferred** — per-codec matrix is spike work |
| SMB | **Bundle our own client** — libsmb2 (LGPL-2.1, dynamically linked) or the young pure-Rust `smb` crate — behind `--share=network`; see below | LGPL-2.1 / MIT | **Known/Inferred** |

**Licence traps found in advance, all avoidable** (**Known**): poppler is GPL
with no linking exception — the shipped binary would be GPL-governed, which is
why pdfium wins; MuPDF is AGPL/commercial and excluded; the `unrar` crate
wraps rarlab's non-OSI UnRAR library and `unrar-rs` is UnRAR-derived *and*
GPL — both disqualified by the criterion that picked libarchive on mobile;
`pavao` links Samba's GPLv3 libsmbclient in-process — excluded. gvfs itself is
GPL-safe to *talk to* (out-of-process over D-Bus), but see the SMB note.

### SMB — bundle the client, as mobile does

GIO over `smb://` gives genuine ranged reads — the gvfs SMB backend implements
seek-on-read via `smbc_lseek`, verified in its source (**Known**) — but gvfs
has documented throughput problems, exists mainly on GNOME hosts, and inside
Flatpak needs its own sandbox holes (**Known**). Since the spec obligations in
[`network-share`](../../docs/openspec/specs/network-share/spec.md) (state
encryption, refuse SMB 1 with a named remedy, protocol-specific failures)
presuppose in-app protocol visibility anyway, the clean answer mirrors mobile:
our own SMB client, ranged reads, `--share=network`, credentials in the secure
store. gvfs stays a possible discovery/browse convenience, never the data
path.

### Secrets

The `oo7` crate (MIT, maintained) speaks the Secret Service on the host and,
inside Flatpak, an encrypted file backend keyed through the Secret portal —
app-private, arguably a better posture than the host keyring, with migration
helpers between the two (**Known**). Some hosts run no keyring at all; the
defined fallback behaviour is spike work, and
[`sources`](../../docs/openspec/specs/sources/spec.md) already obliges a
graceful answer.

## Distribution: Flatpak first, eyes open

Flathub is the channel — default store on Fedora, Mint, elementary and the
Steam Deck (**Reported**). Four findings shape the plan:

1. **Folder grants persist.** A FileChooser-portal directory grant survives
   restarts and reboots by design (Documents portal `persistent` flag,
   directory export since interface v4), and the granted tree is a normal
   POSIX view — recursive enumeration and `pread` ranged reads work through
   the FUSE doc mount (**Known**). Persistence flakiness exists on some KDE
   backend combinations (**Known**), so the re-pick recovery path
   [`local-library`](../../docs/openspec/specs/local-library/spec.md) already
   specifies is load-bearing, not theoretical.
2. **File watching through the portal is broken.** No inotify events cross the
   doc-mount FUSE boundary; the upstream issue has been open since 2021
   (**Known**). "Watched folder" therefore means polled reconciliation by
   mtime and size inside the sandbox — which the spec's
   return-to-foreground reconciliation wording already permits.
3. **FUSE overhead is unquantified on exactly our workload.** Anecdotes (8×
   slower scans, unbounded portal memory on recursive search) exist; a
   10,000-item library benchmark does not (**Reported**). The honest
   precedent: YACReader ships on Flathub with `--filesystem=home` plus media
   mounts; Foliate and Komikku are portal-pure but are not library-scanning
   apps (**Known**). Portal-first, static-grant-if-measured is the plan, and
   the spike decides.
4. **Flathub policy risk, non-technical and potentially decisive.** Flathub's
   generative-AI policy was reportedly tightened in May 2026 to exclude
   AI-assisted apps and AI-authored submissions, with exceptions for mature,
   well-maintained projects (**Reported — verify with Flathub directly**).
   This repository develops with AI assistance in the open, so whether
   StoryArc qualifies must be settled with Flathub **before** any packaging
   work is scheduled. If Flathub is closed, the fallback order is AppImage
   (no sandbox, everything just works, no discovery) plus community
   AUR/distro packaging — workable, materially worse reach.

Secondary channels: AppImage as a cheap CI artifact and portal-debugging
control; no self-maintained deb/rpm; Snap only if Ubuntu demand materialises
(**Inferred**).

### Spec reinterpretations this target owes

To be proposed as spec deltas when the target starts (`/opsx:propose`):

| Spec wording | Linux reading |
| --- | --- |
| Finger-tracked curl, pinch, tap zones | Pointer drag; Ctrl+scroll / touchpad pinch; click zones — keyboard already mandated |
| Screen does not auto-lock while reading | The idle-inhibit portal |
| Backgrounded / killed by the system | Window close, focus loss, quit, crash — the 15 s progress-write cadence stays |
| Secrets in the platform secure store | Secret Service / Secret portal via `oo7`; a defined fallback where no keyring runs |
| Share sheet for diagnostic export | Save-to-file + open containing folder; redaction rules stand |
| Metered / data saver | NetworkManager metered hints — weaker than mobile, degrade honestly |
| Excluded from device backups | No mechanism — a documented-location decision |
| Media controls for read-aloud | MPRIS; speech via speech-dispatcher, where the SHOULD gets genuinely harder |
| File handling | `.desktop` MIME entries — `application/vnd.comicbook+zip` and friends are already in shared-mime-info (**Reported**) |
| Screen readers | Orca over AT-SPI2 — which GTK4 supports natively, and Avalonia 12 now also ships (**Known**) |

Plus the shared inherited cost: a `StoryArcTokens.rs` (or `.cs`) emitter in
`packages/design-tokens`, per
[ADR-0007](../../docs/decisions/0007-design-token-pipeline.md).

## Answer two: Avalonia, shared with Windows

The economics are unchanged and real: one C# implementation for both desktops,
one new format-layer mirror instead of two, and the curl is expressible — SKSL
`SKRuntimeEffect` with two image children on the render thread is an
officially documented pattern, and the 60 FPS cap was lifted for X11 in 12.1
(**Known**). The project is healthier than assumed: MIT, sponsored, annual
cadence, and its WebView was open-sourced in 12.0.

What research subtracts (**Known** unless noted): native Wayland is
experimental opt-in — today means XWayland, with blurry fractional scaling on
the compositors users actually run; the embedded WebView needs the WPE runtime
and otherwise falls back to a *separate window*, which is unacceptable for an
embedded EPUB reader on older distros; no custom-scheme/request-interception
API is documented for serving EPUB resources from an archive (**unknown**,
load-bearing); and fractional scaling, IME and touchpad gestures on the
Wayland backend are undocumented either way.

**The decision remains downstream of Windows, with the weights updated:**

- Windows spike picks **Avalonia** → Linux still follows nearly for free, but
  only after the Avalonia-on-Wayland spike passes; otherwise "free" ships a
  worse Linux app than no Linux app.
- Windows spike picks **WinUI 3** → GTK4 + libadwaita is the honest answer to
  "should it look native", now with its shader path, format layer, and
  licences mapped above.

## The third answer, still open on purpose

Is a desktop app the right shape for Linux users at all — most of whom already
run the *server* side — or would a self-hosted web reader against the same
sources serve them better for a fraction of the work? Nothing in this round of
research closes that question, and it may still be the answer. It is also the
only answer that sidesteps the Flathub policy risk entirely.

## The spike, when its day comes

1. **Curl on GTK4** — `GtkGLArea`, ADR-0009's projection in GLSL over two
   textures, pointer-driven via tick callback. *Exit:* sustained 120 FPS on a
   120 Hz Wayland monitor on Mesa **and** NVIDIA, under both `vulkan` and
   `ngl` renderers; the X11 cap measured and the absent-on-X11 policy written
   down.
2. **Portal reality** — persistence across restart and host reboot on GNOME
   and KDE backends; the FUSE overhead measured on 5,000 small files plus a
   2 GB CBZ read by ranges, versus a static grant, versus unsandboxed. *Exit:*
   a manifest decision — portal-only or YACReader-style grants — from numbers,
   not anecdotes.
3. **Watching** — confirm inotify silence through the doc mount; cost a polled
   mtime sweep at library scale. *Exit:* a chosen reconciliation strategy per
   permission model.
4. **SMB in sandbox** — bundled client, `--share=network`, ranged reads from a
   real NAS, credentials through the Secret portal. *Exit:* page-open latency
   budget met; encryption status surfaced as `network-share` requires.
5. **Format layer** — libarchive FFI over `RandomAccessSource`; own ZIP reader
   against the shared corpus in `packages/test-fixtures`. *Exit:*
   byte-identical pages versus both mobile implementations.
6. **EPUB** — foliate-js (pinned) in `webkitgtk-6.0`, script-message bridge,
   CFI round-trip into the content-addressed progress store. *Exit:*
   reflowable pagination and a locator strategy reconciled with the Readium
   locators the other platforms produce.
7. **Flathub gate, non-code and first** — verify the generative-AI policy text
   and ask Flathub directly whether StoryArc qualifies for the exception.
   *Exit:* a written answer, before any packaging work is scheduled.
8. **If Avalonia is in play** — the same curl and EPUB spikes on Avalonia 12.1
   under X11 and experimental Wayland, plus the WebView archive-serving
   question. *Exit:* same bars as GTK4; misses disqualify.

## Open questions research could not close

1. Whether GTK ever restores scene-graph custom shaders — no roadmap signal;
   `GtkGLArea` may be the permanent answer (**unknown**).
2. GTK4 pointer-event pacing versus the mobile input paths — measurable only.
3. The Flathub AI-policy exception in practice — no published criteria.
4. HEIC on Linux: bundled libheif (LGPL) plus HEVC patent exposure, or refused
   by name — a product decision awaiting the codec-matrix spike.
5. Whether the pure-Rust `smb` crate matures before this target starts —
   libsmb2 is the safe pick today.

## Do not start this

Until both mobile apps have shipped a 1.0, and until Windows has chosen. The
research above makes the eventual spike cheaper; it does not make it due
sooner.
