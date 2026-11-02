#!/usr/bin/env bash
# Copy firmware to a separate directory and generate a verifiable manifest.
set -euo pipefail
SOURCE="${1:?Usage: prepare-artifacts.sh TARGET_DIR OUTPUT_DIR}"
OUTPUT="${2:?Missing output directory}"
[[ -d "$SOURCE" ]] || { echo "ERROR: missing target directory: $SOURCE" >&2; exit 1; }
mkdir -p "$OUTPUT"
if [[ "$(realpath "$SOURCE")" == "$(realpath "$OUTPUT")" ]] ||
   [[ -n "$(find "$OUTPUT" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "ERROR: output must be a separate empty directory: $OUTPUT" >&2
    exit 1
fi
count=0
shopt -s nullglob
for artifact in "$SOURCE"/*; do
    [[ -f "$artifact" ]] || continue
    case "$artifact" in
        *.buildinfo|*.manifest|*.json|*/sha256sums) continue ;;
    esac
    cp -p "$artifact" "$OUTPUT/"
    count=$((count + 1))
done
if (( count == 0 )); then
    echo "ERROR: no firmware artifacts found in $SOURCE" >&2
    exit 1
fi
cd "$OUTPUT"
artifacts=(./*)
sha256sum "${artifacts[@]}" > sha256sums
sha256sum -c sha256sums
