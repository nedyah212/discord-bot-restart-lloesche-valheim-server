#!/usr/bin/env bash
# valheim.sh - status | restart [--force]
set -euo pipefail

CONTAINER="${VALHEIM_CONTAINER:-valheim}"

die() { echo "error: $*" >&2; exit 2; }

command -v docker >/dev/null || die "docker not found"
docker inspect "$CONTAINER" >/dev/null 2>&1 || die "container '$CONTAINER' not found"

is_running() {
  [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" == "true" ]]
}

# Prints the player count from the last "now N player(s)" log line since the
# container last started, or "unknown" if no such line exists yet.
player_count() {
  local started n
  started=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER")
  n=$(docker logs --since "$started" "$CONTAINER" 2>&1 \
    | grep -oE 'now [0-9]+ player\(s\)' | tail -n1 | grep -oE '[0-9]+' || true)
  echo "${n:-unknown}"
}

# Prints the most recent PlayFab join code since the container started, or "unknown".
join_code() {
  local started c
  started=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER")
  c=$(docker logs --since "$started" "$CONTAINER" 2>&1 \
    | grep -oE 'join code [0-9]+' | tail -n1 | grep -oE '[0-9]+' || true)
  echo "${c:-unknown}"
}

cmd_status() {
  if ! is_running; then
    echo "valheim: stopped"
    exit 1
  fi
  local since players code
  since=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER")
  players=$(player_count)
  code=$(join_code)
  echo "valheim: running (since $since), players: $players, join code: $code"
}

cmd_restart() {
  local force="${1:-}"
  if is_running && [[ "$force" != "--force" ]]; then
    local players
    players=$(player_count)
    if [[ "$players" == "unknown" ]]; then
      echo "valheim: can't determine player count (still booting?), not restarting"
      exit 4
    fi
    if (( players > 0 )); then
      echo "valheim: $players player(s) online, not restarting"
      exit 3
    fi
  fi
  docker restart "$CONTAINER" >/dev/null
  echo "valheim: restarted"
}

case "${1:-}" in
  status)  cmd_status ;;
  restart) shift; cmd_restart "${1:-}" ;;
  *) echo "usage: $0 {status|restart [--force]}" >&2; exit 2 ;;
esac
