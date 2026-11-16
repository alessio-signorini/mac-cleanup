#!/bin/bash
# Module: downloads — old installers/archives in Downloads/Desktop, macOS installers.

downloads_meta() { MOD_TITLE="Old installers & archives"; }

downloads_scan() {
  local f a
  mc_group "Installers/archives in Downloads & Desktop older than ${DAYS}d, > 5MB"
  while IFS= read -r f; do
    pick_path "$f" "$(pretty "$f")  ($(stat -f '%Sm' -t '%Y-%m-%d' "$f" 2>/dev/null))"
  done < <(find "$H/Downloads" "$H/Desktop" -maxdepth 2 -type f \( -iname '*.dmg' -o -iname '*.pkg' -o -iname '*.iso' \
             -o -iname '*.xip' -o -iname '*.ipsw' -o -iname '*.zip' -o -iname '*.tar.gz' -o -iname '*.tgz' \) \
             -mtime +"$DAYS" -size +5M 2>/dev/null)
  mc_group "macOS installers"
  for a in /Applications/Install\ macOS*.app; do [ -d "$a" ] && pick_path "$a" "$a"; done
  return 0
}

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only downloads "$@"
fi
# @standalone-end
