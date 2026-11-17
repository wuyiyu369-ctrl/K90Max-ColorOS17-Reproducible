#!/bin/bash
set -euo pipefail

# Stage47: 禁用 mipower_hal，解决 CPU 性能限制
# 基于 Stage45，只修改 ODM 添加禁用 mipower_hal 的 RC

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028
base=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage45_UNIPERF_FAN
delivery=$root/01_主工程/K90_A17_PORT_WORK/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage47_CPU_Final_DisableMipower
work=$root/02_Codex完整工作区/wo/stage47_work
overlay=/root/k90_stage47_overlay

cleanup(){
    for n in verify odm_merged odm_lower; do
        mountpoint -q "$overlay/$n" && umount "$overlay/$n" || true
    done
}
trap cleanup EXIT

# 创建工作目录
mkdir -p "$work/out" "$overlay"/{odm_lower,odm_upper,odm_work,verify}

# 提取 Stage45 的 ODM 分区
echo "[Stage47] 从 Stage45 super.img 提取 ODM..."
if [ ! -f "$work/out/odm.base.img" ]; then
    # ODM 在 super 中的偏移：10217 MB (根据 stage45_resume.sh)
    dd if="$base/images/super.img" of="$work/out/odm.base.img" bs=1M skip=10217 count=6000 status=progress
fi

# 挂载基础 ODM
mount -t erofs -o ro,loop "$work/out/odm.base.img" "$overlay/odm_lower"

# 创建 overlay
mount -t overlay overlay -o "lowerdir=$overlay/odm_lower,upperdir=$overlay/odm_upper,workdir=$overlay/odm_work" "$overlay/odm_merged"

# 添加禁用 mipower_hal 的 RC
echo "[Stage47] 添加 k90_disable_mipower.rc..."
cat > "$overlay/odm_merged/etc/init/k90_disable_mipower.rc" << 'EOF'
# Stage47: Disable mipower_hal to allow K90 native perf bridge
on boot
    stop mipower_hal
    setprop ctl.stop vendor.mipower_hal

on property:sys.boot_completed=1
    stop mipower_hal
EOF

chmod 644 "$overlay/odm_merged/etc/init/k90_disable_mipower.rc"
chown root:root "$overlay/odm_merged/etc/init/k90_disable_mipower.rc"

# 验证文件已添加
test -f "$overlay/odm_merged/etc/init/k90_disable_mipower.rc"

# 打包 ODM (使用与 Stage45 相同的参数)
echo "[Stage47] 打包 ODM..."
mkfs.erofs -z lz4hc,12 -C 65536 \
    -T "$(stat -c%Y "$work/out/odm.base.img")" \
    -U "$(blkid -o value -s UUID "$work/out/odm.base.img")" \
    --preserve-mtime \
    "$work/out/odm.img" \
    "$overlay/odm_merged"

# 验证打包
fsck.erofs "$work/out/odm.img" > "$work/out/fsck-odm.txt" 2>&1
mount -t erofs -o ro,loop "$work/out/odm.img" "$overlay/verify"
test -f "$overlay/verify/etc/init/k90_disable_mipower.rc"
umount "$overlay/verify"

# 复制 Stage45 的 super.img 并替换 ODM
echo "[Stage47] 构建 super.img..."
mkdir -p "$delivery/images"
cp --sparse=always "$base/images/super.img" "$delivery/images/super.img.building"
dd if="$work/out/odm.img" of="$delivery/images/super.img.building" bs=1M seek=10217 conv=notrunc,fsync status=progress
mv "$delivery/images/super.img.building" "$delivery/images/super.img"

# 复制刷机工具
cp -a "$base/platform-tools" "$delivery/"
cp "$base/FLASH_KEEP_DATA.ps1" "$base/START_UPDATE.cmd" "$delivery/"

# 生成审计日志
mkdir -p "$delivery/audit"
cp "$work/out/fsck-odm.txt" "$delivery/audit/"
cat > "$delivery/audit/stage47_changes.txt" << 'EOF'
Stage47 修改内容：

1. 基于 Stage45
2. 修改 ODM 分区：
   - 添加 /odm/etc/init/k90_disable_mipower.rc
   - 作用：开机时禁用 mipower_hal
3. 原因：mipower_hal 持续限制 CPU 频率，与 k90_perf_bridge.sh 冲突
4. 预期效果：CPU 可达物理最大频率 2.7/3.5/4.21 GHz
EOF

echo "[Stage47] 构建完成: $delivery"
