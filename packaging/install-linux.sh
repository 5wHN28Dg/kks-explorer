#!/bin/sh
# Put KKS Explorer in your applications menu (for you only, no root needed). Run it from the unpacked folder:
#   ./install-linux.sh            install or update
#   ./install-linux.sh --remove   remove the program (your data in ~/.local/share/kks-explorer stays)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
DEST="$HOME/.local/opt/kks-explorer"
MENU="$HOME/.local/share/applications/kks-explorer.desktop"
if [ "$1" = "--remove" ]; then
  rm -rf "$DEST" "$MENU"
  echo "Removed. Your data is still in ~/.local/share/kks-explorer (delete it yourself if you mean to)."
  exit 0
fi
mkdir -p "$DEST" "$(dirname "$MENU")"
rm -rf "$DEST/app"
cp -r "$HERE/KKS Explorer" "$DEST/app"
cp "$HERE/KKS Explorer/_internal/icon-512.png" "$DEST/icon.png"
cat > "$MENU" <<DESKTOP
[Desktop Entry]
Type=Application
Name=KKS Explorer
Comment=Plant P&IDs and KKS codes
Exec="$DEST/app/KKS Explorer"
Icon=$DEST/icon.png
Terminal=false
Categories=Office;Engineering;
DESKTOP
chmod +x "$MENU"
echo "Installed. Start it from your applications menu (KKS Explorer)."
