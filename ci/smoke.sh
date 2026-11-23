#!/bin/bash
# Runs INSIDE the env container (workspace /ci, artifacts unpacked in /ci/out/*). Opens every reworked page once.
# A hang or crash in one page only costs that page: pages missing from the result are retried one by one.
set -uo pipefail
cd /ci
P=/ci/plug/plasma/kcms; mkdir -p $P /ci/res/shots
for d in out/*/plugins; do [ -d $d/plasma ] && cp -a $d/plasma/. /ci/plug/plasma/; done   # keeps systemsettings/, kinfocenter/, systemsettings_qwidgets/ apart
mkdir -p /ci/plug/lib; cp -a out/*/lib/. /ci/plug/lib/ 2>/dev/null   # repo-built shared libs the KCMs need
S=/ci/out/systemsettings-bench/stage
export LD_LIBRARY_PATH=/ci/plug/lib:$S/usr/lib:$S/usr/lib64 QT_PLUGIN_PATH=/ci/plug:$S/usr/lib/qt6/plugins QML_IMPORT_PATH=$S/usr/lib/qt6/qml \
  QML2_IMPORT_PATH=$S/usr/lib/qt6/qml XDG_DATA_DIRS=$S/usr/share:/usr/local/share:/usr/share
chmod -R u+x $S/usr/bin $S/usr/libexec $S/usr/lib/libexec 2>/dev/null   # artifact zips drop the exec bits
BIN=$(find $S -name systemsettings -type f | head -1); export BIN; [ -n "$BIN" ] || { echo "no systemsettings binary in $S"; find /ci/out -maxdepth 2; exit 1; }; echo "BIN=$BIN"
find $P -name '*.so' -printf '%f\n' | sed 's/\.so$//' | sort > /ci/res/pages-built.txt
ALL=kcm_mouse,$(grep -vxE "kcm_mouse|kcm_desktoptheme" /ci/res/pages-built.txt | paste -sd,),kcm_desktoptheme
export LOG=/ci/res/ss-bench.log
PAGES=$ALL ROUNDS=1 TMO=${TMO:-1200} scripts/bench.sh res/smoke.tsv res/shots
[ -s res/smoke.tsv ] || printf 'round\tkcm\tkind\tsync_ms\tframe_ms\tready_ms\twait_ms\n' > res/smoke.tsv
# pages that left no row: retry each alone, 150 s at most
done_ids=$(awk -F'\t' 'NR>1{print $2}' res/smoke.tsv 2>/dev/null | sort -u)
for p in ${ALL//,/ }; do
  grep -qx "$p" <<<"$done_ids" && continue
  echo "retry $p"
  LOG=/ci/res/ss-bench-$p.log PAGES=$p ROUNDS=1 TMO=150 scripts/bench.sh res/retry-$p.tsv res/shots
  [ -s res/retry-$p.tsv ] && tail -n +2 res/retry-$p.tsv >> res/smoke.tsv
done
grep -hE "\.qml:[0-9]+|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|failed to load|Segmentation" res/ss-bench*.log \
  | sed 's|qrc:/kcm/||' | sort | uniq -c | sort -rn > res/qml-errors.txt
echo "rows: $(($(wc -l < res/smoke.tsv)-1)) shots: $(ls res/shots | wc -l) qml lines: $(wc -l < res/qml-errors.txt)"
