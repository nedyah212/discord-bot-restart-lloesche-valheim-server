#!/usr/bin/env bash
# valheim.sh - status | start | stop [--force] | restart [--force]
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

# Exits 4 if the player count can't be read, 3 if anyone is online.
# $1 is the verb for the message, e.g. "restarting" or "stopping".
require_empty() {
  local verb="$1" players
  players=$(player_count)
  if [[ "$players" == "unknown" ]]; then
    echo "valheim: can't determine player count (still booting?), not $verb"
    exit 4
  fi
  if (( players > 0 )); then
    echo "valheim: $players player(s) online, not $verb"
    exit 3
  fi
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

cmd_start() {
  if is_running; then
    echo "valheim: already running"
    exit 5
  fi
  docker start "$CONTAINER" >/dev/null
  echo "valheim: started (join code changes on every start, check status in a couple of minutes)"
}

cmd_stop() {
  local force="${1:-}"
  if ! is_running; then
    echo "valheim: already stopped"
    exit 1
  fi
  [[ "$force" == "--force" ]] || require_empty "stopping"
  docker stop "$CONTAINER" >/dev/null
  echo "valheim: stopped"
}

cmd_restart() {
  local force="${1:-}"
  if is_running && [[ "$force" != "--force" ]]; then
    require_empty "restarting"
  fi
  docker restart "$CONTAINER" >/dev/null
  echo "valheim: restarted"
}

case "${1:-}" in
  status)  cmd_status ;;
  start)   cmd_start ;;
  stop)    shift; cmd_stop "${1:-}" ;;
  restart) shift; cmd_restart "${1:-}" ;;
  *) echo "usage: $0 {status|start|stop [--force]|restart [--force]}" >&2; exit 2 ;;
esac
