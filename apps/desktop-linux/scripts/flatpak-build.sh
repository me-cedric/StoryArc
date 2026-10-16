#!/usr/bin/env bash
# Builds the Flatpak in a container, the way the Linux README's Flathub gate describes and
# the way CI can later. Usage: flatpak-build.sh
#
# flatpak-builder sandboxes each module with bubblewrap, which needs user namespaces and mount
# rights the default Docker seccomp and capability set deny, so the container runs
# --privileged: the same option the flathub-infra action images document for GitHub Actions.
# rofiles-fuse is disabled because the container has no FUSE device.
#
# The image carries the GNOME 51 runtime and SDK in its system installation and runs as root,
# so the build uses that installation rather than --user: a named volume over /var/lib/flatpak
# keeps the image's runtimes and takes the Rust extension on the first run (about 500 MB).
# On a desktop, outside a container, the README's --user form is the one to run.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
manifest="apps/desktop-linux/build-aux/com.mecedric.StoryArc.json"
# The image that carries flatpak-builder and the GNOME 51 runtime. Multi-arch: amd64 and arm64.
image="ghcr.io/flathub-infra/flatpak-github-actions:gnome-51"

# One volume holds both the build directory and the .flatpak-builder state: flatpak-builder
# refuses a state dir on a different filesystem from the build dir, which a second volume is.
docker run --rm --privileged \
  -v "$root":/src:ro \
  -v storyarc-flatpak-system:/var/lib/flatpak \
  -v storyarc-flatpak-work:/work \
  -w /work \
  "$image" bash -c "set -e
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak-builder --install --force-clean --disable-rofiles-fuse \
      --install-deps-from=flathub \
      build-flatpak /src/$manifest
    flatpak info com.mecedric.StoryArc"
