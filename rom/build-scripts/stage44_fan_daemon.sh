#!/system/bin/sh
# Stage44 vendor-domain fan controller.
# It deliberately uses the Xiaomi thermal contract and fan nodes only; it does
# not disable thermal protection or write CPU/GPU/DDR/UFS frequency nodes.
MARK=/data/vendor/k90max
FAN=/sys/devices/platform/odm/odm:xiaomi_fan
TM=/sys/class/thermal/thermal_message
FG=$TM/foreground_app_name
SCREEN=$TM/screen_state
LOG=$MARK/stage44_fan.log
PIDF=$MARK/stage44_fan.pid
CONF=/odm/etc/performance/game_profiles

mkdir -p "$MARK" 2>/dev/null
echo $$ > "$PIDF" 2>/dev/null
log(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null; }
cap(){ case "$1" in ''|*[!0-9]*) echo 0;; *) [ "$1" -gt 99 ] 2>/dev/null && echo 99 || echo "$1";; esac; }
temp_c(){
  t=$(cat "$TM/board_sensor_temp" 2>/dev/null)
  case "$t" in ''|*[!0-9]*) echo 0;; *) echo $((t / 1000));; esac
}
charging(){ case "$(cat /sys/class/power_supply/battery/status 2>/dev/null)" in Charging|Full) return 0;; *) return 1;; esac; }
awake(){ case "$(cat "$SCREEN" 2>/dev/null)" in 1|on|ON|awake|Awake) return 0;; *) return 1;; esac; }
game(){
  p=$(cat "$FG" 2>/dev/null | tr -dc 'A-Za-z0-9._')
  [ -n "$p" ] || return 1
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | sed 's/#.*$//; s/[[:space:]]//g')
    case "$line" in *=*) pat=${line%%=*}; id=${line#*=};; *) continue;; esac
    case "$id" in 6|18|19|20|25)
      case "$pat" in *\*) pre=${pat%\*}; case "$p" in "$pre"*) return 0;; esac;; *) [ "$p" = "$pat" ] && return 0;; esac;;
    esac
  done < "$CONF"
  return 1
}
setfan(){
  d=$(cap "$1")
  [ -w "$FAN/target_level" ] && [ -w "$FAN/pwm_duty" ] || return 1
  printf '0' > "$FAN/target_level" 2>/dev/null || return 1
  printf '%s' "$d" > "$FAN/pwm_duty" 2>/dev/null || return 1
  [ "$(cat "$FAN/pwm_duty" 2>/dev/null)" = "$d" ]
}
cleanup(){ setfan 0 >/dev/null 2>&1; rm -f "$PIDF"; log 'exit hand-back'; }
trap cleanup EXIT TERM INT
[ "$(cat "$FAN/fan_support" 2>/dev/null)" = 1 ] || { log 'fan_support!=1'; exit 0; }
last=-1
log 'start'
while :; do
  t=$(temp_c); d=0; why=idle
  # Games receive a temperature-based curve; normal use is quiet. Charging at
  # 100% does not spin the fan unless a game or high temperature needs it.
  if game; then
    if [ "$t" -ge 52 ]; then d=90; elif [ "$t" -ge 47 ]; then d=70; elif [ "$t" -ge 42 ]; then d=50; elif [ "$t" -ge 37 ]; then d=30; fi
    why=game
  elif [ "$t" -ge 55 ]; then
    d=90; why=hot
  elif charging && [ "$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)" -lt 100 ] 2>/dev/null && [ "$t" -ge 43 ]; then
    d=40; why=charge
  fi
  # Dozing is quiet unless temperature safety requires cooling.
  awake || [ "$t" -ge 55 ] || { d=0; why=doze; }
  if [ "$d" != "$last" ]; then
    if setfan "$d"; then log "mode=$why temp=${t}C duty=$d"; last=$d; fi
  fi
  sleep 2
done
