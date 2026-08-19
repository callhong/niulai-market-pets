#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
asset_root="$project_root/assets/pets"
user_home="${HOME:?HOME is required}"
codex_root="$user_home/.codex"
pets_root="$codex_root/pets"
state_root="$codex_root/market-pet"
backup_root="$state_root/install-backups/$(date +%Y%m%d-%H%M%S)"
app_destination="$user_home/Applications/NiuLaiMarketPets.app"
plist_destination="$user_home/Library/LaunchAgents/com.callhong.niulai-market-pets.plist"
label="com.callhong.niulai-market-pets"
uid="$(id -u)"
config_path="$codex_root/config.toml"

[[ -f "$config_path" ]] || { print -u2 "Codex config not found: $config_path"; exit 1; }
for pet in niulai baola muamua; do
  [[ -f "$asset_root/$pet/pet.json" ]] || { print -u2 "pet manifest missing: $pet"; exit 1; }
  [[ -f "$asset_root/$pet/spritesheet.webp" ]] || { print -u2 "pet spritesheet missing: $pet"; exit 1; }
done

if [[ "${NIULAI_SKIP_BUILD:-0}" == "1" ]]; then
  app_source="${NIULAI_APP_SOURCE:?NIULAI_APP_SOURCE is required when skipping the build}"
else
  "$script_dir/build-app.sh" >/dev/null
  app_source="$project_root/build/NiuLaiMarketPets.build"
fi
[[ -x "$app_source/Contents/MacOS/NiuLaiMarketPets" ]] || { print -u2 "app build missing"; exit 1; }

mkdir -p "$pets_root" "$state_root/logs" "$state_root/config-backups" "$backup_root/pets" "$user_home/Applications" "$user_home/Library/LaunchAgents"
config_backup="$backup_root/config.toml.before-install"
cp -p "$config_path" "$config_backup"

had_app=false
had_plist=false
[[ -e "$app_destination" ]] && had_app=true
[[ -e "$plist_destination" ]] && had_plist=true
if $had_app; then ditto "$app_destination" "$backup_root/app-before-install"; fi
if $had_plist; then cp -p "$plist_destination" "$backup_root/launchagent-before-install.plist"; fi

typeset -A had_pet
for pet in niulai baola muamua; do
  had_pet[$pet]=false
  pet_destination="$pets_root/$pet"
  if [[ -e "$pet_destination" ]]; then
    had_pet[$pet]=true
    ditto "$pet_destination" "$backup_root/pets/$pet"
  fi
done

staging="$(mktemp -d "${TMPDIR:-/tmp}/niulai-install.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
for pet in niulai baola muamua; do
  mkdir -p "$staging/pets/$pet"
  cp "$asset_root/$pet/pet.json" "$staging/pets/$pet/pet.json"
  cp "$asset_root/$pet/spritesheet.webp" "$staging/pets/$pet/spritesheet.webp"
done
ditto "$app_source" "$staging/NiuLaiMarketPets.app"

for pet in niulai baola muamua; do
  pet_destination="$pets_root/$pet"
  if [[ -e "$pet_destination" ]]; then rm -rf "$pet_destination"; fi
  mv "$staging/pets/$pet" "$pet_destination"
done
if [[ -e "$app_destination" ]]; then rm -rf "$app_destination"; fi
mv "$staging/NiuLaiMarketPets.app" "$app_destination"

log_path="$state_root/logs/controller.log"
error_log_path="$state_root/logs/controller.error.log"
plist_tmp="$staging/com.callhong.niulai-market-pets.plist"
sed -e "s|__APP_EXECUTABLE__|$app_destination/Contents/MacOS/NiuLaiMarketPets|g" \
    -e "s|__LOG_PATH__|$log_path|g" \
    -e "s|__ERROR_LOG_PATH__|$error_log_path|g" \
    "$project_root/Resources/com.callhong.niulai-market-pets.plist.in" > "$plist_tmp"
plutil -lint "$plist_tmp" >/dev/null
if [[ -e "$plist_destination" ]]; then rm -f "$plist_destination"; fi
mv "$plist_tmp" "$plist_destination"

jq -n \
  --arg installedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg appPath "$app_destination" \
  --arg plistPath "$plist_destination" \
  --arg configPath "$config_path" \
  --arg configBackup "$config_backup" \
  --arg backupRoot "$backup_root" \
  --argjson hadApp "$had_app" \
  --argjson hadPlist "$had_plist" \
  --argjson hadNiulai "${had_pet[niulai]}" \
  --argjson hadBaola "${had_pet[baola]}" \
  --argjson hadMuamua "${had_pet[muamua]}" \
  '{schemaVersion:1, installedAt:$installedAt, appPath:$appPath, plistPath:$plistPath, configPath:$configPath, configBackup:$configBackup, backupRoot:$backupRoot, hadApp:$hadApp, hadPlist:$hadPlist, hadPets:{niulai:$hadNiulai,baola:$hadBaola,muamua:$hadMuamua}}' \
  > "$state_root/install-state.json"

launchctl bootout "gui/$uid/$label" 2>/dev/null || true
sleep 2
bootstrap_ok=false
for attempt in 1 2 3; do
  if launchctl bootstrap "gui/$uid" "$plist_destination"; then
    bootstrap_ok=true
    break
  fi
  launchctl bootout "gui/$uid/$label" 2>/dev/null || true
  sleep 1
done
if ! $bootstrap_ok; then
  print -u2 "LaunchAgent bootstrap failed after 3 attempts; install backups remain at $backup_root"
  exit 1
fi
launchctl kickstart -k "gui/$uid/$label"
print "installed: $app_destination"
print "launch agent: $plist_destination"
print "state: $state_root/install-state.json"
