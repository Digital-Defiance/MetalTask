#!/bin/bash
set -euo pipefail

if [[ $# != 3 || ! -x "$1" || ! "$3" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: package-app.sh EXECUTABLE DESTINATION VERSION" >&2
    exit 2
fi

bundle="$2/MetalTask.app"
mkdir -p "$bundle/Contents/MacOS"
install -m 755 "$1" "$bundle/Contents/MacOS/MetalTask"
cat > "$bundle/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MetalTask</string>
  <key>CFBundleIdentifier</key><string>org.digitaldefiance.metaltask</string>
  <key>CFBundleName</key><string>MetalTask</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$3</string>
  <key>CFBundleVersion</key><string>$3</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
/usr/bin/plutil -lint "$bundle/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$bundle"
