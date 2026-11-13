#!/bin/bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 || ! -f "$1" || ! -x "$1" || ! "$3" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: package-app.sh EXECUTABLE DESTINATION VERSION [DEVELOPER_ID]" >&2
    exit 2
fi

bundle="$2/MetalTask.app"
identity="${4:--}"
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
if [[ "$identity" == "-" ]]; then
    /usr/bin/codesign --force --sign - "$bundle"
else
    /usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "$bundle"
fi
/usr/bin/codesign --verify --deep --strict "$bundle"
