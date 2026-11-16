#!/bin/bash
# Entry point. In dev, sources the core and all modules; in dist/ the region below is
# stripped by build.sh (everything is already concatenated above it).
set -o pipefail

# @dev-begin
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
for _m in $MC_ALL_MODULES; do
  # shellcheck source=/dev/null
  [ -f "$MC_SRC/modules/$_m.sh" ] && . "$MC_SRC/modules/$_m.sh"
done
unset _m
# @dev-end

mc_main "$@"
