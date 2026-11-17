#!/system/bin/sh

STATE=/data/adb/k90max-radio-fix
LOG="$STATE/manual-action-v2.log"
mkdir -p "$STATE" 2>/dev/null

echo "$(date '+%Y-%m-%d %H:%M:%S') manual recovery requested" >> "$LOG"
rm -f "$STATE/last_boot_id"

# Launch the same guarded implementation once in the background.
MODDIR=${0%/*}
sh "$MODDIR/service.sh" >> "$LOG" 2>&1 &
echo "已开始一轮入网强恢复，请等待约 4 分钟；日志：$STATE/service-v2.log"
