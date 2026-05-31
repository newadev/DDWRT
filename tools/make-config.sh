#!/bin/bash
#=============================================================================
# make-config.sh - 为特定设备生成配置 (新架构)
# 
# 用法：
#   ./tools/make-config.sh <设备名>
#
# 示例：
#   ./tools/make-config.sh x86_64
#   ./tools/make-config.sh cudy-tr3000-v1
#
# 前提：项目根目录下已有 immortalwrt 源码目录
#=============================================================================

set -eo pipefail

DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
    echo "错误: 请明确输入设备名！例如: ./tools/make-config.sh x86_64"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$PROJECT_DIR/immortalwrt"

# 检查源码目录是否存在
if [ ! -d "$SRC_DIR" ]; then
    echo "错误: 未找到源码目录 $SRC_DIR"
    echo "请先在项目根目录执行:"
    echo "  git clone -b master --single-branch --filter=blob:none https://github.com/immortalwrt/immortalwrt.git"
    exit 1
fi

# 建立该设备的专属目录（如果不存在）
DEVICE_DIR="$PROJECT_DIR/devices/$DEVICE"
mkdir -p "$DEVICE_DIR/files"
mkdir -p "$DEVICE_DIR/patches"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN} ImmortalWrt 配置生成器 (按设备专属隔离)${NC}"
echo -e "${GREEN} 目标设备目录: devices/$DEVICE${NC}"
echo -e "${GREEN}================================${NC}"

# 1. 进入源码目录并更新
cd "$SRC_DIR"
echo -e "${YELLOW}>>> 更新源码...${NC}"
git pull --ff-only || echo -e "${YELLOW}  ⚠ 更新跳过（可能有本地修改）${NC}"

# 2. 挂载 Feeds 配置
echo -e "${YELLOW}>>> 挂载 Feeds...${NC}"
if [ -f "$PROJECT_DIR/devices/common/feeds.conf" ]; then
    cp "$PROJECT_DIR/devices/common/feeds.conf" feeds.conf.default
fi
if [ -f "$DEVICE_DIR/feeds.conf" ]; then
    cp "$DEVICE_DIR/feeds.conf" feeds.conf.default
fi

# 更新 feeds
echo -e "${YELLOW}>>> Update & Install feeds...${NC}"
./scripts/feeds update -a
./scripts/feeds install -a

# 3. 加载基础配置与现有专属配置
echo -e "${YELLOW}>>> 预加载配置...${NC}"
rm -f .config

# (A) 强行合并通用基础包配置
if [ -f "$PROJECT_DIR/devices/common/base.config" ]; then
    cat "$PROJECT_DIR/devices/common/base.config" >> .config
fi

# (B) 合并该设备现有的旧配置 (如果存在)
if [ -f "$DEVICE_DIR/target.config" ]; then
    cat "$DEVICE_DIR/target.config" >> .config
fi

make defconfig

# 4. 打开 menuconfig
echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN} 操作说明：${NC}"
echo -e "${GREEN}   1. 请配置你的目标硬件系统（Target System / Subtarget）${NC}"
echo -e "${GREEN}   2. 请选择你需要附加安装的专属软件包${NC}"
echo -e "${GREEN}   3. 【注意】不要去取消通用的LuCI/Passwall等，否则基础配置会受损！${NC}"
echo -e "${GREEN}   完成后选择 Save 并 Exit${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
read -p "按 Enter 打开配置界面..."

make menuconfig

# 5. 保存并剔除 common 部分的内容
echo -e "${YELLOW}>>> 剥离出该设备专属的配置差异...${NC}"
TEMP_CONFIG="$(mktemp)"
./scripts/diffconfig.sh > "$TEMP_CONFIG"

# (简单的剔除逻辑：如果在 common 里已经有了，就不算作设备的 specific config)
if [ -f "$PROJECT_DIR/devices/common/base.config" ]; then
    grep -v -F -x -f "$PROJECT_DIR/devices/common/base.config" "$TEMP_CONFIG" > "$DEVICE_DIR/target.config" || true
else
    mv "$TEMP_CONFIG" "$DEVICE_DIR/target.config"
fi

rm -f "$TEMP_CONFIG"

# 如果文件变空了，也要保持为空
if [ ! -s "$DEVICE_DIR/target.config" ]; then
   echo "" > "$DEVICE_DIR/target.config"
fi

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN} ✅ 设备的专有配置 (Diff) 已增量保存！${NC}"
echo -e "${GREEN} 文件位置: devices/$DEVICE/target.config${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "💡 提示："
echo " - 如果你需要修改该设备的默认 IP、默认设置，请在 devices/$DEVICE/ 新建 settings.sh"
echo " - 如果你需要替换文件，请丢入 devices/$DEVICE/files/"
echo " - 如果你想给该设备打补丁，请丢入 devices/$DEVICE/patches/"
echo " - 提交修改: git add . && git commit -m 'update' && git push"
