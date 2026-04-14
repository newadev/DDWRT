#!/bin/bash
#=============================================================================
# settings.sh - 全设备通用自定义设置
# 执行时机: feeds install 之后，make defconfig 之前
#=============================================================================
set -euo pipefail

echo ">>> 应用通用自定义设置"

# 安全的 sed 替换函数
safe_sed() {
    local pattern="$1"
    local file="$2"
    if [ -f "$file" ]; then
        sed -i "$pattern" "$file"
        echo "    ✓ $file"
    else
        echo "    ⚠ 文件不存在: $file"
    fi
}

# 默认 IP 地址
safe_sed 's/192.168.1.1/192.168.30.1/g' package/base-files/files/bin/config_generate

# 默认主机名
safe_sed 's/ImmortalWrt/ASUS/g' package/base-files/files/bin/config_generate

# 默认时区（新加坡）
# 注意：先替换 zonename 再替换 timezone，避免二次替换
safe_sed "s/timezone='UTC'/timezone='SGT-8'/g" package/base-files/files/bin/config_generate
safe_sed "s/zonename='UTC'/zonename='Asia\/Singapore'/g" package/base-files/files/bin/config_generate

# ttyd 免密登录
safe_sed 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

# [Workaround] mbedtls + GCC 14 aarch64 编译错误
# sha256.c ARM crypto 扩展与 musl fortify memset 内联冲突
# mbedtls 3.6.6 升级导致之前的 patch 行号失效
# 现在改为通过 CMake 选项全局关闭 Werror 致命警告
# 上游修复后可删除此段
if [ -f "package/libs/mbedtls/Makefile" ]; then
    # 移除之前的补丁
    rm -f package/libs/mbedtls/patches/999-disable-armv8ce-sha256.patch
    # 在 cmake.mk 引入前增加关闭警告选项
    sed -i '/include \$(INCLUDE_DIR)\/cmake.mk/i CMAKE_OPTIONS += -DMBEDTLS_FATAL_WARNINGS=OFF' package/libs/mbedtls/Makefile
    echo "    ✓ mbedtls: 已通过 CMake 选项禁用 FATAL_WARNINGS 绕过编译 bug"
fi

echo ">>> 通用设置应用完成"
