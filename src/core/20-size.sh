#!/bin/bash
# Size helpers. All sizes are integer KB.

kb() {
  [ -e "$1" ] || { echo 0; return; }
  du -skx "$1" 2>/dev/null | awk '{s=$1} END{print s+0}'
}

hkb() {
  awk -v k="${1:-0}" 'BEGIN{ if(k<0)k=0; s=k; u="KB";
    if(s>=1024){s/=1024;u="MB"} if(s>=1024){s/=1024;u="GB"} if(s>=1024){s/=1024;u="TB"}
    printf (u=="KB"?"%d%s":"%.1f%s"), s, u }'
}

hsz() { hkb "$(kb "$1")"; }

# "1.2GB" / "512MB" / "45.6kB" / "0B" / "1.2 GB (40%)" -> KB (decimal units treated as binary)
parse_size() {
  printf '%s\n' "$1" | awk '{
    s=$0; gsub(/[ ,]/,"",s)
    if (match(s,/^[0-9]+(\.[0-9]+)?/)==0) { print 0; exit }
    n=substr(s,1,RLENGTH)+0; u=toupper(substr(s,RLENGTH+1,1))
    m=1/1024
    if(u=="K")m=1; else if(u=="M")m=1024; else if(u=="G")m=1048576; else if(u=="T")m=1073741824
    printf "%d\n", n*m; exit }'
}

# Size of a measure target: a path, or "@listfile" (sum of the listed paths).
kb_meas() {
  local m="$1" p t=0 k
  case "$m" in
    '') echo 0 ;;
    @*)
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        k=$(kb "$p"); t=$((t + k))
      done < "${m#@}"
      echo "$t" ;;
    *) kb "$m" ;;
  esac
}

free_kb() { df -k "$H" 2>/dev/null | awk 'NR==2{print $4+0}'; }

# jxa JSONFILE 'JS body; `d` is the parsed JSON; return a string'
# Parses JSON with JavaScript for Automation (stock macOS), replacing python3.
jxa() {
  [ -s "$1" ] || return 0
  osascript -l JavaScript -e "function run(a){var s=\$.NSString.stringWithContentsOfFileEncodingError(a[0],4,null);if(!s)return '';var d;try{d=JSON.parse(s.js)}catch(e){return ''}var r=(function(d){$2})(d);return r?String(r):''}" "$1" 2>/dev/null
}
