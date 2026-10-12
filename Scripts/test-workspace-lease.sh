#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d /private/tmp/maconmac-workspace-lease.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/workspace"
CLANG_MODULE_CACHE_PATH="$tmp/module-cache" swiftc Core/VMDiskImage.swift Core/VMHardware.swift Tests/WorkspaceLeaseProcess.swift -o "$tmp/lease-process"
"$tmp/lease-process" hold "$tmp/workspace" &
holder=$!
for _ in {1..40}; do
    [[ -f "$tmp/workspace/lease-held" ]] && break
    sleep 0.05
done
[[ -f "$tmp/workspace/lease-held" ]]
"$tmp/lease-process" probe-held "$tmp/workspace"
wait "$holder" || true
"$tmp/lease-process" probe "$tmp/workspace"
echo "PASS: workspace lease rejects competing processes and recovers after owner exit"
