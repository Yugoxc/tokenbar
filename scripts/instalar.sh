#!/bin/bash
# Empaqueta, instala en /Applications y deja TokenBar corriendo y con arranque
# automático al iniciar sesión.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/empaquetar.sh "$@"

PLIST="$HOME/Library/LaunchAgents/cl.terraworks.tokenbar.plist"

echo "→ instalando…"
launchctl unload "$PLIST" 2>/dev/null || true
pkill -f 'TokenBar.app/Contents/MacOS/TokenBar' 2>/dev/null || true
rm -rf /Applications/TokenBar.app
cp -R build/TokenBar.app /Applications/TokenBar.app

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>cl.terraworks.tokenbar</string>
  <key>ProgramArguments</key>
  <array><string>/Applications/TokenBar.app/Contents/MacOS/TokenBar</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLISTEOF

launchctl load "$PLIST"
echo "✓ TokenBar instalada y corriendo (ícono en la barra de menús)"
