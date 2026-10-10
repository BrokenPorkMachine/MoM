#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == "Darwin" ]] || { echo 'macOS required'; exit 78; }
mkdir -p .build
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -framework DiskArbitration \
  Tools/DiskClaimLab/main.m -o .build/vb-disk-claim-lab
printf 'Built .build/vb-disk-claim-lab (will only claim blank external test media)\n'
