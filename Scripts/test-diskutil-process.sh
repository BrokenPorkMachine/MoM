#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
swiftc -module-cache-path "$TEMP/ModuleCache" Core/DiskutilProcess.swift Tests/DiskutilProcessTests.swift -o "$TEMP/diskutil-process-tests"
"$TEMP/diskutil-process-tests"
