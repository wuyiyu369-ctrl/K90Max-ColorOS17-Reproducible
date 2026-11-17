#!/system/bin/sh
# =============================================================================
# K90 Max 性能桥 (Layer A)  --  perf_bridge
#
# 作用：把「场景语义」翻译成小米底层温控场景选择器
#       /sys/class/thermal/thermal_message/sconfig
#
# 为什么必须是 sconfig：
#   本机 CPU 上限的最终仲裁者是小米内核模块 mi_thermal_interface
#   (/proc/mtk_freq_qos/max_dominant 的持有者 = init_module+0x1e8/0xec4
#    [mi_thermal_interface])，它读的是小米温控策略表；策略表由 sconfig
#   选中的场景决定（/data/vendor/thermal/decrypt.txt）。
#   donor/ColorOS 期望的 vendor.oplus.hardware.performance.IPerformance
#   在本机不存在（audioserver/surfaceflinger 的 find 请求被 SELinux 拒绝），
#   所以必须由本桥把「游戏在前台」这类语义喂给 sconfig。
#   而 scaling_max_freq 是 0444 只读，任何模块都写不进去 —— 不要去写。
#
# 硬性安全边界：
#   * 只写 sconfig / 阅读其它节点；永不写 scaling_max_freq、scaling_min_freq、
#     governor、thermal 阈值，永不关 thermal、永不锁最高频。
#   * 温度 >= SAFE_TEMP_HARD 立即回退 DEFAULT_SCENE，且在温度降到
#     SAFE_TEMP_COOL 之前不再提频（比厂商 yuanshen 表自己的 48C 阈值更严）。
#   * 灭屏 / 无匹配应用 / 守护退出 / disable 标志 -> 仅在本桥曾接管时恢复。
#   * 读不到温度、写不进节点等任何异常 -> 走回退分支，绝不「锁死在高档」。
#
# 实测的重要语义（2026-10-16 实机 A/B，务必先读）：
#   * sconfig 只有写成「有效场景 id」时，mi_thermald 才会立刻重载策略表：
#       0  -> BAT_SOC  厂商自动基线   dec=6254B   caps 1500000/1700000/1850000
#       19 -> MGAME                   dec=3618B   caps 1400000/1900000/2300000
#       20 -> YUANSHEN (最宽松)       dec=3705B   caps 1800000/1900000/2300000
#                                     （8 线程负载下实测 cur 冲到 2200000/2700000/3050000）
#   * -1 是「不触发重载」的哨兵：写 -1 只改文件值，已加载的策略表保持不变。
#     所以回退必须两步：先写 0（把表重载回厂商自动），再写 -1（文件回开机默认值）。
#
# 用法：
#   sh bin/perf_bridge             常驻守护（由 service.sh 拉起）
#   sh bin/perf_bridge --once      跑一轮决策并打印状态（会按决策写入）
#   sh bin/perf_bridge --dry       只打印决策，绝不写入（验证用）
#   sh bin/perf_bridge --status    打印当前状态
#   sh bin/perf_bridge --test 包名 只读验证映射表对某个包名的判定（不写任何节点）
#   sh bin/perf_bridge --test      不带包名 = 逐条自测整张映射表
#   关闭：touch /data/vendor/k90max/disable_perf
#   日志：/data/vendor/k90max/stage37_perf.log
#
# 注意：锁屏时 Android 没有 topResumedActivity，前台包名为空，桥会记录
#       lock-screen 并保持 auto —— 这是预期行为，不是故障。
# =============================================================================

