#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"

"$script_dir/build-app.sh" >/dev/null

app="$project_root/build/NiuLaiMarketPets.build"
[[ -d "$app" ]] || { print -u2 "app build missing: $app"; exit 1; }
command -v hdiutil >/dev/null || { print -u2 "hdiutil is required to build a macOS DMG"; exit 1; }

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
dist="$project_root/dist"
mkdir -p "$dist"
dmg="$dist/NiuLaiMarketPets-$version.dmg"
staging="$(mktemp -d "${TMPDIR:-/tmp}/niulai-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

ditto "$app" "$staging/NiuLaiMarketPets.app"
cp "$project_root/README.md" "$staging/README.md"
mkdir -p "$staging/Resources" "$staging/scripts"
cp "$project_root/Resources/com.callhong.niulai-market-pets.plist.in" "$staging/Resources/"
cp "$project_root/scripts/install.sh" "$project_root/scripts/uninstall.sh" "$staging/scripts/"
cp "$project_root/scripts/install-from-dmg.command" "$staging/Install NiuLai Market Pets.command"
chmod +x "$staging/Install NiuLai Market Pets.command" "$staging/scripts/install.sh" "$staging/scripts/uninstall.sh"
rm -f "$dmg"
hdiutil create -volname "NiuLai Market Pets" -srcfolder "$staging" -format UDZO -ov "$dmg" >/dev/null
print "$dmg"
