#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TEST_SCRATCH="$(mktemp -d)"
trap 'rm -rf "$TEST_SCRATCH"' EXIT
swiftc Core/VMDiskImage.swift Core/VMHardware.swift Tests/DiskImageTests.swift -o "$TEST_SCRATCH/disk-image-tests"
"$TEST_SCRATCH/disk-image-tests"
if [ "$(uname -s)" = Darwin ]; then
    swiftc Core/*.swift App/AppModel.swift Tests/AppDiskWorkflowTests.swift -o "$TEST_SCRATCH/app-disk-workflow-tests"
    "$TEST_SCRATCH/app-disk-workflow-tests"
fi
