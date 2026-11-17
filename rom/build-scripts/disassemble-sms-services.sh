#!/bin/bash
set -euo pipefail
cpj='/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/jars3/smali-dexlib2-3.0.10.jar:/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/jars3/smali-util-3.0.10.jar:/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/jars3/smali-baksmali-3.0.10.jar:/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/jars3/smali-3.0.10.jar:/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/lspwork/guava-31.1-jre.jar:/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/jars/jc.jar:/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/jars/antlr.jar'
rm -rf /root/sms_services_diff
mkdir -p /root/sms_services_diff/base /root/sms_services_diff/mod
java -cp "$cpj" com.android.tools.smali.baksmali.Main disassemble --api 34 \
  '/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/trees/pmb_system/system/framework/services.jar' -o /root/sms_services_diff/base
java -cp "$cpj" com.android.tools.smali.baksmali.Main disassemble --api 34 \
  '/mnt/d/K90Max_ColorOS17_完整迁移_20261028/07_桌面与社区资料/D盘桌面/55/fan-work/module/k90max_fix_ksu/jars/services.jar' -o /root/sms_services_diff/mod
grep -RIlE 'sms_default_application|com\\.android\\.mms|SmsManager|SMS_DELIVER|InvalidImei' /root/sms_services_diff/mod | sort > /root/sms_services_diff/sms_mod_hits.txt || true
grep -RIlE 'sms_default_application|com\\.android\\.mms|SmsManager|SMS_DELIVER|InvalidImei' /root/sms_services_diff/base | sort > /root/sms_services_diff/sms_base_hits.txt || true
wc -l /root/sms_services_diff/*_hits.txt
