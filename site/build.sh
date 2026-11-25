#!/usr/bin/env bash
# Build https://godot-controllers.splatterfacegames.com into site/dist:
# the Web export of demo/demo.tscn (Compatibility renderer, no threads)
# in site/dist/demo, and the static page from site/public. Files over the
# Pages limit move to site/.r2-upload.
#
#   GODOT=<godot 4.7.x with matching Web templates> site/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

rm -rf site/dist site/.r2-upload
mkdir -p site/dist/demo

# The first import after a checkout can crash; a second one passes.
"$GODOT" --headless --path . --import || "$GODOT" --headless --path . --import
"$GODOT" --headless --path . --export-release Web site/dist/demo/index.html
test -s site/dist/demo/index.pck

cp -R site/public/. site/dist/
node site/prepare_r2_assets.mjs site/dist site/.r2-upload