MARK=/data/vendor/k90max
MODDIR=${0%/*}/..
[ -d "$MODDIR/etc/performance" ] || MODDIR=/odm
GAME_CONF=$MODDIR/etc/performance/game_profiles
SAFE_CONF=$MODDIR/etc/performance/thermal_safe
CONF=$MARK/perf.conf
LOG=$MARK/stage37_perf.log
PIDF=$MARK/stage37_perf.pid
OWNED_FILE=$MARK/perf_scene_owned
TM=/sys/class/thermal/thermal_message
SC=$TM/sconfig
FG=$TM/foreground_app_name
SCREEN=$TM/screen_state
DEC=/data/vendor/thermal/decrypt.txt

# ---- 默认参数（可被 /odm/etc/performance/thermal_safe 与
#      /data/vendor/k90max/perf.conf 覆盖，后者优先）
POLL_SEC=5
LAUNCH_BOOST_SEC=4
LAUNCH_SCENE=20
SAFE_TEMP_HARD=45000
SAFE_TEMP_COOL=41000
SAFE_TEMP_SLEEP=48000
SCREEN_OFF_AUTO=1
CHARGE_NO_BOOST=0
DEFAULT_SCENE=0      # 0 = BAT_SOC 厂商自动基线；必须用「有效 id」才能触发策略表重载
EXIT_SCENE=-1        # 退出时把文件写回开机默认值 -1（-1 不触发重载，表保持自动）
LOG_TAIL=150

COOLDOWN=0      # 1 = 处于高温熔断，禁止提频
SC_LAST=""      # 本桥最后一次设定的场景
OWNED=0          # 只有本桥写过游戏场景后，才允许执行恢复写入
WHY="init"
LAST_FG=""
BOOST_UNTIL=0

log(){ echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null; }
rotate_log(){ [ -s "$LOG" ] && { tail -n $LOG_TAIL "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null; }; }

read_cfg(){
  _f=""; _l=""; _k=""; _v=""
  for _f in "$SAFE_CONF" "$CONF"; do
    [ -f "$_f" ] || continue
    while IFS= read -r _l; do
      _l=$(printf '%s' "$_l" | sed 's/#.*$//')
      case "$_l" in *=*) ;; *) continue ;; esac
      # Files edited on Windows may use CRLF.  A trailing '\r' made numeric
      # values fail validation, silently restoring POLL_SEC to 5 seconds.
      _k=$(printf '%s' "${_l%%=*}" | tr -d ' \t\r')
      _v=$(printf '%s' "${_l#*=}" | tr -d ' \t\r')
      [ -z "$_k" ] && continue
      case "$_k" in
        POLL_SEC)        case "$_v" in ''|*[!0-9]*) ;; *) POLL_SEC=$_v ;; esac ;;
        LAUNCH_BOOST_SEC) case "$_v" in ''|*[!0-9]*) ;; *) LAUNCH_BOOST_SEC=$_v ;; esac ;;
        LAUNCH_SCENE)     case "$_v" in ''|*[!0-9]*) ;; *) LAUNCH_SCENE=$_v ;; esac ;;
        SAFE_TEMP_HARD)  case "$_v" in ''|*[!0-9]*) ;; *) SAFE_TEMP_HARD=$_v ;; esac ;;
        SAFE_TEMP_COOL)  case "$_v" in ''|*[!0-9]*) ;; *) SAFE_TEMP_COOL=$_v ;; esac ;;
        SAFE_TEMP_SLEEP) case "$_v" in ''|*[!0-9]*) ;; *) SAFE_TEMP_SLEEP=$_v ;; esac ;;
        DEFAULT_SCENE)   case "$_v" in ''|*[!0-9-]*) ;; *) DEFAULT_SCENE=$_v ;; esac ;;
        EXIT_SCENE)      case "$_v" in ''|*[!0-9-]*) ;; *) EXIT_SCENE=$_v ;; esac ;;
        SCREEN_OFF_AUTO) SCREEN_OFF_AUTO=$_v ;;
        CHARGE_NO_BOOST) CHARGE_NO_BOOST=$_v ;;
      esac
    done < "$_f"
  done
  [ "$POLL_SEC" -ge 1 ] 2>/dev/null || POLL_SEC=5
}

# ---------------- 只读观测 ----------------
temp_mc(){ cat $TM/board_sensor_temp 2>/dev/null | tr -dc '0-9-'; }
caps_now(){ for _p in 0 4 7; do printf '%s ' "$(cat /sys/devices/system/cpu/cpufreq/policy$_p/scaling_max_freq 2>/dev/null)"; done; }
cpu_now(){
  for _p in 0 4 7; do
    _cur=$(cat /sys/devices/system/cpu/cpufreq/policy$_p/scaling_cur_freq 2>/dev/null)
    _max=$(cat /sys/devices/system/cpu/cpufreq/policy$_p/scaling_max_freq 2>/dev/null)
    printf 'p%s=%s/%s ' "$_p" "${_cur:-?}" "${_max:-?}"
  done
}
metric_first(){
  for _f in "$@"; do
    [ -r "$_f" ] || continue
    _v=$(cat "$_f" 2>/dev/null | tr '\r\n' ' ' | tr -s ' ' | sed 's/^ //;s/ $//')
    [ -n "$_v" ] && { printf '%s' "$_v"; return 0; }
  done
  printf '?'
}
gpu_now(){
  metric_first \
    /sys/kernel/ged/hal/current_freqency \
    /sys/kernel/ged/hal/gpu_cur_freq \
    /sys/class/misc/mali0/device/devfreq/*/cur_freq
}
ddr_now(){
  metric_first \
    /sys/class/devfreq/mtk-dvfsrc-devfreq/cur_freq \
    /sys/devices/platform/soc/1c100000.dvfsrc/mtk-dvfsrc-devfreq/devfreq/mtk-dvfsrc-devfreq/cur_freq
}
ufs_now(){
  metric_first \
    /sys/class/devfreq/16810000.ufshci/cur_freq \
    /sys/devices/platform/soc/16810000.ufshci/devfreq/16810000.ufshci/cur_freq
}
metrics_now(){ printf 'cpu[%s] gpu=%s ddr=%s ufs=%s' "$(cpu_now)" "$(gpu_now)" "$(ddr_now)" "$(ufs_now)"; }
profile_count(){ grep -vE '^[[:space:]]*(#|$)' "$GAME_CONF" 2>/dev/null | wc -l | tr -dc '0-9'; }
dec_bytes(){ _n=$(wc -c < "$DEC" 2>/dev/null | tr -dc '0-9'); [ -n "$_n" ] && printf '%s' "$_n" || printf '?'; }
screen_state(){
  _s=$(cat "$SCREEN" 2>/dev/null | tr -dc '0-9A-Za-z_-')
  case "$_s" in
    1|on|ON|On|awake|Awake) printf 'Awake' ;;
    # AOD/Doze is screen-off for scheduling. Unknown values also fail closed
    # so a vendor spelling change cannot accidentally enable foreground boost.
    0|off|OFF|Off|doze|Doze|Dozing|doze_suspend|DozeSuspend|aod|AOD|suspend|Suspended) printf 'Asleep' ;;
    *) printf 'Asleep' ;;
  esac
}
charging(){ [ "$(cat /sys/class/power_supply/usb/online 2>/dev/null)" = "1" ]; }
fg_pkg(){
  # system_server mirrors the real top-resumed package into Xiaomi's native
  # thermal contract. This avoids dumpsys/Binder access from a vendor domain.
  cat "$FG" 2>/dev/null | tr -dc 'A-Za-z0-9._'
}

