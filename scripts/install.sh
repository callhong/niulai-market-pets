#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
user_home="$HOME"
[[ -n "$user_home" ]] || { print -u2 "HOME is required"; exit 1; }
tmp_root="${TMPDIR:-/tmp}"
state_root="$user_home/Library/Application Support/NiuLaiMarketPets"
backup_root="$state_root/install-backups/$(date +%Y%m%d-%H%M%S)"
app_destination="$user_home/Applications/NiuLaiMarketPets.app"
plist_destination="$user_home/Library/LaunchAgents/com.callhong.niulai-market-pets.plist"
label="com.callhong.niulai-market-pets"
uid="$(id -u)"

skip_build="${NIULAI_SKIP_BUILD-0}"
if [[ "$skip_build" == "1" ]]; then
  app_source="${NIULAI_APP_SOURCE:?NIULAI_APP_SOURCE is required when skipping the build}"
else
  "$script_dir/build-app.sh" >/dev/null
  app_source="$project_root/build/NiuLaiMarketPets.build"
fi
[[ -x "$app_source/Contents/MacOS/NiuLaiMarketPets" ]] || { print -u2 "app build missing: $app_source"; exit 1; }
[[ -d "$app_source/Contents/Resources/Pets" ]] || { print -u2 "bundled pet resources missing"; exit 1; }

mkdir -p "$state_root/logs" "$backup_root/legacy-launchagents" \
  "$user_home/Applications" "$user_home/Library/LaunchAgents"

had_app=false
had_plist=false
[[ -e "$app_destination" ]] && had_app=true
[[ -e "$plist_destination" ]] && had_plist=true
if $had_app; then ditto "$app_destination" "$backup_root/app-before-install"; fi
if $had_plist; then cp -p "$plist_destination" "$backup_root/launchagent-before-install.plist"; fi

# Stop both the installed controller and a manually opened DMG copy before
# replacing the bundle. Older builds did not have the single-instance lock;
# matching the exact product executable keeps upgrades deterministic without
# touching unrelated processes.
launchctl bootout "gui/$uid/$label" 2>/dev/null || true
for attempt in {1..20}; do
  found_running=false
  while read -r process_id process_command; do
    case "$process_command" in
      */NiuLaiMarketPets.app/Contents/MacOS/NiuLaiMarketPets)
        [[ "$process_id" == "$$" ]] && continue
        kill "$process_id" 2>/dev/null || true
        found_running=true
        ;;
    esac
  done < <(ps -axo pid=,command=)
  $found_running || break
  sleep 0.1
done

# Migrate any older controller for this product family so a direct install
# cannot leave two floating pets running at the same time.
for legacy_plist in "$user_home/Library/LaunchAgents/"*niulai-market-pets*.plist(N); do
  legacy_label="${legacy_plist:t:r}"
  [[ "$legacy_label" == "$label" ]] && continue
  launchctl bootout "gui/$uid/$legacy_label" 2>/dev/null || true
  cp -p "$legacy_plist" "$backup_root/legacy-launchagents/$legacy_label.plist"
  rm -f "$legacy_plist"
done

staging="$(mktemp -d "$tmp_root/niulai-install.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app_source" "$staging/NiuLaiMarketPets.app"

if [[ -e "$app_destination" ]]; then rm -rf "$app_destination"; fi
mv "$staging/NiuLaiMarketPets.app" "$app_destination"

log_path="$state_root/logs/controller.log"
error_log_path="$state_root/logs/controller.error.log"
plist_template="$project_root/Resources/com.callhong.niulai-market-pets.plist.in"
[[ -f "$plist_template" ]] || { print -u2 "LaunchAgent template missing: $plist_template"; exit 1; }
plist_tmp="$staging/com.callhong.niulai-market-pets.plist"
sed -e "s|__APP_EXECUTABLE__|$app_destination/Contents/MacOS/NiuLaiMarketPets|g" \
    -e "s|__LOG_PATH__|$log_path|g" \
    -e "s|__ERROR_LOG_PATH__|$error_log_path|g" \
    "$plist_template" > "$plist_tmp"
plutil -lint "$plist_tmp" >/dev/null
if [[ -e "$plist_destination" ]]; then rm -f "$plist_destination"; fi
mv "$plist_tmp" "$plist_destination"

jq -n \
  --arg installedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg appPath "$app_destination" \
  --arg plistPath "$plist_destination" \
  --arg backupRoot "$backup_root" \
  --argjson hadApp "$had_app" \
  --argjson hadPlist "$had_plist" \
  '{schemaVersion:2, installedAt:$installedAt, appPath:$appPath, plistPath:$plistPath, backupRoot:$backupRoot, hadApp:$hadApp, hadPlist:$hadPlist}' \
  > "$state_root/install-state.json"

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
