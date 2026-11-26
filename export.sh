#!/bin/sh
# Runs the tests and exports the Godot project to web/, the folder that is served (strux.json).
# GODOT points at a Godot 4.7.2 binary with the 4.7.2 web export templates installed.
set -eu
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")"

# web/ is committed, so it must always come from the same Godot (the README says which).
case "$("$GODOT" --version)" in
	4.7.2.*) ;;
	*) echo "export.sh: needs Godot 4.7.2, found $("$GODOT" --version)" >&2; exit 1 ;;
esac
# icon.svg is the listing icon; project/icon.svg is the same picture for the App (Godot reads only project/).
if ! cmp -s icon.svg project/icon.svg; then
	echo "export.sh: icon.svg and project/icon.svg differ; copy icon.svg over project/icon.svg" >&2
	exit 1
fi

"$GODOT" --headless --path project --import
"$GODOT" --headless --path project --script res://tests/test_seating.gd
"$GODOT" --headless --path project --script res://tests/test_app.gd
rm -rf web
mkdir -p web
"$GODOT" --headless --path project --export-release "Web" ../web/index.html
ls -l web
