#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
shasum -a 256 -c SOURCE_MANIFEST.sha256 --quiet
echo "PASS: source manifest hashes match"
