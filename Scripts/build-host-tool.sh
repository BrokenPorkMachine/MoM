#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != "Darwin" ]; then echo "Requires macOS Swift SDK" >&2; exit 1; fi
mkdir -p build
xcrun swiftc -O Core/VMConnectivity.swift Core/HostGuestExchange.swift Core/GuestToolsProtocol.swift Tools/HostTool/HostCLI.swift -o build/volumeboot-host
printf 'Built: %s\n' "$(pwd)/build/volumeboot-host"
