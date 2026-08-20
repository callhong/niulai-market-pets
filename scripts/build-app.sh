#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
swift_cmd="$(command -v swift)"

"$swift_cmd" build --configuration release --product NiuLaiMarketPets
bin_dir="$("$swift_cmd" build --configuration release --product NiuLaiMarketPets --show-bin-path)"
binary="$bin_dir/NiuLaiMarketPets"
[[ -x "$binary" ]] || { print -u2 "release binary not found: $binary"; exit 1; }

build_root="$project_root/build"
mkdir -p "$build_root"
staging="$(mktemp -d "${TMPDIR:-/tmp}/niulai-app.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/NiuLaiMarketPets.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/NiuLaiMarketPets"
cp "$project_root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$project_root/Resources/BrandMark.svg" "$app/Contents/Resources/BrandMark.svg"
cp "$project_root/Resources/Audio/"*.wav "$app/Contents/Resources/"
for pet in niulai baola muamua; do
  mkdir -p "$app/Contents/Resources/Pets/$pet"
  cp "$project_root/assets/pets/$pet/pet.json" "$project_root/assets/pets/$pet/spritesheet.webp" "$app/Contents/Resources/Pets/$pet/"
done
chmod 755 "$app/Contents/MacOS/NiuLaiMarketPets"
codesign --force --deep --sign - "$app"

output="$build_root/NiuLaiMarketPets.build"
if [[ -e "$output" ]]; then
  rm -rf "$output"
fi
ditto "$app" "$output"
print "$output"
