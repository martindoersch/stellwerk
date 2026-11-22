#!/bin/sh
# Kopiert das Stellwerk-Plug-in in Lightrooms Modules-Ordner (dort lädt Lightroom es beim Start von selbst).
# Aus dem Repo heraus über den Zusatzmodul-Manager hinzugefügt, fand Lightroom nur Info.lua,
# die übrigen Skripte nicht („No script by the name …“).
# Nach Änderungen erneut ausführen und in Lightroom „Zusatzmodul neu laden“ (oder Lightroom neu starten).
set -e
src="$(cd "$(dirname "$0")" && pwd)/Stellwerk.lrplugin"
dst="$HOME/Library/Application Support/Adobe/Lightroom/Modules/Stellwerk.lrplugin"
mkdir -p "$dst"
cp -f "$src"/*.lua "$dst"/
echo "Installiert: $dst"
