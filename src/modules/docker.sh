#!/bin/bash
# Module: docker — containers, volumes, images, build cache, colima VM.

docker_meta() { MOD_TITLE="Docker / colima"; }

docker_scan() {
  local LIMA="$H/.colima/_lima" id name image size since v s r
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker system df --format '{{.Type}}\t{{.Reclaimable}}' > "$MC_TMP/docker_df" 2>/dev/null
    while IFS= read -r r; do note report "$r"; done < <(docker system df 2>/dev/null)

    mc_group "Stopped containers (devcontainers rebuild on 'Reopen in Container')"
    while IFS=$'\t' read -r id name image size since; do
      [ -n "$id" ] || continue
      size="${size%% *}"
      pick_item "$id" "$(fit "$name" 28) $(fit "$image" 34) $since" "$(parse_size "$size")" docker_del_container "$size"
    done < <(docker ps -a -s --filter status=exited --filter status=created --filter status=dead \
               --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Size}}\t{{.RunningFor}}' 2>/dev/null)

    docker system df -v 2>/dev/null | awk '/^Local Volumes space usage/{f=1;next} f&&/^VOLUME NAME/{h=1;next} f&&h&&NF==0{exit} f&&h{print $1"\t"$NF}' > "$MC_TMP/docker_vols"
    mc_group "Unused volumes (may hold devcontainer DBs, node_modules, shell history)"
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      s=$(awk -F'\t' -v v="$v" '$1==v{print $2}' "$MC_TMP/docker_vols")
      pick_item "$v" "$v" "$(parse_size "${s:-0}")" docker_del_volume "${s:-?}"
    done < <(docker volume ls -qf dangling=true 2>/dev/null)

    mc_group "Images, build cache, networks"
    s=$(awk -F'\t' '$1=="Images"{print $2}' "$MC_TMP/docker_df")
    [ "$(parse_size "${s:-0}")" -gt 0 ] && pick_item images "unused images (docker image prune -af; may not be re-downloadable offline)" \
      "$(parse_size "$s")" docker_prune_images "${s%% *}"
    s=$(awk -F'\t' '$1=="Build Cache"{print $2}' "$MC_TMP/docker_df")
    [ "$(parse_size "${s:-0}")" -gt 0 ] && safe_cmd builder "build cache (docker builder prune -af)" docker_prune_builder "$(parse_size "$s")" "${s%% *}"
    safe_cmd networks "unused networks (docker network prune -f)" docker_prune_networks 0 "-"

    if command -v colima >/dev/null 2>&1 && colima status >/dev/null 2>&1; then
      safe_cmd fstrim "fstrim inside colima VM (returns freed blocks to macOS)" docker_fstrim 0 "-" "$LIMA"
      while IFS= read -r r; do note report "$r"; done < <(colima list 2>/dev/null)
    fi
  else
    note skip "docker not reachable — start colima/Docker to clean images, containers and volumes"
  fi
  if command -v colima >/dev/null 2>&1 && [ -d "$LIMA" ]; then
    if $RECLAIM_DOCKER_VM; then
      mc_group "colima VM rebuild"
      pick_item colima "rebuild colima VM — stops containers; ALL images, containers and volumes are lost" \
        "$(kb "$LIMA")" docker_colima_rebuild "" "$LIMA"
    else
      note info "colima VM disk on host: $(hsz "$LIMA")  (--reclaim-docker-vm offers a rebuild from scratch)"
    fi
  fi
  return 0
}

docker_del_container()  { docker rm -v "$1"; }
docker_del_volume()     { docker volume rm "$1"; }
docker_prune_images()   { docker image prune -af; }
docker_prune_builder()  { docker builder prune -af; }
docker_prune_networks() { docker network prune -f; }
docker_fstrim()         { colima ssh -- sudo fstrim -av; }
docker_colima_rebuild() { colima stop; colima delete -f && colima start; }

# @standalone-begin
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
  mc_main --only docker "$@"
fi
# @standalone-end
