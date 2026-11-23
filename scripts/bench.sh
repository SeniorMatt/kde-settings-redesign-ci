#!/bin/bash
# Adapted from the main project's scripts/bench.sh: runs INSIDE the env container (no podman), weston headless.
# Usage: bench.sh OUT.tsv SHOT_DIR   env: BIN (systemsettings), PAGES (comma list), ROUNDS, TMO (seconds), LOG
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=$1 SHOTS=$2; : "${TMO:=1500}" "${LOG:=/tmp/ss-bench.log}"
mkdir -p "$(dirname "$OUT")" "$SHOTS"
export KSR_BENCH="$PAGES" KSR_BENCH_ROUNDS="${ROUNDS:-1}" KSR_BENCH_OUT="$(realpath -m "$OUT")" KSR_SHOT_DIR="$(realpath "$SHOTS")"
export SYSTEMSETTINGS_PAGE_CACHE=0
export XDG_RUNTIME_DIR=/tmp/xdg-bench-$$; rm -rf $XDG_RUNTIME_DIR; mkdir -p -m 700 $XDG_RUNTIME_DIR
export HOME=/tmp/bench-home-$$; rm -rf $HOME; mkdir -p $HOME
export XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true KDE_SESSION_VERSION=6 QT_QPA_PLATFORMTHEME=kde QT_FORCE_STDERR_LOGGING=1
timeout -k 10 "$TMO" dbus-run-session -- bash -c '
  weston --backend=headless --renderer=pixman --width=1280 --height=860 --socket=ksr-bench --idle-time=0 >/tmp/weston-bench.log 2>&1 &
  sleep 3
  WAYLAND_DISPLAY=ksr-bench QT_QPA_PLATFORM=wayland $BIN >>"$LOG" 2>&1
  kill %1' || echo "bench run ended with status $? (timeout or crash), see $LOG"
