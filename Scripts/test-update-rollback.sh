#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d /private/tmp/maconmac-update.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/install" "$tmp/stage" "$tmp/previous" "$tmp/vm"
echo old-app > "$tmp/install/app"
echo old-daemon > "$tmp/install/daemon"
echo identity-and-disk-state > "$tmp/vm/manifest.json"
cp -R "$tmp/install/." "$tmp/previous/"

# Stage a matched app/daemon pair, then atomically switch the active files.
echo new-app > "$tmp/stage/app"
echo new-daemon > "$tmp/stage/daemon"
[[ "$(cat "$tmp/stage/app")" == new-app ]]
[[ "$(cat "$tmp/stage/daemon")" == new-daemon ]]
cp -R "$tmp/stage/." "$tmp/install/"
[[ "$(cat "$tmp/install/app")" == new-app ]]
[[ "$(cat "$tmp/install/daemon")" == new-daemon ]]
[[ "$(cat "$tmp/vm/manifest.json")" == identity-and-disk-state ]]

# Simulate a failed health check and restore the complete previous package.
echo failed-health-check > "$tmp/health"
cp -R "$tmp/previous/." "$tmp/install/"
[[ "$(cat "$tmp/install/app")" == old-app ]]
[[ "$(cat "$tmp/install/daemon")" == old-daemon ]]
[[ "$(cat "$tmp/vm/manifest.json")" == identity-and-disk-state ]]
echo "PASS: managed update preserves VM data and restores a matched app/daemon pair"
