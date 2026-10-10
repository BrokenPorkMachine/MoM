#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc Core/BrokerAuthorizationPolicy.swift Tests/BrokerAuthorizationTests.swift -o "$TMP/broker-policy-tests"
"$TMP/broker-policy-tests"
