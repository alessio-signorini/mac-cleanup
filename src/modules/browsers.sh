#!/bin/bash
# Module: browsers — Chrome on-device AI model; profile size report.

browsers_meta() { MOD_TITLE="Browsers"; }

browsers_scan() {
  local m="$AS/Google/Chrome/OptGuideOnDeviceModel" p
  if [ -d "$m" ]; then
    if app_running Google; then note skip "Chrome on-device AI model $(hsz "$m") — quit Chrome to remove"
    else pick_path "$m" "Chrome on-device AI model (Gemini Nano; re-downloads unless disabled)"; fi
    note tip "Stop the re-download: defaults write com.google.Chrome GenAILocalFoundationalModelSettings -int 1"
  fi
  for p in "$AS/Google/Chrome" "$AS/Vivaldi" "$AS/BraveSoftware" "$H/Library/Safari" "$H/Library/Containers/com.apple.Safari"; do
    [ -d "$p" ] && note report "$(printf '%8s  %s  (profile; clear site data in-browser)' "$(hsz "$p")" "$(pretty "$p")")"
  done
  return 0
}

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only browsers "$@"
fi
# @standalone-end
