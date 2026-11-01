#!/usr/bin/env bash
# Validate package selections before OpenWrt starts the expensive build.

set -euo pipefail

CONFIG_FILE="${1:-.config}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: configuration file not found: $CONFIG_FILE" >&2
    exit 2
fi

is_enabled() {
    grep -Eq "^CONFIG_PACKAGE_${1}=y$" "$CONFIG_FILE"
}

failed=0

check_conflict() {
    local first="$1"
    local second="$2"

    if is_enabled "$first" && is_enabled "$second"; then
        echo "ERROR: mutually exclusive packages selected: $first and $second" >&2
        failed=1
    fi
}

# 1. ip-full and ip-tiny provide the same ip utility and cannot coexist.
check_conflict ip-full ip-tiny

# 2. dnsmasq variants
check_conflict dnsmasq dnsmasq-full

# 3. iptables legacy vs iptables-nft
check_conflict iptables iptables-nft

# 4. wpad variants (e.g. wpad-openssl vs wpad-basic-mbedtls)
check_conflict wpad-openssl wpad-basic-mbedtls
check_conflict wpad-openssl wpad-basic-wolfssl
check_conflict wpad wpad-openssl

if (( failed )); then
    echo "Configuration validation failed: $CONFIG_FILE" >&2
    exit 1
fi

echo "Configuration validation passed: $CONFIG_FILE"
