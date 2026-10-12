#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "Requires macOS" >&2; exit 1; }
mkdir -p build
xcrun swiftc Core/VMDiskImage.swift Core/VMBackendTrust.swift Core/VMGuest.swift Core/VMHardware.swift Core/VMConnectivity.swift Core/VMRegistry.swift Tools/VMControl/VMControlCLI.swift -o build/maconmac-vm
echo "Built: $PWD/build/maconmac-vm"
