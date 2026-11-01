#!/bin/bash
#=============================================================================
# settings.sh - Cudy TR3000 v1 专属设置脚本
# 1. 扩容 UBI DTS 分区至 112MB
# 2. 扩容 filogic.mk 中的 IMAGE_SIZE 限制以容纳大固件
#=============================================================================
set -euo pipefail

echo ">>> 应用 Cudy TR3000 v1 专属设置"

DTS_FILE="target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1.dts"
MK_FILE="target/linux/mediatek/image/filogic.mk"

# 1. 扩容 UBI DTS 分区 (0x4000000 -> 0x7000000 即 64MB -> 112MB)
if [ -f "$DTS_FILE" ]; then
    if grep -q "0x4000000" "$DTS_FILE"; then
        sed -i 's/0x4000000/0x7000000/g' "$DTS_FILE"
        echo "    ✓ 已更新 DTS 分区定义 (64M -> 112M): $DTS_FILE"
    else
        echo "    ℹ DTS 分区大小已修改或无匹配项: $DTS_FILE"
    fi
else
    echo "    ⚠ 未找到 DTS 文件: $DTS_FILE"
fi

# 2. 同步放宽 Makefile 中的镜像生成尺寸上限 (从 64MB 扩展至 112MB)
if [ -f "$MK_FILE" ]; then
    if grep -q "cudy_tr3000-v1" "$MK_FILE"; then
        sed -i '/define Device\/cudy_tr3000-v1/,/endef/ s/IMAGE_SIZE := 65536k/IMAGE_SIZE := 114688k/' "$MK_FILE"
        echo "    ✓ 已更新 filogic.mk IMAGE_SIZE (65536k -> 114688k): $MK_FILE"
    fi
else
    echo "    ⚠ 未找到 Makefile: $MK_FILE"
fi

echo ">>> Cudy TR3000 v1 专属设置完成"
