#!/usr/bin/env bash
# Emit each Kconfig symbol once; later fragments override earlier fragments.
set -euo pipefail
if (( $# == 0 )); then
    echo "Usage: merge-config.sh CONFIG_FRAGMENT..." >&2
    exit 2
fi
for fragment in "$@"; do
    [[ -f "$fragment" ]] || { echo "ERROR: missing configuration: $fragment" >&2; exit 1; }
done
awk '
    /^CONFIG_[^=]+=/{ key=$0; sub(/=.*/, "", key) }
    /^# CONFIG_[^ ]+ is not set$/{ key=$2 }
    !/^CONFIG_[^=]+=/ && !/^# CONFIG_[^ ]+ is not set$/ { next }
    { if (!(key in value)) order[++count]=key; value[key]=$0 }
    END { for (i=1; i<=count; i++) print value[order[i]] }
' "$@"
