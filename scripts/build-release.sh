#!/bin/bash
set -euo pipefail

if [[ $# != 2 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || -z "$2" ]]; then
    echo "Usage: build-release.sh VERSION OUTPUT_DIRECTORY" >&2
    exit 2
fi

version="$1"
output="$2"
: "${METALTASK_NOTARY_PROFILE:?Set the notarytool Keychain profile for the same Apple team}"
requested_identity="${METALTASK_SIGNING_IDENTITY:-${APPLE_SIGNING_IDENTITY:-}}"
if [[ -z "$requested_identity" ]]; then
    echo "Set APPLE_SIGNING_IDENTITY to the Developer ID Application certificate name or fingerprint." >&2
    exit 2
fi
profile="$METALTASK_NOTARY_PROFILE"
identity="$(/usr/bin/security find-identity -v -p codesigning |
    awk -v requested="$requested_identity" '/"Developer ID Application:/ {
        name = $0
        sub(/^[^"]*"/, "", name)
        sub(/"$/, "", name)
        if (name == requested || $2 == toupper(requested)) print $2
    }' | sort -u)"
if [[ ! "$identity" =~ ^[[:xdigit:]]{40}$ ]]; then
    echo "Select a unique Developer ID Application identity in Keychain. Use its fingerprint if multiple certificates share a name." >&2
    exit 1
fi
if [[ "$(/usr/bin/uname -m)" != arm64 ]]; then
    echo "Build the MetalTask release from a native Apple Silicon shell." >&2
    exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
asset="MetalTask-${version}-arm64.dmg"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
if [[ -e "$output/$asset" || -L "$output/$asset" ||
      -e "$output/$asset.sha256" || -L "$output/$asset.sha256" ]]; then
    echo "Release output already exists. Choose a new output directory or version." >&2
    exit 1
fi
staging="$(mktemp -d "$output/.metaltask-release.XXXXXX")"
cleanup() { rm -rf "$staging"; }
trap cleanup EXIT

echo "Checking Apple notarization access…" >&2
/usr/bin/xcrun notarytool history --keychain-profile "$profile" --output-format json >/dev/null

cd "$root"
swift test --scratch-path "$staging/swift-build"
swift build -c release --scratch-path "$staging/swift-build"
products="$(swift build -c release --scratch-path "$staging/swift-build" --show-bin-path)"
image_contents="$staging/image"
/bin/bash scripts/package-app.sh "$products/MetalTask" "$image_contents" "$version" "$identity"
ln -s /Applications "$image_contents/Applications"
cp LICENSE "$image_contents/LICENSE.txt"

image="$staging/$asset"
/usr/bin/hdiutil create -srcfolder "$image_contents" -volname MetalTask -format UDZO "$image"
/usr/bin/codesign --timestamp --sign "$identity" "$image"
/usr/bin/codesign --verify --strict "$image"

receipt="$staging/notary.json"
if ! /usr/bin/xcrun notarytool submit "$image" --keychain-profile "$profile" \
    --wait --timeout 30m --output-format json >"$receipt"; then
    cat "$receipt" >&2
    exit 1
fi
status="$(/usr/bin/plutil -extract status raw -o - "$receipt")"
if [[ "$status" != Accepted ]]; then
    cat "$receipt" >&2
    echo "Apple did not accept the DMG for notarization." >&2
    exit 1
fi
/bin/bash scripts/finish-release.sh "$image" "$output"
