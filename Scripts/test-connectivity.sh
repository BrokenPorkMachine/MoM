#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
swiftc Core/VMConnectivity.swift Core/HostGuestExchange.swift Tests/ConnectivityTests.swift -o "$TEMP/vb-connectivity-tests"
"$TEMP/vb-connectivity-tests"
swiftc -typecheck Core/HostGuestExchange.swift Core/GuestToolsProtocol.swift Tools/GuestAgent/main.swift
swiftc -typecheck Core/VMConnectivity.swift Core/HostGuestExchange.swift Core/GuestToolsProtocol.swift Tools/HostTool/HostCLI.swift
