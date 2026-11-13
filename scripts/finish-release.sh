#!/bin/bash
set -euo pipefail

if [[ $# != 2 || ! -f "$1" || ! -d "$2" ]]; then
    echo "Usage: finish-release.sh ACCEPTED_DMG OUTPUT_DIRECTORY" >&2
    exit 2
fi
name="$(basename "$1" .dmg)"
if [[ ! "$name" =~ ^MetalTask-[0-9]+\.[0-9]+\.[0-9]+-arm64$ ]]; then
    echo "Expected a versioned MetalTask ARM64 disk image." >&2
    exit 2
fi
output="$(cd "$2" && pwd)"
for asset in "$name.dmg" "$name.zip" "$name.sha256"; do
    if [[ -e "$output/$asset" || -L "$output/$asset" ]]; then
        echo "Release output already exists: $output/$asset" >&2
        exit 1
    fi
done

staging="$(mktemp -d "$output/.metaltask-final.XXXXXX")"
mount="$staging/mounted"
mounted=false
cleanup() {
    if "$mounted"; then
        /usr/bin/hdiutil detach "$mount" >&2 || return
    fi
    rm -rf "$staging"
}
trap cleanup EXIT

image="$staging/$name.dmg"
cp "$1" "$image"
/usr/bin/xcrun stapler staple "$image"
/usr/bin/xcrun stapler validate "$image"
/usr/bin/codesign --verify --strict "$image"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$image"

mkdir "$mount"
/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$image"
mounted=true
app="$mount/MetalTask.app"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/ditto "$app" "$staging/MetalTask.app"
/usr/bin/hdiutil detach "$mount"
mounted=false

/usr/bin/xcrun stapler staple "$staging/MetalTask.app"
/usr/bin/xcrun stapler validate "$staging/MetalTask.app"
/usr/bin/ditto -c -k --keepParent "$staging/MetalTask.app" "$staging/$name.zip"
mkdir "$staging/extracted"
/usr/bin/ditto -x -k "$staging/$name.zip" "$staging/extracted"
app="$staging/extracted/MetalTask.app"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/xcrun stapler validate "$app"
/usr/sbin/spctl --assess --type execute --verbose=2 "$app"
"$app/Contents/MacOS/MetalTask" --sample-gpu

(cd "$staging" && /usr/bin/shasum -a 256 "$name.dmg" "$name.zip" >"$name.sha256")
for asset in "$name.dmg" "$name.zip" "$name.sha256"; do
    ln "$staging/$asset" "$output/$asset"
    printf 'Verified release asset: %s\n' "$output/$asset"
done
