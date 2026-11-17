#!/usr/bin/env bash
set -euo pipefail

src=/mnt/c/Users/USERNAME/Documents/Codex/2026-10-08/wo
root=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK
base=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage76_NANDSWAP_CARRIER
out=$root/delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage78_FIXED
patch_root=/mnt/d/K90_AOD_STAGE75_WORK/stage78_jars
donor_odm=$root/trees/pmb_odm
donor=$donor_odm/lib64
work=/root/k90_stage78_work
overlay=/root/k90_stage78_overlay
avb=/mnt/d/K90Max_ColorOS17_完整迁移_20261028/02_Codex完整工作区/wo/tools/avb/avbtool.py

super_size=13421772800
system_offset=1048576
system_erofs_size=1049554944
system_partition_size=1061134336
system_end=$((system_offset + system_partition_size))
my_manifest_offset=$((4499456 * 512))
my_manifest_size=$((1152 * 512))
my_manifest_end=$((my_manifest_offset + my_manifest_size))
odm_offset=$((20924416 * 512))
odm_size=$((3368224 * 512))
odm_end=$((odm_offset + odm_size))
base_hash=967fba34a0c3e27ea5db53fc3d674c855b9a3edd2f64887c098b351d4fc2673c
base_telephony=cc0e18e7ba9e18a828526a462d6dbb7daeca998091fd56efb8f1aaee04f61a33
base_oplus=fff57869c365ee60ea1f697b965a7740cedddae70a2cce76ba318633a065882a
service_hash=c358a3af55705624d1bdf211d8e7163ced33b35116ccec663aee65461de64ad7
wire_hash=3f651fcc423db6532ac8e5c3f5f580deb89ba35e579befa8fe82f87619f793e0

base_super=$base/images/super.img
telephony_jar=$patch_root/telephony-common.stage78.jar
oplus_jar=$patch_root/oplus-services.stage78.jar
perf_service=$donor_odm/bin/hw/vendor-oplus-hardware-performance-V1-service
wire=$donor_odm/lib64/vendor.oplus.hardware.performance-V5-ndk.so

for tool in mkfs.erofs fsck.erofs getfattr setfattr readelf sha256sum cmp blkid; do
  command -v "$tool" >/dev/null
done
for file in "$base_super" "$telephony_jar" "$oplus_jar" "$perf_service" "$wire" "$avb" \
            "$src/stage62_policy_patch.c" \
            "$src/generate_erofs_file_contexts.py"; do
  test -s "$file" || { echo "MISSING: $file" >&2; exit 1; }
done
test "$(stat -c%s "$base_super")" -eq "$super_size"
test "$(sha256sum "$base_super" | cut -d' ' -f1)" = "$base_hash"
test "$(sha256sum "$perf_service" | cut -d' ' -f1)" = "$service_hash"
test "$(sha256sum "$wire" | cut -d' ' -f1)" = "$wire_hash"

rm -rf "$work" "$overlay" "$out"
mkdir -p "$work/out" "$work/policy" "$overlay" "$out"/{images,audit}
for part in system manifest odm; do
  mkdir -p "$overlay/$part"/{lower,upper,work,merged,verify}
done

cleanup() {
  for p in "$work/policy"/{odm_candidate,odm_base,vendor,product,system_ext,system}; do
    mountpoint -q "$p" && umount "$p" || true
  done
  for part in system manifest odm; do
    for name in verify merged lower; do
      mountpoint -q "$overlay/$part/$name" && umount "$overlay/$part/$name" || true
    done
  done
}
trap cleanup EXIT

# Use the PMB110 donor's own stable-AIDL V5 server/wire pair. ColorOS clients
# link V1, while the donor compatibility matrix explicitly accepts versions 1-5.
readelf -d "$perf_service" > "$work/out/performance.readelf-dynamic.txt"
grep -q 'Shared library: \[vendor.oplus.hardware.performance-V5-ndk.so\]' \
  "$work/out/performance.readelf-dynamic.txt"
