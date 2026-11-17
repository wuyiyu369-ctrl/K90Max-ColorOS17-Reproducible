#!/system/bin/sh

MODDIR=${0%/*}
STATE=/data/adb/k90max-radio-fix
mkdir -p "$STATE" 2>/dev/null
chmod 0700 "$STATE" 2>/dev/null

log_early() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$STATE/early.log" 2>/dev/null
}

SKU="$(getprop ro.boot.product.hardware.sku)"
PLATFORM="$(getprop ro.board.platform)"
if [ "$SKU" != "prague" ] || [ "$PLATFORM" != "mt6993" ]; then
  log_early "guard failed: sku=$SKU platform=$PLATFORM"
  touch "$MODDIR/disable"
  exit 0
fi

RP=resetprop
[ -x /data/adb/ksu/bin/resetprop ] && RP=/data/adb/ksu/bin/resetprop
[ -x /data/adb/magisk/resetprop ] && RP=/data/adb/magisk/resetprop

# Stage80 的 vendor_init 设置此属性被策略拒绝，导致属性最终缺失。
$RP -n ro.telephony.sim.count 2 2>/dev/null
$RP -n persist.radio.multisim.config dsds 2>/dev/null

log_early "applied sim_count=$(getprop ro.telephony.sim.count) multisim=$(getprop persist.radio.multisim.config)"
