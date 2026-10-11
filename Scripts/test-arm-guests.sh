#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo 'ARM guest runtime tests require an Apple Silicon Mac'
    exit 0
fi
if ! command -v qemu-system-aarch64 >/dev/null || ! command -v swtpm >/dev/null; then
    echo 'ARM guest runtime tests require installed QEMU and swtpm'
    exit 0
fi
ARM_TEST_SCRATCH="$(mktemp -d)"
trap 'rm -rf "$ARM_TEST_SCRATCH"' EXIT
swiftc Core/*.swift Tests/ARMGuestTests.swift -o "$ARM_TEST_SCRATCH/arm-guest-tests"
codesign --force --sign - --entitlements Resources/MacOnMac.entitlements "$ARM_TEST_SCRATCH/arm-guest-tests"
VOLUMEBOOT_ARM_TEST_ROOT="$ARM_TEST_SCRATCH" "$ARM_TEST_SCRATCH/arm-guest-tests"
