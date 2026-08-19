#!/bin/zsh
set -euo pipefail

user_home="${HOME:?HOME is required}"
state_root="$user_home/.codex/market-pet"
state_file="$state_root/install-state.json"
remove_pets=false
[[ "${1:-}" == "--remove-pets" ]] && remove_pets=true
[[ -f "$state_file" ]] || { print -u2 "install state not found: $state_file"; exit 1; }

backup_root="$(jq -r '.backupRoot' "$state_file")"
uid="$(id -u)"
label="com.callhong.niulai-market-pets"

# install-state.json is user-writable. Never use its paths as deletion targets.
# Reconstruct the expected locations from HOME and accept backups only below
# the install-backups directory created by install.sh.
app_path="$user_home/Applications/NiuLaiMarketPets.app"
plist_path="$user_home/Library/LaunchAgents/$label.plist"
config_path="$user_home/.codex/config.toml"
pets_root="$user_home/.codex/pets"
expected_backup_root="$user_home/.codex/market-pet/install-backups"
case "$backup_root" in
  "$expected_backup_root"/*) ;;
  *) print -u2 "unsafe backup path in install state: $backup_root"; exit 1 ;;
esac
config_backup="$backup_root/config.toml.before-install"

launchctl bootout "gui/$uid/$label" 2>/dev/null || true

if [[ -e "$app_path" ]]; then rm -rf "$app_path"; fi
if [[ "$(jq -r '.hadApp' "$state_file")" == true && -e "$backup_root/app-before-install" ]]; then
  mkdir -p "$(dirname "$app_path")"
  ditto "$backup_root/app-before-install" "$app_path"
fi

if [[ -e "$plist_path" ]]; then rm -f "$plist_path"; fi
if [[ "$(jq -r '.hadPlist' "$state_file")" == true && -e "$backup_root/launchagent-before-install.plist" ]]; then
  mkdir -p "$(dirname "$plist_path")"
  cp -p "$backup_root/launchagent-before-install.plist" "$plist_path"
fi

for pet in niulai baola muamua; do
  pet_path="$pets_root/$pet"
  if [[ -e "$pet_path" ]]; then rm -rf "$pet_path"; fi
  had="$(jq -r ".hadPets.$pet" "$state_file")"
  if [[ "$had" == true && -e "$backup_root/pets/$pet" ]]; then
    mkdir -p "$pets_root"
    ditto "$backup_root/pets/$pet" "$pet_path"
  fi
done

if [[ -f "$config_backup" ]]; then
  cp -p "$config_backup" "$config_path"
fi

if $remove_pets; then
  for pet in niulai baola muamua; do
    pet_path="$pets_root/$pet"
    if [[ -e "$pet_path" ]]; then rm -rf "$pet_path"; fi
  done
fi

print "uninstalled controller and restored pre-install configuration"
print "recovery backups retained at: $backup_root"
if $remove_pets; then
  print "explicit --remove-pets applied"
else
  print "pet packages retained only when they existed before install; use --remove-pets to delete installed packages"
fi
