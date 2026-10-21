#!/bin/zsh
# Builds build/Clawdling.app from main.swift. Needs only the Xcode Command Line Tools.
set -e
cd "$(dirname "$0")"
if ! command -v swiftc >/dev/null; then
  echo "swiftc not found. Install the Command Line Tools first:  xcode-select --install" >&2
  exit 1
fi
APP=build/Clawdling.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 main.swift -o "$APP/Contents/MacOS/Clawdling" -framework AppKit
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Clawdling</string>
  <key>CFBundleIdentifier</key><string>io.github.clawdling</string>
  <key>CFBundleExecutable</key><string>Clawdling</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
codesign -s - --force "$APP" >/dev/null 2>&1 || true
echo "built $APP"
