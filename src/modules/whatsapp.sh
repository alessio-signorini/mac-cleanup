#!/bin/bash
# Module: whatsapp — logs, unreferenced media (orphans), old media per chat.

whatsapp_meta() { MOD_TITLE="WhatsApp"; }

WA=""   # set by whatsapp_scan (H is not defined yet when a standalone module is parsed)

whatsapp_name() {   # chat display name for a JID
  local n
  n=$(awk -F'\t' -v j="$1" '$1==j{print $2; exit}' "$MC_TMP/whatsapp_names" 2>/dev/null)
  printf '%s' "${n:-$1}"
}

# Media files on disk that no ZWAMEDIAITEM row references. A file is kept if its path stem
# (dir + uuid, extension ignored) matches any referenced media/thumbnail/xmpp-thumb path.
# Files touched < 48h are never candidates. Aborts if DB paths don't line up with disk.
# Output: $MC_TMP/whatsapp_orphans (relative paths), $MC_TMP/whatsapp_orphan_by_chat (kb \t n \t jid)
whatsapp_orphan_scan() {
  local msg="$WA/Message" db="$WA/ChatStorage.sqlite" nref nmatch norph T="$MC_TMP/whatsapp"
  : > "${T}_orphans"; : > "${T}_orphan_by_chat"
  if [ ! -f "$db" ] || ! command -v sqlite3 >/dev/null 2>&1; then
    note skip "WhatsApp DB/sqlite3 not found — orphan sweep skipped"; return 0
  fi
  if ! sqlite3 -readonly "$db" "SELECT ZMEDIALOCALPATH FROM ZWAMEDIAITEM WHERE ZMEDIALOCALPATH<>''
        UNION SELECT ZTHUMBNAILLOCALPATH FROM ZWAMEDIAITEM WHERE ZTHUMBNAILLOCALPATH<>''
        UNION SELECT ZXMPPTHUMBPATH FROM ZWAMEDIAITEM WHERE ZXMPPTHUMBPATH<>'';" > "${T}_refs" 2>"${T}_err"; then
    note warn "WhatsApp DB query failed ($(head -1 "${T}_err")) — orphan sweep skipped"; return 0
  fi
  sed -nE 's|^.*(Media/[^/]+@[^/]+/.*)$|\1|p' "${T}_refs" | sed -E 's/\.[^./]+$//' | sort -u > "${T}_ref_stems"
  ( cd "$msg" && find Media -mindepth 2 -type f \( -path 'Media/*@g.us/*' -o -path 'Media/*@s.whatsapp.net/*' \
      -o -path 'Media/*@lid/*' -o -path 'Media/*@newsletter/*' -o -path 'Media/*@broadcast/*' \) 2>/dev/null ) > "${T}_disk_all"
  ( cd "$msg" && find Media -mindepth 2 -type f -mtime +1 \( -path 'Media/*@g.us/*' -o -path 'Media/*@s.whatsapp.net/*' \
      -o -path 'Media/*@lid/*' -o -path 'Media/*@newsletter/*' -o -path 'Media/*@broadcast/*' \) 2>/dev/null ) > "${T}_disk"
  nref=$(wc -l < "${T}_ref_stems" | tr -d ' ')
  nmatch=$(awk 'NR==FNR{r[$0]=1;next}{s=$0;sub(/\.[^.\/]+$/,"",s); if(s in r) c++} END{print c+0}' "${T}_ref_stems" "${T}_disk_all")
  if [ "$nref" -gt 0 ] && [ "$nmatch" -eq 0 ]; then
    note warn "Safety stop: $nref referenced media in DB but none match files on disk (path format changed?). Orphan sweep skipped."
    return 0
  fi
  if [ "$nref" -eq 0 ] && [ -s "${T}_disk_all" ]; then
    note warn "Safety stop: DB references no media but files exist on disk. Orphan sweep skipped."
    return 0
  fi
  awk 'NR==FNR{r[$0]=1;next}{s=$0;sub(/\.[^.\/]+$/,"",s); if(!(s in r)) print}' "${T}_ref_stems" "${T}_disk" > "${T}_orphans"
  norph=$(wc -l < "${T}_orphans" | tr -d ' ')
  note info "DB references: $nref media | on disk: $(wc -l < "${T}_disk_all" | tr -d ' ') files ($nmatch referenced) | unreferenced: $norph"
  [ "$norph" -gt 0 ] || return 0
  ( cd "$msg" && tr '\n' '\0' < "${T}_orphans" | xargs -0 du -k 2>/dev/null ) |
    awk '{split($2,a,"/"); s[a[2]]+=$1; n[a[2]]++} END{for(j in s) if(s[j]>=1024) print s[j]"\t"n[j]"\t"j}' |
    sort -rn > "${T}_orphan_by_chat"
}