grep -q 'Shared library: \[libc++.so\]' "$work/out/performance.readelf-dynamic.txt"
! grep -q 'libc++_shared.so' "$work/out/performance.readelf-dynamic.txt"
grep -a -q 'vendor.oplus.hardware.performance.IPerformance' "$wire"

# Patch the boot policy with the exact client domains observed in Stage76.
cc -O2 -Wall -Wextra -Werror \
  -I"$src/stage44_toolchain_source/selinux-main/libsepol/include" \
  -o "$work/out/stage78_policy_patch" "$src/stage62_policy_patch.c" \
  "$src/stage44_toolchain_source/selinux-main/libsepol/src/libsepol.a"

# Extract the three bounded extents from the booted Stage76 baseline.
dd if="$base_super" of="$work/out/system.base.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$system_offset" count="$system_partition_size" status=none
dd if="$base_super" of="$work/out/my_manifest.base.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$my_manifest_offset" count="$my_manifest_size" status=none
dd if="$base_super" of="$work/out/odm.base.img" bs=16M \
  iflag=skip_bytes,count_bytes skip="$odm_offset" count="$odm_size" status=none
for part in system my_manifest odm; do
  fsck.erofs "$work/out/$part.base.img" > "$work/out/fsck-$part-base.txt" 2>&1
done
python3 "$avb" info_image --image "$work/out/system.base.img" \
  > "$work/out/avb-system-base.txt"

# SYSTEM: replace only telephony-common.jar and oplus-services.jar.
mount -t erofs -o ro,loop "$work/out/system.base.img" "$overlay/system/lower"
test "$(sha256sum "$overlay/system/lower/system/framework/telephony-common.jar" | cut -d' ' -f1)" = "$base_telephony"
test "$(sha256sum "$overlay/system/lower/system/framework/oplus-services.jar" | cut -d' ' -f1)" = "$base_oplus"
setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/system/lower")" \
  "$overlay/system/upper"
mkdir -p "$overlay/system/upper/system/framework"
for rel in system system/framework; do
  chmod --reference="$overlay/system/lower/$rel" "$overlay/system/upper/$rel"
  chown --reference="$overlay/system/lower/$rel" "$overlay/system/upper/$rel"
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/system/lower/$rel")" \
    "$overlay/system/upper/$rel"
