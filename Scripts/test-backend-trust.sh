#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc Core/VMBackendTrust.swift Tests/VMBackendTrustTests.swift -o "$TMP/backend-trust"
"$TMP/backend-trust"
