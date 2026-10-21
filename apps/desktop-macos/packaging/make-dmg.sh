#!/usr/bin/env bash
# Makes the StoryArc disk image with the designed window (design.md D6).
#   make-dmg.sh <path/to/StoryArc.app> <out.dmg>
# Needs dmgbuild on PATH: python3 -m pip install dmgbuild==1.6.5
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: make-dmg.sh <path/to/StoryArc.app> <out.dmg>" >&2
  exit 2
fi
app=$1
out=$2
[ -d "$app" ] || { echo "make-dmg.sh: no app bundle at $app" >&2; exit 1; }
command -v dmgbuild >/dev/null || {
  echo "make-dmg.sh: dmgbuild is not installed. Run: python3 -m pip install dmgbuild==1.6.5" >&2
  exit 1
}

here=$(cd "$(dirname "$0")" && pwd)
dmgbuild -s "$here/dmg-settings.py" -D app="$app" -D background="$here/background.tiff" StoryArc "$out"
