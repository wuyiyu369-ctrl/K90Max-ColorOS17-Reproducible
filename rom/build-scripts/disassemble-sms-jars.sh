#!/bin/bash
set -euo pipefail
cpj='/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/jars3/smali-dexlib2-3.0.10.jar:/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/jars3/smali-util-3.0.10.jar:/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/jars3/smali-baksmali-3.0.10.jar:/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/jars3/smali-3.0.10.jar:/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/lspwork/guava-31.1-jre.jar:/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/jars/jc.jar:/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR/jars/antlr.jar'
rm -rf /root/sms_diff
mkdir -p /root/sms_diff/base /root/sms_diff/mod
java -cp "$cpj" com.android.tools.smali.baksmali.Main disassemble --api 34 \
  '/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK/trees/pmb_system/system/framework/telephony-common.jar' -o /root/sms_diff/base
java -cp "$cpj" com.android.tools.smali.baksmali.Main disassemble --api 34 \
  '/mnt/d/K90Max_ColorOS17_完整迁移_20261028/07_桌面与社区资料/D盘桌面/55/fan-work/module/k90max_fix_ksu/jars/telephony-common.jar' -o /root/sms_diff/mod
find /root/sms_diff/base -type f | wc -l
find /root/sms_diff/mod -type f | wc -l
