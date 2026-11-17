#!/system/bin/sh
MODDIR=${0%/*}
STATE=/data/vendor/k90max/module_state
SOURCE="$MODDIR/config/oplus_vrr_config.json"
TARGET=/data/system/oplus_vrr_config.json
MARKER=/data/system/.k90max_vrr_override

mkdir -p "$STATE"
printf '%s\n' k90max_game_system_fix > "$STATE/.owner"

# Install the VRR override before system_server starts.  This is a real
# ColorOS data-config path, not a system/vendor overlay mount.
[ "$(getprop ro.boot.product.hardware.sku)" = prague ] || exit 0
[ "$(getprop ro.board.platform)" = mt6993 ] || exit 0
[ -s "$SOURCE" ] || exit 0

if [ -e "$TARGET" ] && [ ! -e "$MARKER" ] &&
   [ ! -e "$STATE/orig_oplus_vrr_config.json" ]; then
  cp -p "$TARGET" "$STATE/orig_oplus_vrr_config.json" 2>/dev/null
  printf '1\n' > "$STATE/orig_oplus_vrr_present"
elif [ ! -e "$TARGET" ] && [ ! -e "$STATE/orig_oplus_vrr_present" ]; then
  printf '0\n' > "$STATE/orig_oplus_vrr_present"
fi

tmp=/data/system/.oplus_vrr_config.k90max.tmp
cp "$SOURCE" "$tmp" 2>/dev/null || exit 0
chown system:system "$tmp" 2>/dev/null
chmod 0600 "$tmp" 2>/dev/null
restorecon "$tmp" >/dev/null 2>&1
mv -f "$tmp" "$TARGET" 2>/dev/null || exit 0
restorecon "$TARGET" >/dev/null 2>&1
printf 'k90max_game_system_fix\n' > "$MARKER"
chown system:system "$MARKER" 2>/dev/null
chmod 0600 "$MARKER" 2>/dev/null
restorecon "$MARKER" >/dev/null 2>&1
