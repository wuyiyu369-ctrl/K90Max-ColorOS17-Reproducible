#!/system/bin/sh

ui_print "***************************************"
ui_print " K90 Max ColorOS 17 入网强恢复 v2.1"
ui_print "***************************************"

SKU="$(getprop ro.boot.product.hardware.sku)"
PLATFORM="$(getprop ro.board.platform)"
if [ "$SKU" != "prague" ] || [ "$PLATFORM" != "mt6993" ]; then
  abort "机型校验失败：仅支持 prague / MT6993，当前为 $SKU / $PLATFORM"
fi

ui_print "- 机型校验通过：prague / MT6993"
ui_print "- 不会写入基带、IMEI、NV 或 persist 分区"
ui_print "- 每次开机最多执行一轮，不会无限重启"
ui_print "- 诊断日志保存到 /data/adb/k90max-radio-fix/"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
