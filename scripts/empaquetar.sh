#!/bin/bash
# Compila TokenBar y arma el bundle .app listo para /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(grep -m1 'VERSION=' scripts/version.txt 2>/dev/null | cut -d= -f2 || echo 1.0.0)}"
APP="build/TokenBar.app"

echo "→ compilando (release)…"
swift build -c release

echo "→ armando bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TokenBar "$APP/Contents/MacOS/TokenBar"
cp Recursos/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TokenBar</string>
  <key>CFBundleDisplayName</key><string>TokenBar</string>
  <key>CFBundleIdentifier</key><string>cl.terraworks.tokenbar</string>
  <key>CFBundleExecutable</key><string>TokenBar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- Agente: vive solo en la barra de menús, sin ícono en el Dock. -->
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Uso interno</string>
</dict>
</plist>
PLIST

# Firma ad-hoc: suficiente para correr local y para que macOS recuerde permisos.
codesign --force --deep --sign - "$APP" 2>/dev/null

echo "✓ listo: $APP"
