#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc Core/BrokerProtocolContract.swift Tests/BrokerContractTests.swift -o "$TMP/broker-contract-tests"
"$TMP/broker-contract-tests"
