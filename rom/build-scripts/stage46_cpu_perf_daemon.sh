#!/system/bin/sh
MODDIR=/data/adb/k90max
LOG=$MODDIR/cpu_perf.log
SCONFIG=/sys/class/thermal/thermal_message/sconfig
TEMP=/sys/class/thermal/thermal_message/board_sensor_temp

TARGET_SCENE=20
SAFE_TEMP=45000
CHECK_INTERVAL=3

mkdir -p $MODDIR 2>/dev/null
log(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG 2>/dev/null; }

i=0
while [ $i -lt 60 ]; do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 1; i=$((i+1))
done

log "CPU perf daemon start (target=$TARGET_SCENE)"

while true; do
  temp=$(cat $TEMP 2>/dev/null | tr -dc '0-9')
  [ -z "$temp" ] && temp=0

  if [ $temp -ge $SAFE_TEMP ]; then
    current=$(cat $SCONFIG 2>/dev/null)
    if [ "$current" != "0" ] && [ "$current" != "6" ]; then
      echo "0" > $SCONFIG 2>/dev/null
      log "SAFETY: temp ${temp}mC -> auto"
    fi
    sleep $CHECK_INTERVAL
    continue
  fi

  current=$(cat $SCONFIG 2>/dev/null)

  if [ "$current" != "$TARGET_SCENE" ]; then
    echo "$TARGET_SCENE" > $SCONFIG 2>/dev/null
    new=$(cat $SCONFIG 2>/dev/null)
    if [ "$new" = "$TARGET_SCENE" ]; then
      log "FIX sconfig: $current -> $TARGET_SCENE (temp=${temp}mC)"
    else
      log "FAIL write: $current -> $TARGET_SCENE (actual=$new)"
    fi
  fi

  sleep $CHECK_INTERVAL
done
