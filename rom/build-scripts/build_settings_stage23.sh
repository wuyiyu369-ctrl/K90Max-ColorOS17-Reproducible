set -e
j=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/06_WSL关键产物_虚拟磁盘不迁移/工具JAR
cp="$j/jars3/smali-dexlib2-3.0.10.jar:$j/jars3/smali-util-3.0.10.jar:$j/jars3/smali-baksmali-3.0.10.jar:$j/jars3/smali-3.0.10.jar:$j/lspwork/guava-31.1-jre.jar:$j/jars/jc.jar:$j/jars/antlr.jar"
src=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/Settings_A17_dec/smali_classes14
out=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo/Settings_classes14_stage23.dex
java -cp "$cp" com.android.tools.smali.smali.Main assemble --api 34 "$src" -o "$out"
java -cp "$cp" com.android.tools.smali.baksmali.Main disassemble --api 34 "$out" -o /tmp/settings_stage23_verify
rg -n '一加 Ace 6 至尊版' /tmp/settings_stage23_verify/com/oplus/settings/utils/AboutPhoneDisplayUtils.smali
