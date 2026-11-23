#!/bin/bash
# Free space on a GitHub runner (about 14 GB free by default).
sudo rm -rf /usr/share/dotnet /opt/ghc /usr/local/lib/android /opt/hostedtoolcache/CodeQL /usr/local/share/boost \
  /usr/share/swift /usr/local/.ghcup /opt/microsoft /usr/local/share/powershell 2>/dev/null || true
sudo docker image prune -af >/dev/null 2>&1 || true
df -h / | tail -1
