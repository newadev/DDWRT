#!/usr/bin/env bash
# Shared source preparation for Actions and the local configuration editor.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:?Usage: prepare-source.sh DEVICE SOURCE_DIR feeds|customize|files}"
SRC_DIR="${2:?Missing source directory}"
PHASE="${3:?Missing preparation phase}"

if [[ ! "$DEVICE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ || "$DEVICE" == common ]]; then
    echo "ERROR: invalid device name: $DEVICE" >&2
    exit 1
fi
if [[ ! -d "$PROJECT_DIR/devices/$DEVICE" || ! -f "$SRC_DIR/Makefile" ]]; then
    echo "ERROR: device directory or OpenWrt Makefile is missing" >&2
    exit 1
fi
cd "$SRC_DIR"

case "$PHASE" in
    feeds)
        if [[ -f "$PROJECT_DIR/devices/common/feeds.conf" ]]; then
            cp "$PROJECT_DIR/devices/common/feeds.conf" feeds.conf.default
        fi
        if [[ -f "$PROJECT_DIR/devices/$DEVICE/feeds.conf" ]]; then
            printf '\n' >> feeds.conf.default
            cat "$PROJECT_DIR/devices/$DEVICE/feeds.conf" >> feeds.conf.default
        fi
        awk '!/^[[:space:]]*#/ && NF >= 3 {
            if (seen[$2]++) { print "ERROR: duplicate feed name: " $2 > "/dev/stderr"; failed=1 }
        } END { exit failed }' feeds.conf.default
        ;;
    customize)
        for scope in common "$DEVICE"; do
            if [[ -f "$PROJECT_DIR/devices/$scope/settings.sh" ]]; then
                bash "$PROJECT_DIR/devices/$scope/settings.sh"
            fi
        done
        shopt -s nullglob
        for scope in common "$DEVICE"; do
            for patch in "$PROJECT_DIR/devices/$scope/patches/"*.patch; do
                if git apply --check "$patch"; then
                    git apply "$patch"
                elif git apply --reverse --check "$patch" 2>/dev/null; then
                    echo "Already applied: $patch"
                else
                    echo "ERROR: cannot apply patch: $patch" >&2
                    exit 1
                fi
            done
        done
        ;;
    files)
        mkdir -p files
        for scope in common "$DEVICE"; do
            if [[ -d "$PROJECT_DIR/devices/$scope/files" ]]; then
                cp -a "$PROJECT_DIR/devices/$scope/files/." files/
            fi
        done
        ;;
    *)
        echo "ERROR: unknown preparation phase: $PHASE" >&2
        exit 1
        ;;
esac