# 应用 -> 场景映射：精确匹配优先，否则最长前缀通配
map_scene(){
  _pkg="$1"; _best=""; _bestlen=-1; _l=""; _pat=""; _id=""; _pre=""
  [ -f "$GAME_CONF" ] || return 1
  while IFS= read -r _l; do
    _l=$(printf '%s' "$_l" | sed 's/#.*$//; s/[[:space:]]//g')
    [ -z "$_l" ] && continue
    case "$_l" in *=*) _pat=${_l%%=*}; _id=${_l#*=} ;; *) continue ;; esac
    [ -z "$_pat" ] && continue
    case "$_pat" in
      *'*') _pre=${_pat%\*}
            case "$_pkg" in
              "$_pre"*) [ "${#_pre}" -gt "$_bestlen" ] && { _bestlen=${#_pre}; _best=$_id; } ;;
            esac ;;
      *)    [ "$_pkg" = "$_pat" ] && { _best=$_id; _bestlen=100000; } ;;
    esac
  done < "$GAME_CONF"
  [ -n "$_best" ] && { printf '%s' "$_best"; return 0; }
  return 1
}

# ---------------- 唯一写动作 ----------------
write_scene(){   # $1=目标场景  $2=原因
  _id="$1"; _why="$2"; _cur=$(cat "$SC" 2>/dev/null)
  if [ "$_cur" = "$_id" ] && [ "$OWNED" = "1" ] && [ "$SC_LAST" = "$_id" ]; then
    return 0
  fi
  if [ "$DRY" = "1" ]; then
    log "DRY: would write sconfig $_cur -> $_id ($_why)"
    return 0
  fi
  # sconfig 的文件值可能已经等于目标场景，但 mi_thermald 仍加载着旧策略表。
  # 进入场景时先切一次有效基线，再写回目标值，确保触发真实重载。
  if [ "$_cur" = "$_id" ]; then
    printf '%s' "$DEFAULT_SCENE" > "$SC" 2>/dev/null || {
      log "ERROR: 强制重载前写基线失败 (scene=$_id)"
      return 1
    }
    sleep 1
  fi
  printf '%s' "$_id" > "$SC" 2>/dev/null || { log "ERROR: 写 sconfig=$_id 失败 (cur=$_cur) -- 保持现状并回退"; return 1; }
  sleep 1
  _cur=$(cat "$SC" 2>/dev/null)
  SC_LAST=$_cur
  OWNED=1
  printf '%s\n' "$SC_LAST" > "$OWNED_FILE" 2>/dev/null || true
  log "SET scene=$_id ($_why): sconfig=$_cur $(metrics_now) dec=$(dec_bytes)B temp=$(( $(temp_mc) / 1000 ))C"
}

