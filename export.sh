#!/bin/sh
# Exports the Godot project to web/ (the folder Strux serves, see strux.json) and runs the logic tests.
# GODOT points at a Godot 4.7.2 binary with the 4.7.2 web export templates installed.
set -eu
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")"
"$GODOT" --headless --path project --import
"$GODOT" --headless --path project --script res://tests/test_seating.gd
rm -rf web
mkdir -p web
"$GODOT" --headless --path project --export-release "Web" ../web/index.html
ls -l web
