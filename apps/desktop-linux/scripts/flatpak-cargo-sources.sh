#!/usr/bin/env bash
# Regenerates apps/desktop-linux/build-aux/cargo-sources.json from Cargo.lock, so the Flatpak
# builds offline. Run it after any change to Cargo.lock.
#
# The generator is flatpak-cargo-generator.py from flatpak/flatpak-builder-tools (MIT). It is
# not vendored: this script fetches it at one pinned commit, checks its digest, and runs it in
# a throwaway Python container so nothing is installed on the host. Docker is the only
# requirement.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
out="$root/apps/desktop-linux/build-aux/cargo-sources.json"

# flatpak/flatpak-builder-tools, commit of 2026-09-30. Bump both lines together.
commit="74697c75b630d7330e77250fc13cb5ea688d9479"
digest="0a2db6be87d75910facef28ab46d4d6460802e8419ab850d0caa6a364d26b380"
url="https://raw.githubusercontent.com/flatpak/flatpak-builder-tools/$commit/cargo/flatpak-cargo-generator.py"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -sSfL "$url" -o "$work/flatpak-cargo-generator.py"
echo "$digest  $work/flatpak-cargo-generator.py" | shasum -a 256 --check --status \
  || { echo "flatpak-cargo-generator.py does not match the pinned digest; read the diff before bumping it" >&2; exit 1; }

# Dependencies are the script's own PEP 723 header. Crate digests come from Cargo.lock, so
# the only network traffic is pip, and git dependencies if the lock file ever has any.
docker run --rm \
  -v "$root/Cargo.lock":/in/Cargo.lock:ro \
  -v "$work":/tool:ro \
  -v "$(dirname "$out")":/out \
  python:3.12-slim bash -c '
    set -e
    pip install -q "aiohttp<4.0.0,>=3.9.5" "tomlkit>=0.13.3,<1.0" >/dev/null
    python3 -I /tool/flatpak-cargo-generator.py /in/Cargo.lock -o /out/cargo-sources.json'

echo "wrote $out"