release_scene(){
  _why="$1"
  [ "$OWNED" = "1" ] || [ -s "$OWNED_FILE" ] || return 0
  if [ "$DRY" = "1" ]; then
    log "DRY: would release owned scene ($_why)"
    return 0
  fi
  printf '%s' "$DEFAULT_SCENE" > "$SC" 2>/dev/null || {
    log "ERROR: 恢复厂商场景失败 ($_why)"
    return 1
  }
  sleep 1
  printf '%s' "$EXIT_SCENE" > "$SC" 2>/dev/null || true
  OWNED=0
  SC_LAST=$EXIT_SCENE
  rm -f "$OWNED_FILE" 2>/dev/null
  log "RELEASE: $_why -> vendor auto (table=$DEFAULT_SCENE file=$EXIT_SCENE)"
}

managed_scene_id(){
  _wanted="$1"; _line=""; _id=""
  while IFS= read -r _line; do
    _line=$(printf '%s' "$_line" | sed 's/#.*$//')
    case "$_line" in *=*) _id=$(printf '%s' "${_line#*=}" | tr -d ' \t\r') ;; *) continue ;; esac
    [ "$_id" = "$_wanted" ] && return 0
  done < "$GAME_CONF"
  return 1
}

startup_reconcile(){
  _fg=$(fg_pkg)
  _cur=$(cat "$SC" 2>/dev/null)
  if [ -n "$_fg" ] && _id=$(map_scene "$_fg" 2>/dev/null); then
    OWNED=0
    SC_LAST=""
    write_scene "$_id" "startup-game:$_fg"
  elif managed_scene_id "$_cur"; then
    # 兼容旧版本：守护重启后内存 OWNED 丢失，但游戏场景仍残留。
    OWNED=1
    SC_LAST=$_cur
    printf '%s\n' "$_cur" > "$OWNED_FILE" 2>/dev/null || true
    release_scene "startup-stale:${_fg:-none}"
  fi
}

# ---------------- 一轮决策 ----------------
run_once(){
  read_cfg
  _t=$(temp_mc)
  case "$_t" in ''|*[!0-9-]*) _t=0; log "WARN: 读不到 board_sensor_temp，按回退处理" ;; esac

  # 安全熔断（迟滞：>= HARD 熔断，<= COOL 解除）
  if [ "$COOLDOWN" = "1" ]; then
    if [ "$_t" -le "$SAFE_TEMP_COOL" ]; then COOLDOWN=0; log "SAFETY: 已降到 $(( _t / 1000 ))C，解除熔断"; fi
  else
    if [ "$_t" -ge "$SAFE_TEMP_HARD" ]; then
      COOLDOWN=1
      log "SAFETY: 温度 $(( _t / 1000 ))C >= $(( SAFE_TEMP_HARD / 1000 ))C -> 放弃提频，交还厂商温控"
    fi
  fi
  [ "$_t" -ge "$SAFE_TEMP_SLEEP" ] && log "SAFETY: 温度 $(( _t / 1000 ))C >= $(( SAFE_TEMP_SLEEP / 1000 ))C 紧急"

  _req=""; WHY="auto"
  if [ "$COOLDOWN" = "1" ]; then
    WHY="cooldown($(( _t / 1000 ))C)"
  else
    _sst=$(screen_state)
    if [ "$SCREEN_OFF_AUTO" = "1" ] && [ "$_sst" != "Awake" ]; then
      WHY="screen-off(${_sst:-unknown})"
    else
      _fg=$(fg_pkg)
      if [ -n "$_fg" ] && _id=$(map_scene "$_fg"); then
        _req=$_id; WHY="game:$_fg"
        if charging && [ "$CHARGE_NO_BOOST" = "1" ]; then _req=""; WHY="charging-no-boost:$_fg"; fi
      else
        WHY="no-profile:${_fg:-none}"
      fi
      # Every app gets a short launch burst when the foreground package
      # changes. UniPerf raises the MTK Power HAL floor, while LAUNCH_SCENE
      # temporarily removes the Xiaomi thermal-table ceiling that previously
      # kept visible CPU clocks near 1.9/2.6GHz even after a successful hint.
      # A mapped game scene always takes precedence and remains active.
      _now=$(date +%s 2>/dev/null || echo 0)
      case "$_now" in ''|*[!0-9]*) _now=0 ;; esac
      if [ -n "$_fg" ] && [ "$_fg" != "$LAST_FG" ]; then
        BOOST_UNTIL=$(( _now + LAUNCH_BOOST_SEC ))
        LAST_FG=$_fg
        if ! map_scene "$_fg" >/dev/null 2>&1; then
          _req=$LAUNCH_SCENE
          WHY="launch-combined:${_fg}(scene=$LAUNCH_SCENE,${LAUNCH_BOOST_SEC}s)"
        fi
      elif [ -n "$_fg" ] && [ "$_now" -lt "$BOOST_UNTIL" ] && ! map_scene "$_fg" >/dev/null 2>&1; then
        _req=$LAUNCH_SCENE
        WHY="launch-combined:${_fg}(remain=$((BOOST_UNTIL-_now))s)"
      fi
    fi
  fi

  if [ -n "$_req" ]; then
    write_scene "$_req" "$WHY"
  else
    release_scene "$WHY"
  fi
}

