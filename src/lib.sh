#!/bin/bash
# Dev loader: sources every core file in order. Not included in dist/.
set -o pipefail
MC_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _f in "$MC_SRC"/core/*.sh; do
  # shellcheck source=/dev/null
  . "$_f"
done
unset _f