whatsapp_scan() {
  WA="$H/Library/Group Containers/group.net.whatsapp.WhatsApp.shared"
  local MEDIA="$WA/Message/Media" wa_up=false k n jid name d old label n0=${#IT_ID[@]}
  [ -d "$MEDIA" ] || return 0
  note info "media $(hsz "$MEDIA"), whole container $(hsz "$WA")"
  app_running WhatsApp && wa_up=true
  if $wa_up; then
    note warn "WhatsApp is running — quit it to delete logs/media. Candidates are listed below for reference."
  else
    safe_clear "$WA/Logs" "WhatsApp logs"
  fi
  sqlite3 -readonly -separator $'\t' "$WA/ChatStorage.sqlite" \
    "SELECT ZCONTACTJID, ifnull(ZPARTNERNAME,'') FROM ZWACHATSESSION;" > "$MC_TMP/whatsapp_names" 2>/dev/null
  whatsapp_orphan_scan

  mc_group "Unreferenced media (no message points to it; invisible in WhatsApp's storage view)"
  while IFS=$'\t' read -r k n jid; do
    [ -n "$jid" ] || continue
    label="$(fit "$(whatsapp_name "$jid")" 34) $(padl "$n" 6) unreferenced files"
    if $wa_up; then note report "$(printf '%8s  %s' "$(hkb "$k")" "$label")"
    else pick_item "$jid" "$label" "$k" whatsapp_del_orphans "" "$MEDIA/$jid"; fi
  done < "$MC_TMP/whatsapp_orphan_by_chat"

  if [ "$MEDIA_DAYS" -eq 0 ]; then mc_group "ALL media per chat (top 30 chats ≥ 10MB)"
  else mc_group "Media older than ${MEDIA_DAYS}d per chat (top 30 chats ≥ 10MB)"; fi
  : > "$MC_TMP/whatsapp_list"
  for d in "$MEDIA"/*/; do
    d="${d%/}"; k=$(kb "$d")
    [ "$k" -ge 10240 ] && printf '%s\t%s\n' "$k" "$d" >> "$MC_TMP/whatsapp_list"
  done
  while IFS=$'\t' read -r k d; do
    name=$(whatsapp_name "${d##*/}")
    if [ "$MEDIA_DAYS" -eq 0 ]; then old="$k"
    else old=$(find "$d" -type f -mtime +"$MEDIA_DAYS" -exec du -k {} + 2>/dev/null | awk '{s+=$1} END{print s+0}'); fi
    [ "$old" -lt 1024 ] && continue
    label="$(fit "$name" 34) (chat total $(hkb "$k"))"
    if $wa_up; then note report "$(printf '%8s  %s' "$(hkb "$old")" "$label")"
    else pick_item "$d" "$label" "$old" whatsapp_del_old "" "$d"; fi
  done < <(sort -rn "$MC_TMP/whatsapp_list" | head -30)

  [ ${#IT_ID[@]} -gt "$n0" ] && note warn "Deleted media shows as unavailable in WhatsApp and may not be re-downloadable."
  note tip "Alternative: WhatsApp > Settings > Storage and Data > Manage Storage > pick the chat."
  [ "$MEDIA_DAYS" -gt 0 ] && note tip "--only whatsapp --media-days 0 targets all (referenced) media in a chat."
  return 0
}

whatsapp_del_orphans() {   # $1 = chat jid
  local msg="$WA/Message" f
  [ -n "$1" ] || return 1
  grep -F "Media/$1/" "$MC_TMP/whatsapp_orphans" | while IFS= read -r f; do rm -f "$msg/$f"; done
  find "$msg/Media/$1" -mindepth 1 -type d -empty -delete 2>/dev/null
  return 0
}

whatsapp_del_old() {   # $1 = chat media dir
  guard_path "$1" || return 1
  case "$1" in "$WA/Message/Media/"*) ;; *) return 1 ;; esac
  if [ "$MEDIA_DAYS" -eq 0 ]; then find "$1" -type f -delete 2>/dev/null
  else find "$1" -type f -mtime +"$MEDIA_DAYS" -delete 2>/dev/null; fi
  return 0
}

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only whatsapp "$@"
fi
# @standalone-end
