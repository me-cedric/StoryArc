# build-aux

The Flatpak manifest for StoryArc on Linux and the file that lets it build offline.

| File | What it is |
| --- | --- |
| `com.mecedric.StoryArc.json` | The repository's own manifest. GNOME 51 runtime, the Rust SDK extension, a `pdfium` module and the `storyarc` module. |
| `cargo-sources.json` | Every crate of `Cargo.lock` as a flatpak-builder source, plus the cargo config that points at the vendored copies. Generated, never edited by hand. |

## The policy

This manifest may be machine-written. The copy that goes to Flathub may not be:
Flathub forbids AI-generated or AI-assisted content in the manifest it accepts, and
a human submits it after the owner's written question to Flathub is answered
(ADR-0018 D4, `tasks.md` 1.25). No Flathub submission work happens in this repository.

## Regenerating `cargo-sources.json`

Run `apps/desktop-linux/scripts/flatpak-cargo-sources.sh` after any change to
`Cargo.lock`. It fetches `flatpak-cargo-generator.py` from
[flatpak/flatpak-builder-tools](https://github.com/flatpak/flatpak-builder-tools)
at commit `74697c75b630d7330e77250fc13cb5ea688d9479` (2026-09-30), checks the script
against a pinned sha256, and runs it in a throwaway `python:3.12-slim` container.
The generator is MIT licensed (`__license__` in the script and `cargo/pyproject.toml`
in that repository); it is fetched rather than vendored so the pin stays one line.

The output was last generated from the `Cargo.lock` at commit `9ca4b487`: 83 crates,
all from crates.io, and one inline `cargo/config`.

## What the manifest bundles, and what it does not

- **PDFium**: one release asset per architecture from `bblanchon/pdfium-binaries`,
  tag and sha256 copied from `apps/desktop-core/pdfium/pin.json`. `only-arches` picks
  the x86_64 or the aarch64 tarball. It lands at `/app/lib/libpdfium.so` with its
  licence. Bump it only with `pin.json`.
- **libarchive**: no module. `storyarc-core` compiles the vendored
  `third_party/libarchive` sources with the `cc` crate, and the `dir` source carries
  them. A system or module libarchive is never linked.
- **WebKitGTK**: in the GNOME 51 runtime, nothing to bundle.
- The finish arguments are the five the base needs. `--socket=pulseaudio` joins when
  the audio wave lands.

## Trying the build

`apps/desktop-linux/scripts/flatpak-build.sh` runs

```sh
flatpak-builder --user --install --force-clean --disable-rofiles-fuse \
  --install-deps-from=flathub build-flatpak apps/desktop-linux/build-aux/com.mecedric.StoryArc.json
```

inside `ghcr.io/flathub-infra/flatpak-github-actions:gnome-51`, the image the Flathub
infra publishes for GitHub Actions. The container runs `--privileged` because
flatpak-builder sandboxes each module with bubblewrap, which needs user namespaces and
mount rights Docker's defaults deny; the same option is what those action images
document. `--disable-rofiles-fuse` because the container has no FUSE device. The
runtime, SDK and Rust extension install into a named volume on the first run and stay.

A CI job can run the same command in that image with `options: --privileged`; the
ubuntu-24.04 runner has no flatpak-builder package of its own.
