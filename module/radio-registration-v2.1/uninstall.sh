#!/system/bin/sh

STATE=/data/adb/k90max-radio-fix
BACKUP="$STATE/settings.backup"

restore_setting() {
  key="$1"
  value="$(sed -n "s/^${key}=//p" "$BACKUP" 2>/dev/null | head -1)"
  [ -z "$value" ] && return
  if [ "$value" = "null" ]; then
    settings delete global "$key" >/dev/null 2>&1
  else
    settings put global "$key" "$value" >/dev/null 2>&1
  fi
}

if [ -f "$BACKUP" ]; then
  restore_setting airplane_mode_on
  restore_setting mobile_data
  restore_setting msim_mode_setting
  restore_setting preferred_network_mode
fi

# Read-only identity and SIM-count overrides disappear at the next reboot.
# Keep evidence so it can be sent back even after uninstall.
echo "$(date '+%Y-%m-%d %H:%M:%S') module uninstalled; settings restored" >> "$STATE/uninstall.log" 2>/dev/null