# ---------------- 状态 ----------------
print_status(){
  _fg=$(fg_pkg); _sc=$(cat "$SC" 2>/dev/null); _t=$(temp_mc)
  echo "===== K90 Max 性能桥 (Layer A) 状态 ====="
  echo "开关        : $([ -f "$MARK/disable_perf" ] && echo '已关闭 (disable_perf 存在)' || echo '运行中')"
  echo "守护 PID    : $(cat "$PIDF" 2>/dev/null || echo '-')"
  echo "sconfig     : $_sc   (decrypt.txt=$(dec_bytes)B)"
  echo "硬件回读    : $(metrics_now)"
  echo "皮肤温度    : $(( _t / 1000 ))C ($_t mC, board_sensor_temp)"
  echo "前台应用    : ${_fg:-未知}"
  if _m=$(map_scene "$_fg" 2>/dev/null); then echo "匹配档位    : sconfig=$_m"; else echo "匹配档位    : 无 -> 交还厂商(auto)"; fi
  echo "屏幕/充电   : $(screen_state) / $(charging && echo 充电中 || echo 电池)"
  echo "运行参数    : poll=${POLL_SEC}s launch=${LAUNCH_SCENE}/${LAUNCH_BOOST_SEC}s hard=${SAFE_TEMP_HARD} cool=${SAFE_TEMP_COOL} default=${DEFAULT_SCENE} cooldown=${COOLDOWN}"
  echo "策略表大小  : $(profile_count) 条"
  echo "限频持有者  : $(cat /proc/mtk_freq_qos/max_dominant 2>/dev/null | sed -n '2p' | tr -s ' ')"
  echo "-- 映射表 --"; grep -vE '^\s*(#|$)' "$GAME_CONF" 2>/dev/null | head -20
  echo "-- 最近日志 --"; tail -8 "$LOG" 2>/dev/null
}

restore(){
  _cur=$(cat "$SC" 2>/dev/null)
  [ "$OWNED" = "1" ] || [ -s "$OWNED_FILE" ] || { rm -f "$PIDF" 2>/dev/null; return 0; }
  if [ "$DRY" = "1" ]; then
    log "DRY: 退出回退（策略表->$DEFAULT_SCENE，文件->$EXIT_SCENE，当前文件=$_cur）"
    return 0
  fi
  # 两步回退（实测语义，见 README「-1 不触发重载」）：
  #   1) 写一个「有效场景 id」(0 = BAT_SOC 厂商自动基线) -> mi_thermald 立刻重载策略表
  #   2) 再把文件写回开机默认值 -1 -> -1 不触发重载，所以生效的表仍是自动表
  printf '%s' "$DEFAULT_SCENE" > "$SC" 2>/dev/null
  sleep 2
  printf '%s' "$EXIT_SCENE" > "$SC" 2>/dev/null
  log "EXIT: 已交还厂商 (was=$_cur, 表=$DEFAULT_SCENE, 文件=$EXIT_SCENE, dec=$(dec_bytes)B caps$(caps_now))"
  rm -f "$OWNED_FILE" 2>/dev/null
  rm -f "$PIDF" 2>/dev/null
}

