#!/bin/bash
# Module: xcode — DerivedData, simulator caches/runtimes/devices, DeviceSupport, archives.

xcode_meta() { MOD_TITLE="Xcode & simulators"; }

xcode_scan() {
  local D="$H/Library/Developer" id k label udid d platf a
  [ -d "$D" ] || return 0
  safe_clear "$D/Xcode/DerivedData" "Xcode DerivedData"
  safe_clear "$D/CoreSimulator/Caches" "CoreSimulator caches"
  safe_clear "$D/Xcode/UserData/Previews" "SwiftUI preview simulators"
  safe_clear "$D/Xcode/DocumentationCache" "Xcode documentation cache"
  safe_clear "$D/XCPGDevices" "Playground devices"

  if command -v xcrun >/dev/null 2>&1 && xcrun --find simctl >/dev/null 2>&1; then
    safe_cmd unavailable "delete unavailable simulators (simctl delete unavailable)" xcode_del_unavailable 0 "-"

    xcrun simctl runtime list -j > "$MC_TMP/xcode_rt.json" 2>/dev/null
    mc_group "Simulator runtimes (5-10GB each; reinstall via Xcode > Settings > Components)"
    while IFS=$'\t' read -r id k label; do
      [ -n "$id" ] && pick_item "$id" "$label" "$k" xcode_del_runtime
    done < <(jxa "$MC_TMP/xcode_rt.json" '
      var r=[]; for (var k in d) { var v=d[k];
        var p=(v.platformIdentifier||"").split(".").pop().replace("simulator","");
        r.push(k+"\t"+Math.floor((v.sizeBytes||0)/1024)+"\t"+p+" "+(v.version||"?")+" ("+(v.build||"?")+")  last used "+String(v.lastUsedAt||"never").slice(0,10)); }
      return r.join("\n");')

    xcrun simctl list devices -j > "$MC_TMP/xcode_dev.json" 2>/dev/null
    mc_group "Simulator devices > 50MB (apps + data inside the simulator)"
    while IFS=$'\t' read -r udid label; do
      [ -n "$udid" ] || continue
      k=$(kb "$D/CoreSimulator/Devices/$udid")
      [ "$k" -ge 51200 ] && pick_item "$udid" "$label" "$k" xcode_del_sim "" "$D/CoreSimulator/Devices/$udid"
    done < <(jxa "$MC_TMP/xcode_dev.json" '
      var r=[], dv=d.devices||{}; for (var rt in dv) {
        var n=rt.split(".").pop().replace("-"," ").replace(/-/g,".");
        dv[rt].forEach(function(x){ r.push(x.udid+"\t"+(x.name||"?")+" - "+n+"  last booted "+String(x.lastBootedAt||"never").slice(0,10)); }); }
      return r.join("\n");')
  fi

  mc_group "Device support files (re-created when that device connects)"
  for d in "$D"/Xcode/*DeviceSupport/*/; do
    [ -d "$d" ] || continue; d="${d%/}"
    platf=$(basename "$(dirname "$d")"); platf="${platf% DeviceSupport}"
    pick_path "$d" "$platf ${d##*/}  ($(stat -f '%Sm' -t '%Y-%m-%d' "$d" 2>/dev/null))"
  done

  mc_group "Archives (keep the ones you need to symbolicate shipped builds)"
  while IFS= read -r a; do pick_path "$a" "${a##*/}"; done \
    < <(find "$D/Xcode/Archives" -maxdepth 2 -name '*.xcarchive' 2>/dev/null)
  return 0
}

xcode_del_unavailable() { xcrun simctl delete unavailable; }
xcode_del_runtime()     { xcrun simctl runtime delete "$1"; }
xcode_del_sim()         { xcrun simctl delete "$1"; }

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only xcode "$@"
fi
# @standalone-end