done
for pair in "telephony-common.jar:$telephony_jar" "oplus-services.jar:$oplus_jar"; do
  name=${pair%%:*}; source=${pair#*:}
  cp --preserve=all "$overlay/system/lower/system/framework/$name" \
    "$overlay/system/upper/system/framework/$name"
  dd if="$source" of="$overlay/system/upper/system/framework/$name" status=none
done
mount -t overlay overlay \
  -o "lowerdir=$overlay/system/lower,upperdir=$overlay/system/upper,workdir=$overlay/system/work" \
  "$overlay/system/merged"
python3 "$src/generate_erofs_file_contexts.py" "$overlay/system/merged" /system \
  "$work/out/system_file_contexts" --override /system/my_reserve=u:object_r:system_file:s0 \
  > "$work/out/system-contexts.txt"
system_uuid=$(blkid -o value -s UUID "$work/out/system.base.img")
system_label=$(blkid -o value -s LABEL "$work/out/system.base.img" || true)
system_args=(-z lz4hc,12 -C 16384 -T 1791277125 -U "$system_uuid" --preserve-mtime \
  --mount-point=/system --file-contexts="$work/out/system_file_contexts")
[[ -z "$system_label" ]] || system_args+=(-L "$system_label")
mkfs.erofs "${system_args[@]}" "$work/out/system.raw.img" "$overlay/system/merged" \
  > "$work/out/mkfs-system.log" 2>&1
test "$(stat -c%s "$work/out/system.raw.img")" -le "$system_erofs_size"
cp --sparse=always "$work/out/system.raw.img" "$work/out/system.img"
truncate -s "$system_erofs_size" "$work/out/system.img"
python3 "$avb" add_hashtree_footer --image "$work/out/system.img" \
  --partition_size "$system_partition_size" --partition_name system \
  --hash_algorithm sha256 --salt e25ce9d868f66f3acadc4cd9388398d9 \
  --block_size 4096 --do_not_generate_fec --algorithm NONE \
  --prop com.android.build.oplus_custom_images.os_version:11 \
  --prop com.android.build.oplus_custom_images.security_patch:2020-10-05
python3 "$avb" verify_image --image "$work/out/system.img" > "$work/out/avb-system.txt"
fsck.erofs "$work/out/system.img" > "$work/out/fsck-system.txt" 2>&1
umount "$overlay/system/merged"
umount "$overlay/system/lower"

# MY_MANIFEST: replace the original model value; do not append a duplicate.
mount -t erofs -o ro,loop "$work/out/my_manifest.base.img" "$overlay/manifest/lower"
setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/manifest/lower")" \
  "$overlay/manifest/upper"
mount -t overlay overlay \
  -o "lowerdir=$overlay/manifest/lower,upperdir=$overlay/manifest/upper,workdir=$overlay/manifest/work" \
  "$overlay/manifest/merged"
prop="$overlay/manifest/merged/build.prop"
test "$(grep -c '^ro.product.model=' "$prop")" -eq 1
sed -i 's/^ro\.product\.model=.*/ro.product.model=一加 Ace 6 至尊版/' "$prop"
cp --attributes-only --preserve=all "$overlay/manifest/lower/build.prop" \
  "$overlay/manifest/upper/build.prop"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 \
  "$overlay/manifest/upper/build.prop"
python3 "$src/generate_erofs_file_contexts.py" "$overlay/manifest/merged" /my_manifest \
  "$work/out/my_manifest_file_contexts" \
  --override /my_manifest/build.prop=u:object_r:vendor_file:s0 \
  > "$work/out/my_manifest-contexts.txt"
manifest_uuid=$(blkid -o value -s UUID "$work/out/my_manifest.base.img")
manifest_label=$(blkid -o value -s LABEL "$work/out/my_manifest.base.img" || true)
manifest_args=(-z lz4hc,12 -C 65536 -T 1791306550 -U "$manifest_uuid" --preserve-mtime \
  --mount-point=/my_manifest --file-contexts="$work/out/my_manifest_file_contexts")
[[ -z "$manifest_label" ]] || manifest_args+=(-L "$manifest_label")
mkfs.erofs "${manifest_args[@]}" "$work/out/my_manifest.raw.img" \
  "$overlay/manifest/merged" > "$work/out/mkfs-my_manifest.log" 2>&1
test "$(stat -c%s "$work/out/my_manifest.raw.img")" -le "$my_manifest_size"
cp --sparse=always "$work/out/my_manifest.raw.img" "$work/out/my_manifest.img"
truncate -s "$my_manifest_size" "$work/out/my_manifest.img"
umount "$overlay/manifest/merged"
umount "$overlay/manifest/lower"
fsck.erofs "$work/out/my_manifest.img" > "$work/out/fsck-my_manifest.txt" 2>&1

# ODM: install the PMB110 donor IPerformance V5 server/wire pair and include only
# MT6993 PMB110 AI runtime candidates. Existing fan, URCC, camera and linker
# files remain the Stage76 lower tree.
mount -t erofs -o ro,loop "$work/out/odm.base.img" "$overlay/odm/lower"
test "$(getfattr -n security.selinux --only-values "$overlay/odm/lower/lib64/libc++_shared.so")" = u:object_r:vendor_file:s0
setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/odm/lower")" \
  "$overlay/odm/upper"
for rel in bin bin/hw lib64 etc etc/selinux etc/vintf etc/vintf/manifest; do
  mkdir -p "$overlay/odm/upper/$rel"
  chmod --reference="$overlay/odm/lower/$rel" "$overlay/odm/upper/$rel"
  chown --reference="$overlay/odm/lower/$rel" "$overlay/odm/upper/$rel"
  setfattr -n security.selinux \
    -v "$(getfattr -n security.selinux --only-values "$overlay/odm/lower/$rel")" \
    "$overlay/odm/upper/$rel"
done
mkdir -p "$overlay/odm/upper/lib64/aiframe"
chmod 0755 "$overlay/odm/upper/lib64/aiframe"
chown 0:0 "$overlay/odm/upper/lib64/aiframe"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$overlay/odm/upper/lib64/aiframe"

perf_rel=bin/hw/vendor-oplus-hardware-performance-V1-service
cp --preserve=all "$overlay/odm/lower/$perf_rel" "$overlay/odm/upper/$perf_rel"
dd if="$perf_service" of="$overlay/odm/upper/$perf_rel" status=none
setfattr -n security.selinux -v u:object_r:vendor_touch_init_shell_exec:s0 \
  "$overlay/odm/upper/$perf_rel"
install -m 0644 "$wire" \
  "$overlay/odm/upper/lib64/vendor.oplus.hardware.performance-V5-ndk.so"
chown 0:0 "$overlay/odm/upper/lib64/vendor.oplus.hardware.performance-V5-ndk.so"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 \
  "$overlay/odm/upper/lib64/vendor.oplus.hardware.performance-V5-ndk.so"

perf_manifest=etc/vintf/manifest/manifest_performance_aidl.xml
cp --preserve=all "$overlay/odm/lower/$perf_manifest" "$overlay/odm/upper/$perf_manifest"
python3 - "$overlay/odm/upper/$perf_manifest" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text()
old = '<version>2</version>'
if t.count(old) != 1:
    raise SystemExit('unexpected IPerformance manifest version')
p.write_text(t.replace(old, '<version>5</version>'))
PY
setfattr -n security.selinux \
  -v "$(getfattr -n security.selinux --only-values "$overlay/odm/lower/$perf_manifest")" \
  "$overlay/odm/upper/$perf_manifest"

: > "$work/out/ai-runtime-candidates.txt"
for file in "$donor"/libaiboost*.so "$donor"/aiframe/*.so; do
  test -f "$file"
  if [[ "$file" == */aiframe/* ]]; then
    dest="$overlay/odm/upper/lib64/aiframe/$(basename "$file")"
  else
    dest="$overlay/odm/upper/lib64/$(basename "$file")"
  fi
  install -m 0644 "$file" "$dest"
  chown 0:0 "$dest"
  setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$dest"
  printf '%s  %s\n' "$(sha256sum "$file" | cut -d' ' -f1)" "${dest#"$overlay/odm/upper"}" \
    >> "$work/out/ai-runtime-candidates.txt"
done

"$work/out/stage78_policy_patch" \
  "$overlay/odm/lower/etc/selinux/precompiled_sepolicy" \
  "$overlay/odm/upper/etc/selinux/precompiled_sepolicy" \
  > "$work/out/policy-patch.txt"
cp --preserve=all "$overlay/odm/lower/etc/selinux/odm_sepolicy.cil" \
  "$overlay/odm/upper/etc/selinux/odm_sepolicy.cil"
cat >> "$overlay/odm/upper/etc/selinux/odm_sepolicy.cil" <<'EOF'
; Stage78 exact IPerformance/IUrcc client denials observed on Stage76.
(allow audioserver hal_power_service (service_manager (find)))
(allow audioserver vendor_touch_init_shell (binder (call transfer)))
(allow vendor_touch_init_shell audioserver (binder (transfer)))
(typeattributeset hal_power_client (oplus_game_service))
(allow oplus_game_service vendor_touch_init_shell (binder (call transfer)))
(allow vendor_touch_init_shell oplus_game_service (binder (transfer)))
EOF
setfattr -n security.selinux -v u:object_r:sepolicy_file:s0 \
  "$overlay/odm/upper/etc/selinux/precompiled_sepolicy"
setfattr -n security.selinux -v u:object_r:sepolicy_file:s0 \
  "$overlay/odm/upper/etc/selinux/odm_sepolicy.cil"

# Explicitly preserve the camera-critical library and its corrected label.
cp -a "$overlay/odm/lower/lib64/libc++_shared.so" \
  "$overlay/odm/upper/lib64/libc++_shared.so"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 \
  "$overlay/odm/upper/lib64/libc++_shared.so"

mount -t overlay overlay \
  -o "lowerdir=$overlay/odm/lower,upperdir=$overlay/odm/upper,workdir=$overlay/odm/work" \
  "$overlay/odm/merged"
python3 "$src/generate_erofs_file_contexts.py" "$overlay/odm/merged" /odm \
  "$work/out/odm_file_contexts" \
  --override /odm/bin/hw/vendor-oplus-hardware-performance-V1-service=u:object_r:vendor_touch_init_shell_exec:s0 \
  --override /odm/lib64/vendor.oplus.hardware.performance-V5-ndk.so=u:object_r:vendor_file:s0 \
  --override /odm/lib64/libc++_shared.so=u:object_r:vendor_file:s0 \
  --override /odm/etc/selinux/precompiled_sepolicy=u:object_r:sepolicy_file:s0 \
  --override /odm/etc/selinux/odm_sepolicy.cil=u:object_r:sepolicy_file:s0 \
  > "$work/out/odm-contexts.txt"
odm_uuid=$(blkid -o value -s UUID "$work/out/odm.base.img")
odm_label=$(blkid -o value -s LABEL "$work/out/odm.base.img" || true)
odm_args=(-z lz4hc,12 -C 16384 -T 1791306550 -U "$odm_uuid" --preserve-mtime \
  --mount-point=/odm --file-contexts="$work/out/odm_file_contexts")
[[ -z "$odm_label" ]] || odm_args+=(-L "$odm_label")
mkfs.erofs "${odm_args[@]}" "$work/out/odm.raw.img" "$overlay/odm/merged" \
  > "$work/out/mkfs-odm.log" 2>&1
test "$(stat -c%s "$work/out/odm.raw.img")" -le "$odm_size"
cp --sparse=always "$work/out/odm.raw.img" "$work/out/odm.img"
truncate -s "$odm_size" "$work/out/odm.img"
umount "$overlay/odm/merged"
umount "$overlay/odm/lower"
fsck.erofs "$work/out/odm.img" > "$work/out/fsck-odm.txt" 2>&1

# Verify rebuilt extents and require every file/directory to carry a label.
for spec in system:system.img manifest:my_manifest.img odm:odm.img; do
  part=${spec%%:*}; image=${spec#*:}
  mount -t erofs -o ro,loop "$work/out/$image" "$overlay/$part/verify"
  missing=0
  while IFS= read -r -d '' item; do
    getfattr -n security.selinux --only-values "$item" >/dev/null 2>&1 || missing=$((missing + 1))
  done < <(find "$overlay/$part/verify" -xdev \( -type f -o -type d \) -print0)
  echo "$missing" > "$work/out/missing-selinux-labels-$part.txt"
  test "$missing" -eq 0
  case "$part" in
    system)
      cmp "$telephony_jar" "$overlay/$part/verify/system/framework/telephony-common.jar"
      cmp "$oplus_jar" "$overlay/$part/verify/system/framework/oplus-services.jar"
      ;;
    manifest)
      test "$(grep -c '^ro.product.model=' "$overlay/$part/verify/build.prop")" -eq 1
      grep -q '^ro.product.model=一加 Ace 6 至尊版$' "$overlay/$part/verify/build.prop"
      ;;
    odm)
      cmp "$perf_service" "$overlay/$part/verify/$perf_rel"
      cmp "$wire" "$overlay/$part/verify/lib64/vendor.oplus.hardware.performance-V5-ndk.so"
      grep -q '<version>5</version>' "$overlay/$part/verify/$perf_manifest"
      test "$(getfattr -n security.selinux --only-values "$overlay/$part/verify/lib64/libc++_shared.so")" = u:object_r:vendor_file:s0
      grep -q '^allow audioserver vendor_touch_init_shell:binder { call transfer };$' \
        "$work/out/policy-patch.txt"
      grep -q '^(allow oplus_game_service vendor_touch_init_shell (binder (call transfer)))$' \
        "$overlay/$part/verify/etc/selinux/odm_sepolicy.cil"
      ;;
  esac
  umount "$overlay/$part/verify"
done

# Assemble Stage78 and prove all bytes outside the three replaced extents are
# exactly identical to Stage76.
building=$out/images/super.img.building
cp --sparse=always "$base_super" "$building"
dd if="$work/out/system.img" of="$building" bs=4096 \
  seek=$((system_offset / 4096)) conv=notrunc,fsync status=progress
dd if="$work/out/my_manifest.img" of="$building" bs=4096 \
  seek=$((my_manifest_offset / 4096)) conv=notrunc,fsync status=none
dd if="$work/out/odm.img" of="$building" bs=4096 \
  seek=$((odm_offset / 4096)) conv=notrunc,fsync status=progress
test "$(stat -c%s "$building")" -eq "$super_size"
cmp -n "$system_offset" "$base_super" "$building"
cmp -n $((my_manifest_offset - system_end)) -i "$system_end:$system_end" "$base_super" "$building"
cmp -n $((odm_offset - my_manifest_end)) -i "$my_manifest_end:$my_manifest_end" "$base_super" "$building"
cmp -n $((super_size - odm_end)) -i "$odm_end:$odm_end" "$base_super" "$building"

for spec in system:$system_offset:$system_partition_size my_manifest:$my_manifest_offset:$my_manifest_size odm:$odm_offset:$odm_size; do
  name=${spec%%:*}; rest=${spec#*:}; off=${rest%%:*}; len=${rest#*:}
  dd if="$building" of="$work/out/$name.readback.img" bs=16M \
    iflag=skip_bytes,count_bytes skip="$off" count="$len" status=none
  cmp "$work/out/$name.img" "$work/out/$name.readback.img"
  fsck.erofs "$work/out/$name.readback.img" > "$work/out/fsck-$name-readback.txt" 2>&1
done
python3 "$avb" verify_image --image "$work/out/system.readback.img" \
  > "$work/out/avb-system-readback.txt"

mv "$building" "$out/images/super.img"
cp -a "$base/platform-tools" "$out/"
for file in FLASH_KEEP_DATA.ps1 START_UPDATE.cmd; do
  test ! -f "$base/$file" || cp "$base/$file" "$out/"
done
cp "$work/out/"*.txt "$work/out/"*.log "$out/audit/" 2>/dev/null || true
sha256sum "$out/images/super.img" > "$out/SHA256SUMS.txt"
sha256sum "$telephony_jar" "$oplus_jar" "$perf_service" "$wire" \
  > "$out/audit/patched-files.sha256"

cat > "$out/STATUS.txt" <<'EOF'
Stage78 corrected compatibility candidate
Base: device-booted Stage76
Changed extents: system, my_manifest and ODM only
Data wipe: authorized after a successful flash

Confirmed implementation changes:
- Carrier text preserves normal SPN/PLMN handling and localizes known mainland
  PLMNs; 46011 is displayed as China Telecom in Chinese.
- The Stage77 color-mode patch is fully removed. The Stage76 framework jar is
  restored because SurfaceFlinger IDs 7/9 are invalid framework mode values.
- ro.product.model is replaced at its original my_manifest source with the
  Chinese product name; no duplicate read-only property is appended.
- IPerformance uses the unmodified PMB110 V5 service and matching V5 wire
  library. The ColorOS compatibility matrix accepts stable AIDL versions 1-5.
- Audio/game client permissions match the concrete Stage76 denials.

Candidate integration, requiring runtime validation:
- MT6993 PMB110 AI Boost libraries are included with vendor_file labels while
  preserving K90 MTK APU/Neuron services. This does not prove that every
  optional model/backend or dlopen target is available.

Preserved from Stage76:
- Fan, URCC, camera/linker, AOD, product libc++, radio and all other extents.

Not claimed until runtime tests pass:
- Benchmark uplift, automatic brightness, 90 Hz, nandswap, full AI feature
  availability or full-screen AOD UI behavior.
EOF

echo STAGE78_BUILD_PASSED
