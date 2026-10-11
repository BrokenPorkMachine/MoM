#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
swiftc -module-cache-path "$TEMP/ModuleCache" Core/TaskDispatchQueue.swift Tests/TaskDispatchQueueTests.swift -o "$TEMP/task-dispatch-tests"
"$TEMP/task-dispatch-tests"
