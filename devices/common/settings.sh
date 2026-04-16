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


echo ">>> 通用设置应用完成"
