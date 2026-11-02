#!/usr/bin/env bash
# Validate package selections before OpenWrt starts the expensive build.

set -euo pipefail

CONFIG_FILE="${1:-.config}"
EXPECTED_PROFILE="${2:-}"
REQUESTED_CONFIG="${3:-}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: configuration file not found: $CONFIG_FILE" >&2
    exit 2
fi

failed=0

check_group() {
    local pattern="$1"
    local packages=()
    mapfile -t packages < <(sed -n 's/^CONFIG_PACKAGE_\(.*\)=y$/\1/p' "$CONFIG_FILE" | grep -E "$pattern" || true)
    if (( ${#packages[@]} > 1 )); then
        echo "ERROR: mutually exclusive packages selected: ${packages[*]}" >&2
        failed=1
    fi
}

check_group '^ip-(full|tiny)$'
check_group '^dnsmasq(-full|-dhcpv6)?$'
check_group '^iptables(-nft)?$'
check_group '^(wpad(-.*)?|hostapd(-basic(-openssl|-mbedtls|-wolfssl)?|-mini|-openssl|-mbedtls|-wolfssl)?)$'
check_group '^(wpad(-.*)?|wpa-supplicant(-.*)?)$'
check_group '^mihomo-(meta|alpha)$'

if [[ -n "$EXPECTED_PROFILE" ]]; then
    if [[ ! "$EXPECTED_PROFILE" =~ ^CONFIG_TARGET_[a-zA-Z0-9_-]+_DEVICE_[a-zA-Z0-9_-]+$ ]] ||
       ! grep -Fxq "$EXPECTED_PROFILE=y" "$CONFIG_FILE"; then
        echo "ERROR: expected device profile is not enabled: $EXPECTED_PROFILE" >&2
        failed=1
    fi
    profile_count=$(grep -Ec '^CONFIG_TARGET_.*_DEVICE_.*=y$' "$CONFIG_FILE" || true)
    if [[ "$profile_count" != 1 ]]; then
        echo "ERROR: expected exactly one device profile, found $profile_count" >&2
        failed=1
    fi
fi

if [[ -n "$REQUESTED_CONFIG" ]]; then
    if [[ ! -f "$REQUESTED_CONFIG" ]]; then
        echo "ERROR: requested configuration not found: $REQUESTED_CONFIG" >&2
        exit 2
    fi
    while IFS= read -r selection; do
        if ! grep -Fxq "$selection" "$CONFIG_FILE"; then
            echo "ERROR: requested package was dropped by defconfig: $selection" >&2
            failed=1
        fi
    done < <(grep -E '^CONFIG_PACKAGE_.*=y$' "$REQUESTED_CONFIG" || true)
fi

if (( failed )); then
    echo "Configuration validation failed: $CONFIG_FILE" >&2
    exit 1
fi

echo "Configuration validation passed: $CONFIG_FILE"
