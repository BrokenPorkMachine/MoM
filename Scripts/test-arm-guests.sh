#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ]; then
    echo 'ARM guest runtime tests require macOS'
    exit 0
fi
if ! command -v qemu-system-aarch64 >/dev/null || ! command -v swtpm >/dev/null; then
    echo 'ARM guest runtime tests require installed QEMU and swtpm'
    exit 0
fi
ARM_TEST_SCRATCH="$(mktemp -d)"
trap 'rm -rf "$ARM_TEST_SCRATCH"' EXIT
swiftc Core/*.swift Tests/ARMGuestTests.swift -o "$ARM_TEST_SCRATCH/arm-guest-tests"
"$ARM_TEST_SCRATCH/arm-guest-tests"
