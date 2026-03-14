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
# 直接禁用 mbedtls 的 ARMv8 CE 硬件加速来绕过该问题
# 上游修复后可删除此段
if [ -f "package/libs/mbedtls/Makefile" ]; then
    # 在 mbedtls 的编译前加一个 hook，注释掉 config 头文件中的 ARMv8 CE 支持
    mkdir -p package/libs/mbedtls/patches
    cat << 'EOF' > package/libs/mbedtls/patches/999-disable-armv8ce-sha256.patch
--- a/include/mbedtls/mbedtls_config.h
+++ b/include/mbedtls/mbedtls_config.h
@@ -2965,7 +2965,7 @@
  *
  * Requires: MBEDTLS_SHA256_C
  */
-#define MBEDTLS_ARMV8CE_SHA256_C
+//#define MBEDTLS_ARMV8CE_SHA256_C
 
 /**
  * \def MBEDTLS_ARMV8CE_SHA512_C
EOF
    echo "    ✓ mbedtls: 已添加 patch 禁用 ARMv8CE_SHA256 硬件加速绕过编译 bug"
fi

echo ">>> 通用设置应用完成"
