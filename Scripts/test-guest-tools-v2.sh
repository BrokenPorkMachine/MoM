#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
swiftc Core/HostGuestExchange.swift Core/GuestToolsProtocol.swift Tests/GuestToolsProtocolTests.swift -o "$TEMP/vb-tools-tests"
"$TEMP/vb-tools-tests"
