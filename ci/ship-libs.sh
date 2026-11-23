#!/bin/bash
# Copy the shared libraries a KCM plugin needs from its own build dir (libs the repo builds itself, e.g.
# libkcm_firewall_core.so, libkglobalaccelmodel.so, libplasmanm_*.so), so an older system copy is not picked up.
# Usage: ship-libs.sh BUILD_DIR DEST_DIR plugin.so [plugin.so ...]   (follows NEEDED entries recursively)
# Shipped by scripts/export-patches.sh to the CI repo as ci/ship-libs.sh. Needs readelf.
set -uo pipefail
B=$1 D=$2; shift 2; mkdir -p "$D"
declare -A path seen
while IFS= read -r f; do path[${f##*/}]=$f; done < <(find "$B" \( -name 'lib*.so' -o -name 'lib*.so.*' \) \( -type f -o -type l \) 2>/dev/null)
queue=("$@")
while [ ${#queue[@]} -gt 0 ]; do
  f=${queue[0]}; queue=("${queue[@]:1}")
  for n in $(readelf -d "$f" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
    [ -n "${seen[$n]:-}" ] && continue; seen[$n]=1
    p=${path[$n]:-}; [ -n "$p" ] || continue
    cp -L "$p" "$D/"; echo "ship $n" ; queue+=("$p")
  done
done
