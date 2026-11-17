#!/system/bin/sh

MODDIR=${0%/*}
STATE=/data/adb/k90max-radio-fix
LOG="$STATE/service-v2.log"
mkdir -p "$STATE" 2>/dev/null
chmod 0700 "$STATE" 2>/dev/null

log() {
  line="$(date '+%Y-%m-%d %H:%M:%S') $*"
  echo "$line" >> "$LOG" 2>/dev/null
  /system/bin/log -t K90RadioFix "$*" 2>/dev/null
}

run_log() {
  log "RUN: $*"
  "$@" >> "$LOG" 2>&1
  rc=$?
  log "RC=$rc: $*"
  return $rc
}

is_registered() {
  dumpsys telephony.registry 2>/dev/null | grep -qE "mVoiceRegState=0\(IN_SERVICE\)|mDataRegState=0\(IN_SERVICE\)"
}

sim_ready() {
  # Android 17 reports a fully initialized SIM as LOADED. Older builds may
  # briefly use READY, so accept either state for slot 0 only.
  state="$(getprop gsm.sim.state 2>/dev/null)"
  state="${state%%,*}"
  [ "$state" = "READY" ] || [ "$state" = "LOADED" ]
}

wait_registered() {
  limit="$1"
  n=0
  while [ "$n" -lt "$limit" ]; do
    is_registered && return 0
    sleep 1
    n=$((n + 1))
  done
  return 1
}

snapshot() {
  tag="$1"
  out="$STATE/${tag}.txt"
  {
    echo "time=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
    echo "sku=$(getprop ro.boot.product.hardware.sku)"
    echo "platform=$(getprop ro.board.platform)"
    echo "sim_state=$(getprop gsm.sim.state)"
    echo "sim_operator=$(getprop gsm.sim.operator.numeric)"
    echo "operator=$(getprop gsm.operator.numeric)"
    echo "network_type=$(getprop gsm.network.type)"
    echo "baseband=$(getprop gsm.version.baseband)"
    echo "md_status=$(getprop vendor.ril.md_status_from_ccci)"
    echo "airplane=$(settings get global airplane_mode_on 2>/dev/null)"
    echo "mobile_data=$(settings get global mobile_data 2>/dev/null)"
    echo "preferred_network=$(settings get global preferred_network_mode 2>/dev/null)"
    echo "--- processes ---"
    ps -A -o USER,PID,NAME,CONTEXT 2>/dev/null | grep -E "mtkfusionrild|com.oplus.subsys|com.android.phone"
    echo "--- telephony ---"
    dumpsys telephony.registry 2>/dev/null | grep -E "mVoiceRegState|mDataRegState|mServiceState|mSignalStrength|mDataConnectionState" | head -100
  } > "$out" 2>&1
}

SKU="$(getprop ro.boot.product.hardware.sku)"
PLATFORM="$(getprop ro.board.platform)"
log "service start sku=$SKU platform=$PLATFORM sim=$(getprop gsm.sim.state)"
if [ "$SKU" != "prague" ] || [ "$PLATFORM" != "mt6993" ]; then
  log "guard failed sku=$SKU platform=$PLATFORM; disabling module"
  touch "$MODDIR/disable"
  exit 0
fi

# One run per boot, including restarts of this script.
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
if [ -n "$BOOT_ID" ] && [ "$(cat "$STATE/last_boot_id" 2>/dev/null)" = "$BOOT_ID" ]; then
  log "already attempted this boot; skip"
  exit 0
fi
echo "$BOOT_ID" > "$STATE/last_boot_id"

# Wait for framework, phone service and SIM initialization.
n=0
while [ "$n" -lt 240 ]; do
  [ "$(getprop sys.boot_completed)" = "1" ] && service check phone >/dev/null 2>&1 && sim_ready && break
  sleep 1
  n=$((n + 1))
done
log "start waited=${n}s sim=$(getprop gsm.sim.state) md=$(getprop vendor.ril.md_status_from_ccci)"
snapshot v2-before

if ! sim_ready; then
  log "SIM is not READY; no recovery attempted"
  exit 0
fi

# Give the stock modem and ColorOS recovery stack a full minute first.
if wait_registered 60; then
  log "registered normally; no recovery needed"
  snapshot v2-registered-normal
  exit 0
fi

log "still out of service; begin one-shot strong recovery"

# Preserve user-controlled settings once so uninstall can restore them.
if [ ! -f "$STATE/settings.backup" ]; then
  {
    echo "airplane_mode_on=$(settings get global airplane_mode_on 2>/dev/null)"
    echo "mobile_data=$(settings get global mobile_data 2>/dev/null)"
    echo "msim_mode_setting=$(settings get global msim_mode_setting 2>/dev/null)"
  } > "$STATE/settings.backup"
fi

# Keep airplane mode disabled and mobile data enabled. No APN/NV data is erased.
run_log settings put global airplane_mode_on 0
run_log cmd connectivity airplane-mode disable
run_log settings put global msim_mode_setting 1
run_log settings put global mobile_data 1
run_log svc data enable

# Restart MTK's userspace RIL. init owns this process and starts it again.
RIL_PID="$(pidof mtkfusionrild 2>/dev/null)"
if [ -n "$RIL_PID" ]; then
  log "restart mtkfusionrild pid=$RIL_PID"
  for pid in $RIL_PID; do
    run_log kill -TERM "$pid"
  done
  sleep 8
else
  log "mtkfusionrild pid not found"
fi

# Wait for RIL and SIM to return before continuing.
n=0
while [ "$n" -lt 90 ]; do
  pidof mtkfusionrild >/dev/null 2>&1 && sim_ready && break
  sleep 1
  n=$((n + 1))
done
log "RIL return waited=${n}s pid=$(pidof mtkfusionrild 2>/dev/null) sim=$(getprop gsm.sim.state)"

if wait_registered 60; then
  log "recovery result: REGISTERED after RIL restart"
  snapshot v2-after-ril
  exit 0
fi

# Reinitialize only SIM slot 0 when the framework command is available.
if cmd phone help 2>&1 | grep -q "set-sim-power-state"; then
  log "cycle SIM slot 0 power"
  run_log cmd phone set-sim-power-state -s 0 0
  sleep 5
  run_log cmd phone set-sim-power-state -s 0 1
else
  log "set-sim-power-state is unavailable"
fi

# Restart the persistent ColorOS NAS host so PCDR/SIDO re-evaluates no-service.
NAS_PID="$(pidof com.oplus.subsys 2>/dev/null)"
if [ -n "$NAS_PID" ]; then
  log "restart ColorOS NAS pid=$NAS_PID"
  for pid in $NAS_PID; do
    run_log kill -TERM "$pid"
  done
else
  log "ColorOS NAS pid not found"
fi

if wait_registered 120; then
  log "recovery result: REGISTERED after SIM/NAS reset operator=$(getprop gsm.operator.numeric)"
else
  log "recovery result: STILL_OUT_OF_SERVICE; software recovery exhausted"
fi
snapshot v2-after
exit 0
