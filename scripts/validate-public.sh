#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

forbidden='(/Users/|/home/|id_ed25519|tail5d7cb0|com\.hong|ssh-rsa|BEGIN (RSA|OPENSSH|EC|PRIVATE))'
if rg -n --hidden -g '!.git/**' -g '!scripts/validate-public.sh' -g '!*.png' -g '!*.jpg' -g '!*.gif' -g '!*.webp' -g '!*.wav' -g '!dist/**' -g '!build/**' -g '!.build/**' "$forbidden" .; then
  print -u2 "private information pattern found"
  exit 1
fi

for pet in niulai baola muamua; do
  [[ -f "assets/pets/$pet/pet.json" ]] || exit 1
  [[ -f "assets/pets/$pet/spritesheet.webp" ]] || exit 1
done

plutil -lint Resources/Info.plist >/dev/null
plutil -lint Resources/com.callhong.niulai-market-pets.plist.in >/dev/null
print "public validation: PASS"
