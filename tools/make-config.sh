#!/usr/bin/env bash
# Usage: ./tools/make-config.sh DEVICE [OPENWRT_SOURCE_DIR]
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:-}"
SRC_DIR="${2:-$PROJECT_DIR/openwrt}"
if [[ ! "$DEVICE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ || "$DEVICE" == common ]]; then
    echo "错误: 请输入有效设备名，例如: ./tools/make-config.sh 360-t7" >&2
    exit 1
fi
if [[ ! -f "$SRC_DIR/Makefile" ]]; then
    echo "错误: 未找到 OpenWrt 源码: $SRC_DIR" >&2
    echo '请先执行: git clone -b openwrt-25.12 --single-branch --depth=1 https://github.com/openwrt/openwrt.git openwrt' >&2
    exit 1
fi
DEVICE_DIR="$PROJECT_DIR/devices/$DEVICE"
mkdir -p "$DEVICE_DIR/files" "$DEVICE_DIR/patches"
SRC_DIR="$(cd "$SRC_DIR" && pwd)"
cd "$SRC_DIR"

# Updating is explicit so existing patches are never mixed with another revision.
bash "$PROJECT_DIR/tools/prepare-source.sh" "$DEVICE" "$SRC_DIR" feeds
./scripts/feeds update -a
./scripts/feeds install -a
bash "$PROJECT_DIR/tools/prepare-source.sh" "$DEVICE" "$SRC_DIR" customize

fragments=("$PROJECT_DIR/devices/common/base.config")
if [[ -f "$DEVICE_DIR/target.config" ]]; then
    fragments+=("$DEVICE_DIR/target.config")
fi
bash "$PROJECT_DIR/tools/merge-config.sh" "${fragments[@]}" > .config.requested
cp .config.requested .config
make defconfig
bash "$PROJECT_DIR/tools/validate-config.sh" .config '' .config.requested

echo "配置设备: $DEVICE"
echo '请选择目标硬件及专属软件包，保存并退出后会写入设备配置。'
read -r -p '按 Enter 打开 menuconfig...'
make menuconfig
make defconfig
bash "$PROJECT_DIR/tools/validate-config.sh" .config

TEMP_CONFIG="$(mktemp "$DEVICE_DIR/.target.config.XXXXXX")"
TEMP_DIFF="$(mktemp)"
trap 'rm -f "$TEMP_CONFIG" "$TEMP_DIFF"' EXIT
./scripts/diffconfig.sh > "$TEMP_DIFF"
# Remove identical common lines but retain device-specific overrides.
awk 'FILENAME == ARGV[1] { common[$0]=1; next } !($0 in common)' \
    "$PROJECT_DIR/devices/common/base.config" "$TEMP_DIFF" > "$TEMP_CONFIG"
chmod 644 "$TEMP_CONFIG"
mv "$TEMP_CONFIG" "$DEVICE_DIR/target.config"
echo "已保存: devices/$DEVICE/target.config"
