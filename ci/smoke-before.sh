#!/bin/bash
# Runs INSIDE the env container (workspace /ci). "Before" pass: the stock /usr/bin/systemsettings (KDE Linux's own build and
# pages, none of our patches) opened on the same page list as smoke.sh; one screenshot per page in /ci/res/shots-before.
# Needs res/pages-built.txt from smoke.sh. weston runs with --debug so weston-screenshooter may capture the output.
set -uo pipefail
cd /ci; mkdir -p res/shots-before
export XDG_RUNTIME_DIR=/tmp/xdg-before; rm -rf $XDG_RUNTIME_DIR; mkdir -p -m 700 $XDG_RUNTIME_DIR
export HOME=/tmp/before-home; rm -rf $HOME; mkdir -p $HOME
export XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true KDE_SESSION_VERSION=6 QT_QPA_PLATFORMTHEME=kde QT_FORCE_STDERR_LOGGING=1
export PAGES=$(cat res/pages-built.txt | paste -sd' ')
timeout -k 10 "${TMO:-1500}" dbus-run-session -- bash -c '
  weston --backend=headless --renderer=pixman --width=1280 --height=860 --socket=ksr-before --idle-time=0 --debug >/tmp/weston-before.log 2>&1 &
  sleep 3
  export WAYLAND_DISPLAY=ksr-before QT_QPA_PLATFORM=wayland
  for p in $PAGES; do
    /usr/bin/systemsettings $p >/ci/res/before-$p.log 2>&1 &
    pid=$!
    sleep ${WAIT:-8}
    (cd /ci/res/shots-before && rm -f wayland-screenshot-*.png && weston-screenshooter >/dev/null 2>&1 && mv wayland-screenshot-*.png $p.png)
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
  done
  kill %1'
echo "before shots: $(ls res/shots-before | wc -l) of $(wc -w <<<"$PAGES")"
