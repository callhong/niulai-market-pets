#!/bin/zsh
set -euo pipefail

user_home="$HOME"
[[ -n "$user_home" ]] || { print -u2 "HOME is required"; exit 1; }
state_root="$user_home/Library/Application Support/NiuLaiMarketPets"
state_file="$state_root/install-state.json"
[[ -f "$state_file" ]] || { print -u2 "install state not found: $state_file"; exit 1; }

backup_root="$(jq -r '.backupRoot' "$state_file")"
uid="$(id -u)"
label="com.callhong.niulai-market-pets"
app_path="$user_home/Applications/NiuLaiMarketPets.app"
plist_path="$user_home/Library/LaunchAgents/$label.plist"
expected_backup_root="$state_root/install-backups"
case "$backup_root" in
  "$expected_backup_root"/*) ;;
  *) print -u2 "unsafe backup path in install state: $backup_root"; exit 1 ;;
esac

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

for legacy_backup in "$backup_root/legacy-launchagents/"*.plist(N); do
  legacy_destination="$user_home/Library/LaunchAgents/${legacy_backup:t}"
  if [[ ! -e "$legacy_destination" ]]; then
    cp -p "$legacy_backup" "$legacy_destination"
    plutil -lint "$legacy_destination" >/dev/null
    launchctl bootstrap "gui/$uid" "$legacy_destination" 2>/dev/null || true
  fi
done

print "uninstalled: $app_path"
print "restored pre-install app and LaunchAgent when present"
print "recovery backups retained at: $backup_root"
