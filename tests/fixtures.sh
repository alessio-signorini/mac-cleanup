#!/bin/bash
# Fake $HOME fixture shared by tests/run.sh and dev/sandbox.sh. Source it, then: make_home DIR [bad-db]

mkf() {  # mkf PATH SIZE_KB [old]
  mkdir -p "$(dirname "$1")"
  dd if=/dev/zero of="$1" bs=1024 count="$2" 2>/dev/null
  [ "${3:-}" = old ] && touch -t 202401010000 "$1"
  return 0
}

WA_REL="Library/Group Containers/group.net.whatsapp.WhatsApp.shared"
make_home() {   # make_home DIR [bad-db]
  local h="$1" wa chat
  rm -rf "$h"; mkdir -p "$h"
  mkf "$h/Library/Caches/com.example.app/blob" 2048
  mkf "$h/Library/Caches/Google/blob" 2048
  mkf "$h/Library/Logs/app/x.log" 2048
  mkf "$h/.claude/debug/d.log" 2048
  mkf "$h/.claude/projects/p/old.jsonl" 2048 old
  mkf "$h/Downloads/old.dmg" 6144 old
  mkf "$h/Downloads/older.zip" 8192 old
  mkf "$h/Downloads/new.dmg" 6144
  mkf "$h/code/proj/node_modules/pkg/index.js" 11264 old
  mkf "$h/code/proj/package.json" 1 old
  touch -t 202401010000 "$h/code/proj/node_modules/pkg" "$h/code/proj/node_modules" "$h/code/proj"
  wa="$h/$WA_REL"; chat="$wa/Message/Media/123@s.whatsapp.net"
  mkf "$chat/a/b/ref.jpg" 512 old
  mkf "$chat/a/b/ref-thumb.jpg" 16 old
  mkf "$chat/c/d/orphan-old.jpg" 2048 old
  mkf "$chat/e/f/orphan-new.jpg" 2048
  local refpath="/private/var/mobile/Containers/Shared/AppGroup/X/Message/Media/123@s.whatsapp.net/a/b/ref.jpg"
  local thumbpath="Media/123@s.whatsapp.net/a/b/ref-thumb.jpg"
  if [ "${2:-}" = bad-db ]; then
    refpath="Media/999@s.whatsapp.net/zz/zz/nothing.jpg"; thumbpath="Media/999@s.whatsapp.net/zz/zz/nothing-thumb.jpg"
  fi
  sqlite3 "$wa/ChatStorage.sqlite" <<SQL
CREATE TABLE ZWAMEDIAITEM (Z_PK INTEGER PRIMARY KEY, ZMEDIALOCALPATH VARCHAR, ZTHUMBNAILLOCALPATH VARCHAR, ZXMPPTHUMBPATH VARCHAR);
CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID VARCHAR, ZPARTNERNAME VARCHAR);
INSERT INTO ZWAMEDIAITEM VALUES (1, '$refpath', '$thumbpath', '');
INSERT INTO ZWACHATSESSION VALUES (1, '123@s.whatsapp.net', 'Test Chat');
SQL
}
