#!/usr/bin/env bash
set -euo pipefail

mount_root=/root/stage54_deps
odm=/root/stage54_inspect/odm53.img
mkdir -p "$mount_root"
mount -t erofs -o ro,loop "$odm" "$mount_root"

for lib in \
  libbase.so \
  libcutils.so \
  liblog.so \
  libbinder_ndk.so \
  libprocessgroup.so \
  libutils.so \
  libcrypto.so \
  android.frameworks.stats-V1-ndk.so \
  libxml2.so \
  libprotobuf-cpp-lite-21.12.so \
  libc++.so; do
  if [ -e "$mount_root/lib64/$lib" ]; then
    echo "ODM $lib"
  elif [ -e "$mount_root/lib/$lib" ]; then
    echo "ODM32 $lib"
  else
    echo "MISSING_ODM $lib"
  fi
done

for lib in liburcccore.so; do
  f="$mount_root/lib64/$lib"
  if [ -e "$f" ]; then
    echo "EXISTING_$lib"
    readelf -d "$f" | sed -n 's/.*NEEDED.*\[\(.*\)\]/NEEDED \1/p'
  fi
done

umount "$mount_root"
