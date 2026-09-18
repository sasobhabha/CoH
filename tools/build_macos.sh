#!/usr/bin/env bash
# Build the double-clickable macOS app.
#
#   tools/build_macos.sh
#
# The output lands in build/macos/Century of Humiliation.app.  Two things this
# wraps that are
# easy to trip over by hand:
#
#   * the exporter refuses to run if the target *folder* does not exist, and it
#     will not create it for you;
#   * build/ needs a .gdignore or Godot imports the exported bundle's own icons
#     and plists back into the project as resources.
#
# The preset (export_presets.cfg) builds a universal x86_64 + arm64 bundle and
# signs it ad-hoc, which is what an Apple Silicon Mac requires to run it at all.
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="build/macos/Century of Humiliation.app"

mkdir -p build/macos
printf '' > build/.gdignore

"$GODOT" --headless --path . --export-release "macOS" "$OUT"

echo
echo "built: $OUT"
du -sh "$OUT"
echo "open it with:  open \"$OUT\""
