#!/bin/bash
set -euo pipefail

if [[ $# != 2 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! -d "$2" ]]; then
    echo "Usage: publish-release.sh VERSION VERIFIED_ARTIFACT_DIRECTORY" >&2
    exit 2
fi
version="$1"
assets="$(cd "$2" && pwd)"
tag="v$version"
name="MetalTask-$version-arm64"
repo="Digital-Defiance/MetalTask"

cd "$assets"
expected="$(/usr/bin/shasum -a 256 "$name.dmg" "$name.zip")"
if [[ "$(cat "$name.sha256")" != "$expected" ]]; then
    echo "Release checksum mismatch." >&2
    exit 1
fi
/usr/bin/xcrun stapler validate "$name.dmg"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
/usr/bin/ditto -x -k "$name.zip" "$scratch"
app="$scratch/MetalTask.app"
/usr/bin/xcrun stapler validate "$app"
/usr/bin/codesign --verify --deep --strict "$app"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" != "$version" ]]; then
    echo "Release version does not match the app bundle." >&2
    exit 1
fi

if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    echo "Release $tag already exists. Use a new version for replacement artifacts." >&2
    exit 1
fi
gh release create "$tag" "$name.dmg" "$name.zip" "$name.sha256" \
    --repo "$repo" --verify-tag --title "MetalTask $version" --generate-notes
