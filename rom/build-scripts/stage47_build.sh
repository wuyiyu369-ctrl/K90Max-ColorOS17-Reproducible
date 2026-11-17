#!/bin/bash
set -e

cd /mnt/d/K90Max_ColorOS17_完整迁移_20261028/01_主工程/K90_A17_PORT_WORK

STAGE=47
BASE_STAGE=45
DESC="CPU_Final_DisableMipower"

BUILD_DIR="delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage${STAGE}_${DESC}"
BASE_DIR="delivery/K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage${BASE_STAGE}_UNIPERF_FAN"

echo "[Stage${STAGE}] Start build"
echo "Base: ${BASE_DIR}"
echo "Target: ${BUILD_DIR}"

mkdir -p "${BUILD_DIR}"
if [ -f "${BASE_DIR}/super.img" ]; then
    cp "${BASE_DIR}/super.img" "${BUILD_DIR}/"
fi
if [ -d "${BASE_DIR}/platform-tools" ]; then
    cp -r "${BASE_DIR}/platform-tools" "${BUILD_DIR}/"
fi

echo "Done"
