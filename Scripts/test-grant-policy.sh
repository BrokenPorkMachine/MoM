#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc Core/BrokerAuthorizationPolicy.swift Core/ReadOnlyGrantPolicy.swift Tests/ReadOnlyGrantPolicyTests.swift -o "$TMP/grant-policy"
"$TMP/grant-policy"
