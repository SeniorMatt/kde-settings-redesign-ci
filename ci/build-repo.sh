#!/bin/bash
# Runs INSIDE the env container (workspace mounted at /ci). Usage: build-repo.sh REPO
# Fetch REPO at the base commit from invent.kde.org, git am our patches, build the KCM targets (systemsettings: all),
# collect results in /ci/out/REPO and errors in /ci/out/REPO/error.log.
set -uo pipefail
R=$1; CI=/ci; W=/tmp/src/$R; B=/tmp/build/$R; O=$CI/out/$R
mkdir -p "$O" "$W" "$B"; : > "$O/build.log"
IFS=$'\t' read -r _ path base branch n < <(awk -F'\t' -v r="$R" '$1==r' $CI/patches/series.tsv)
[ -n "$base" ] || { echo "$R not in series.tsv" > "$O/error.log"; exit 1; }
fail() { echo "$*" >> "$O/error.log"; exit 1; }
git config --global user.name ci; git config --global user.email ci@example.invalid; git config --global --add safe.directory '*'
cd "$W"; git init -q
ok=0
for try in 1 2 3 4; do
  for url in "https://invent.kde.org/$path.git" "https://github.com/KDE/${path##*/}.git"; do
    git fetch --depth 1 "$url" "$base" >> "$O/build.log" 2>&1 && { ok=1; break 2; }
  done; sleep $((try*20))
done
[ $ok = 1 ] || { tail -8 "$O/build.log" > "$O/error.log"; fail "cannot fetch $path at $base"; }
git checkout -q FETCH_HEAD
git am --3way -q $CI/patches/$R/*.patch >> "$O/build.log" 2>&1 || fail "git am failed (see build.log)"
CM="-G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
export CCACHE_DIR=$CI/ccache/$R CCACHE_MAXSIZE=${CCACHE_MAXSIZE:-1G} CCACHE_COMPRESS=1 CCACHE_BASEDIR=/tmp; mkdir -p "$CCACHE_DIR"
cmake -S "$W" -B "$B" $CM >> "$O/build.log" 2>&1 || { grep -E "CMake Error|not found|Could not find" -A3 "$O/build.log" | head -80 > "$O/error.log"; fail "configure failed"; }
J=$(nproc)
case $R in
  systemsettings|systemsettings-bench)
    ninja -k 0 -j$J -C "$B" >> "$O/build.log" 2>&1 || { grep -E "error:|FAILED" -A6 "$O/build.log" | head -150 > "$O/error.log"; fail "build failed"; }
    DESTDIR=$O/stage ninja -C "$B" install >> "$O/build.log" 2>&1 || fail "install failed" ;;
  *)
    all=$(ninja -C "$B" -t targets all 2>/dev/null | cut -d: -f1)
    kcms=$(awk -F'\t' -v r="$R" '$1==r{print $2}' $CI/ci/data/kcms.tsv); targets=""
    for k in $kcms; do
      t=$(grep -xE "$k|${k}_kcm|kcm_${k#kcm_}" <<<"$all" | head -1)
      [ -n "$t" ] && targets="$targets $t" || echo "NO TARGET $k" >> "$O/error.log"
    done
    [ -n "$targets" ] || fail "no targets"
    echo "targets:$targets" >> "$O/build.log"
    ninja -k 0 -j$J -C "$B" $targets >> "$O/build.log" 2>&1 || { grep -E "error:|FAILED" -A6 "$O/build.log" | head -150 >> "$O/error.log"; fail "build failed"; }
    mkdir -p "$O/plugins"
    for k in $kcms; do
      # keep the path relative to bin/ (plasma/kcms/kinfocenter, plasma/kcms, ...); flat in bin/ = install dir systemsettings_qwidgets
      so=$(find "$B/bin" -name "$k.so" | head -1)
      if [ -z "$so" ]; then echo "NO PLUGIN $k" >> "$O/error.log"; continue; fi
      sub=$(dirname "${so#*/bin/}"); [ "$sub" = . ] && sub=plasma/kcms/systemsettings_qwidgets
      mkdir -p "$O/plugins/$sub"; cp "$so" "$O/plugins/$sub/"
    done
    # libraries this repo builds itself and the plugins link to (the system copy can be older: ABI/symbol mismatch)
    $CI/ci/ship-libs.sh "$B" "$O/lib" $(find "$O/plugins" -name "*.so") >> "$O/build.log" 2>&1 ;;
esac
ccache -s 2>/dev/null | grep -iE "hit|miss" >> "$O/build.log"
tail -3 "$O/build.log"; rm -f "$O/error.log.empty"; exit 0
