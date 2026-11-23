#!/bin/bash
# Recreate KDE Linux's userland (Arch snapshot + packages.txt + KDE's install.tar.zst) in an archlinux container and
# export it to $1 (env.tar.zst). Same recipe as build/containers/make-kdelinux.sh of the main project.
set -euo pipefail
OUT=$(realpath -m "$1"); CI=$(cd "$(dirname "$0")/.." && pwd)
SNAP=https://archive.kde-linux.haraldsitter.eu/snapshot-2026-10-29T04:34:36Z
TAR=https://kde-linux-packages.s3.kde.org/testing/artifacts/install.tar.zst
docker rm -f ksr-env-build >/dev/null 2>&1 || true
docker run -d --name ksr-env-build -v "$CI":/ci:ro docker.io/library/archlinux:latest sleep infinity
docker exec ksr-env-build bash -c "
set -e
echo 'Server = $SNAP/\$repo/os/\$arch' > /etc/pacman.d/mirrorlist
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/; s/^#DisableSandbox/DisableSandbox/' /etc/pacman.conf
grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf 2>/dev/null || true
pkgs=\$(grep -v -e '^qt6-webengine' -e '^qt6-webview' /ci/ci/data/packages.txt | tr '\n' ' ')
extra=\$(tr '\n' ' ' < /ci/ci/data/extra-packages.txt)
for i in 1 2 3; do pacman -Syyuu --noconfirm --needed --disable-download-timeout \$pkgs \$extra && break; done
command -v git >/dev/null && command -v ninja >/dev/null && command -v weston >/dev/null || { echo package install failed; exit 1; }
curl -fL --retry 5 -o /tmp/install.tar.zst '$TAR'
tar --zstd -xf /tmp/install.tar.zst -C / --keep-directory-symlink
rm -f /tmp/install.tar.zst
# packages pulled in by the extra list leave stale -noconfig/-release cmake files next to the tarball's -relwithdebinfo ones
for f in /usr/lib/cmake/*/*-relwithdebinfo.cmake; do rm -f \${f%-relwithdebinfo.cmake}-noconfig.cmake \${f%-relwithdebinfo.cmake}-release.cmake; done
 pacman -Scc --noconfirm >/dev/null || true; ldconfig
ls /usr/lib/qt6/plugins/plasma/kcms/systemsettings | wc -l; du -sh /usr
"
docker export ksr-env-build | zstd -T0 -3 -o "$OUT"
docker rm -f ksr-env-build >/dev/null
ls -l "$OUT"