MODE=run; DRY=0; TEST_PKG=""
case "$1" in
  --status) MODE=status ;;
  --once)   MODE=once ;;
  --dry)    MODE=once; DRY=1 ;;
  --test)   MODE=test; TEST_PKG="$2" ;;
  --help|-h) sed -n '2,50p' "$0"; exit 0 ;;
esac

read_cfg
if [ -s "$OWNED_FILE" ]; then
  _owned=$(tr -d ' \t\r\n' < "$OWNED_FILE" 2>/dev/null)
  case "$_owned" in ''|*[!0-9-]*) rm -f "$OWNED_FILE" 2>/dev/null ;; *) OWNED=1; SC_LAST=$_owned ;; esac
fi

# ---- 映射表只读自测（不写任何节点）----
if [ "$MODE" = "test" ]; then
  echo "===== 映射表自测（只读，不写任何节点）====="
  echo "配置文件 : $GAME_CONF"
  echo "默认场景 : $DEFAULT_SCENE (auto)"
  if [ -n "$TEST_PKG" ]; then _list="$TEST_PKG"
  else _list=$(sed -n 's/#.*$//; s/[[:space:]]//g; /^$/d; s/=.*//p' "$GAME_CONF" 2>/dev/null); fi
  _n=0; _ok=0
  for _p in $_list; do
    _n=$((_n + 1))
    if _m=$(map_scene "$_p" 2>/dev/null); then
      _ok=$((_ok + 1))
      echo "  [命中] $(printf '%-38s' "$_p") -> sconfig=$_m"
    else
      echo "  [未命中] $(printf '%-36s' "$_p") -> auto($DEFAULT_SCENE)  <== 规则可能写错"
    fi
  done
  echo "规则数=$_n 命中=$_ok"
  if [ -n "$TEST_PKG" ]; then
    if _m=$(map_scene "$TEST_PKG" 2>/dev/null); then
      echo "结论: 该应用在前台时，桥会写 sconfig=$_m"
    else
      echo "结论: 该应用不在映射表内 -> 桥保持 auto($DEFAULT_SCENE)，不提频"
    fi
  fi
  echo "-- 当前表内容 --"; grep -vE '^[[:space:]]*(#|$)' "$GAME_CONF" 2>/dev/null
  echo "-- 表中最大档位实测参考 --"
  echo "   0=BAT_SOC auto dec6254B caps1500000/1700000/1850000"
  echo "   19=MGAME dec3618B caps1400000/1900000/2300000"
  echo "   20=YUANSHEN dec3705B caps1800000/1900000/2300000 (8线程负载下 cur 2200000/2700000/3050000)"
  exit 0
fi

case "$MODE" in
  status) print_status; exit 0 ;;
esac

if [ "$MODE" = "once" ]; then
  if [ -f "$MARK/disable_perf" ]; then echo "已关闭 (disable_perf)"; exit 0; fi
  _fg=$(fg_pkg); echo "前台: ${_fg:-未知}  温度: $(( $(temp_mc) / 1000 ))C  sconfig=$(cat $SC 2>/dev/null)"
  if _m=$(map_scene "$_fg" 2>/dev/null); then echo "映射: sconfig=$_m"; else echo "映射: 无 (交还厂商 $DEFAULT_SCENE)"; fi
  [ "$DRY" = "1" ] && echo "模式: DRY (不写入)"
  run_once
  echo "结果: sconfig=$(cat $SC 2>/dev/null) caps$(caps_now) why=$WHY"
  exit 0
fi

rotate_log
echo $$ > "$PIDF"
log "daemon start: pid=$$ poll=${POLL_SEC}s launch=${LAUNCH_SCENE}/${LAUNCH_BOOST_SEC}s hard=${SAFE_TEMP_HARD} cool=${SAFE_TEMP_COOL} default=${DEFAULT_SCENE} profiles=$(profile_count) moddir=$MODDIR"
trap 'log "signal: 收尾回退"; restore; exit 0' INT TERM HUP
startup_reconcile
_i=0
while :; do
  [ -f "$MARK/disable_perf" ] && { log "disable_perf 出现 -> 停止"; break; }
  run_once
  _i=$((_i + 1))
  [ $((_i % 30)) -eq 0 ] && log "heartbeat: scene=${SC_LAST:-?} why=$WHY temp=$(( $(temp_mc) / 1000 ))C $(metrics_now)"
  sleep "$POLL_SEC"
done
restore
log "daemon stop"
exit 0
