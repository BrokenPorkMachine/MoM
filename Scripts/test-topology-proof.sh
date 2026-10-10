#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc Core/PhysicalDiskTopologyProof.swift Tests/PhysicalDiskTopologyProofTests.swift -o "$TMP/topology"
"$TMP/topology"
