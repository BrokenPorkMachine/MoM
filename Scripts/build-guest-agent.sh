#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
a="$(uname -s)"
if [ "$a" != "Darwin" ]; then echo "Requires macOS Swift SDK" >&2; exit 1; fi
xcrun swiftc -O Core/HostGuestExchange.swift Core/GuestToolsProtocol.swift Tools/GuestAgent/main.swift -o build/volumeboot-guest-agent
printf 'Built: %s\n' "$(pwd)/build/volumeboot-guest-agent"
