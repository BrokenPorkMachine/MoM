#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
cp Tests/SafetyGateTests.swift "$DIR/main.swift"
swiftc Core/PhysicalDiskSafetyPolicy.swift Core/DiskLeaseStateMachine.swift "$DIR/main.swift" -o "$DIR/safety-tests"
"$DIR/safety-tests"
