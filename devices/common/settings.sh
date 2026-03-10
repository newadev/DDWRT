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
# -Werror 由 mbedtls 的 CMakeLists.txt 注入，需要修改 OpenWrt 的包 Makefile
# 上游修复后可删除此段
if [ -f "package/libs/mbedtls/Makefile" ]; then
    # 方法1: 在 OpenWrt Makefile 中添加 CMAKE 选项禁用致命警告
    sed -i '/CMAKE_OPTIONS/a\\t-DMBEDTLS_FATAL_WARNINGS=OFF \\' package/libs/mbedtls/Makefile
    # 方法2: 直接追加 CFLAGS 覆盖
    sed -i 's/TARGET_CFLAGS +=/TARGET_CFLAGS += -Wno-error/' package/libs/mbedtls/Makefile 2>/dev/null || true
    echo "    ✓ mbedtls: 已应用 GCC 14 workaround"
fi

echo ">>> 通用设置应用完成"
