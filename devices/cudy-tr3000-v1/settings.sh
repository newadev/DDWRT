#!/usr/bin/env bash
# Expand the existing Cudy TR3000 v1 layout to 112 MiB.
set -euo pipefail

DTS_FILE="target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1.dts"
MK_FILE="target/linux/mediatek/image/filogic.mk"

# Verify both upstream definitions before making either edit.
if [[ ! -f "$DTS_FILE" || ! -f "$MK_FILE" ]]; then
    echo 'ERROR: Cudy DTS or image definition is missing' >&2
    exit 1
fi
ubi_definition=$(sed -n '/^&ubi {/,/^};/p' "$DTS_FILE")
image_definition=$(sed -n '/^define Device\/cudy_tr3000-v1$/,/^endef$/p' "$MK_FILE")
if [[ $(grep -Ec '^[[:space:]]*reg = <0x5c0000 0x(4000000|7000000)>;' <<< "$ubi_definition") != 1 ]] ||
   [[ $(grep -Ec '^[[:space:]]*IMAGE_SIZE := (65536|114688)k$' <<< "$image_definition") != 1 ]]; then
    echo 'ERROR: unexpected Cudy partition/image layout; refusing to change it' >&2
    exit 1
fi

sed -i '/^&ubi {/,/^};/ s/0x4000000/0x7000000/' "$DTS_FILE"
sed -i '/^define Device\/cudy_tr3000-v1$/,/^endef$/ s/IMAGE_SIZE := 65536k/IMAGE_SIZE := 114688k/' "$MK_FILE"
echo 'Cudy TR3000 v1: DTS 与镜像上限已同步为 112 MiB'
