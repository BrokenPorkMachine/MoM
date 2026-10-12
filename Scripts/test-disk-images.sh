#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TEST_SCRATCH="$(mktemp -d)"
trap 'rm -rf "$TEST_SCRATCH"' EXIT
MACONMAC_ALLOW_LOW_SPACE_TEST=1 swiftc Core/VMDiskImage.swift Core/VMHardware.swift Tests/DiskImageTests.swift -o "$TEST_SCRATCH/disk-image-tests"
MACONMAC_ALLOW_LOW_SPACE_TEST=1 "$TEST_SCRATCH/disk-image-tests"
if [ "$(uname -s)" = Darwin ]; then
    MACONMAC_ALLOW_LOW_SPACE_TEST=1 swiftc Core/*.swift App/AppModel.swift Tests/AppDiskWorkflowTests.swift -o "$TEST_SCRATCH/app-disk-workflow-tests"
    MACONMAC_ALLOW_LOW_SPACE_TEST=1 "$TEST_SCRATCH/app-disk-workflow-tests"
fi
