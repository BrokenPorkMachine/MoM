#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
git ls-files -z | while IFS= read -r -d '' file; do
    [[ "$file" == "SOURCE_MANIFEST.sha256" ]] && continue
    shasum -a 256 "$file"
done | LC_ALL=C sort -k 2 > "$tmp"
mv "$tmp" SOURCE_MANIFEST.sha256
echo "Updated SOURCE_MANIFEST.sha256"
