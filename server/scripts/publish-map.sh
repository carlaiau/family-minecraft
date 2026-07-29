#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)
cd "$REPO_ROOT"

COMMIT_MESSAGE=${1:-}
MAP_REPO_INPUT=${MAP_REPO:-../minecraft-map}
MAP_SOURCE_INPUT=${MAP_SOURCE:-./data/bluemap/web}
MAP_DEST_NAME=${MAP_DEST_NAME:-site}
MINECRAFT_SERVICE=${MINECRAFT_SERVICE:-minecraft}
MINECRAFT_CONTAINER=${MINECRAFT_CONTAINER:-minecraft-family}
BLUEMAP_RENDER_TIMEOUT=${BLUEMAP_RENDER_TIMEOUT:-1800}
BLUEMAP_POLL_SECONDS=${BLUEMAP_POLL_SECONDS:-10}
BLUEMAP_IDLE_CONFIRMATIONS=${BLUEMAP_IDLE_CONFIRMATIONS:-2}
BLUEMAP_TRIGGER_UPDATE=${BLUEMAP_TRIGGER_UPDATE:-true}
NETLIFY_EXPAND_GZIP=${NETLIFY_EXPAND_GZIP:-true}

SERVER_WAS_RUNNING=false
STAGING_ROOT=

usage() {
  cat <<EOF
Usage: $0 "Commit message"

Environment overrides:
  MAP_REPO                   Public map repository (default: ../minecraft-map)
  MAP_SOURCE                 BlueMap webroot (default: ./data/bluemap/web)
  MAP_DEST_NAME              Generated-site directory (default: site)
  BLUEMAP_RENDER_TIMEOUT     Render wait timeout in seconds (default: 1800)
  BLUEMAP_POLL_SECONDS       Render poll interval in seconds (default: 10)
  BLUEMAP_IDLE_CONFIRMATIONS Consecutive idle checks required (default: 2)
  BLUEMAP_TRIGGER_UPDATE     Queue a BlueMap update before polling (default: true)
  NETLIFY_EXPAND_GZIP        Expand .gz assets for static Netlify hosting (default: true)
EOF
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

is_true() {
  case "$1" in
    true | TRUE | 1 | yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

require_non_negative_integer() {
  local name=$1
  local value=$2
  [[ "$value" =~ ^[0-9]+$ ]] ||
    fail "$name must be a non-negative integer: $value"
}

cleanup() {
  local exit_status=$?
  trap - EXIT INT TERM

  if [[ -n "$STAGING_ROOT" && -d "$STAGING_ROOT" ]]; then
    rm -rf -- "$STAGING_ROOT"
  fi

  if [[ "$SERVER_WAS_RUNNING" == "true" ]]; then
    local is_running
    is_running=$(docker inspect -f '{{.State.Running}}' "$MINECRAFT_CONTAINER" 2>/dev/null || true)
    if [[ "$is_running" != "true" ]]; then
      echo "Restarting Minecraft server..."
      if ! docker compose start "$MINECRAFT_SERVICE" >/dev/null; then
        echo "Error: failed to restart Minecraft service: $MINECRAFT_SERVICE" >&2
        exit_status=1
      fi
    fi
  fi

  exit "$exit_status"
}

run_rcon() {
  docker exec "$MINECRAFT_CONTAINER" rcon-cli "$1"
}

wait_for_bluemap() {
  local start_time
  local now
  local elapsed
  local output
  local idle_count=0

  start_time=$(date +%s)
  echo "Waiting for BlueMap render tasks to finish..."

  while true; do
    if ! output=$(run_rcon "bluemap tasks" 2>&1); then
      echo "$output" >&2
      fail "could not read BlueMap task status"
    fi

    if printf '%s\n' "$output" | grep -Fqi "no pending tasks, all done"; then
      idle_count=$((idle_count + 1))
      echo "BlueMap is idle ($idle_count/$BLUEMAP_IDLE_CONFIRMATIONS)."
      if ((idle_count >= BLUEMAP_IDLE_CONFIRMATIONS)); then
        return 0
      fi
    else
      idle_count=0
      echo "BlueMap still has active or queued render tasks."
    fi

    now=$(date +%s)
    elapsed=$((now - start_time))
    if ((elapsed >= BLUEMAP_RENDER_TIMEOUT)); then
      fail "timed out after ${BLUEMAP_RENDER_TIMEOUT}s waiting for BlueMap"
    fi

    sleep "$BLUEMAP_POLL_SECONDS"
  done
}

collect_known_private_values() {
  local output_file=$1
  local log_file

  {
    printf '%s\n' "$REPO_ROOT"

    if [[ -f data/usercache.json ]]; then
      jq -r '.[] | .name, .uuid' data/usercache.json 2>/dev/null || true
    fi

    if [[ -f data/server.properties ]]; then
      awk -F= '
        $1 == "rcon.password" && length($2) > 0 {
          sub(/^[^=]*=/, "")
          print
        }
      ' data/server.properties
    fi

    if [[ -f data/.rcon-cli.env ]]; then
      awk -F= '
        $1 == "password" && length($2) > 0 {
          sub(/^[^=]*=/, "")
          gsub(/^["'\'']|["'\'']$/, "")
          print
        }
      ' data/.rcon-cli.env
    fi

    if [[ -d data/logs ]]; then
      while IFS= read -r -d '' log_file; do
        case "$log_file" in
          *.gz) gzip -cd -- "$log_file" 2>/dev/null || true ;;
          *) sed -n '1,999999p' "$log_file" ;;
        esac
      done < <(find data/logs -type f \( -name '*.log' -o -name '*.log.gz' \) -print0) |
        rg --pcre2 -o '(?<![0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])' || true
    fi
  } |
    awk 'length($0) >= 3' |
    LC_ALL=C sort -u >"$output_file"
}

expand_gzip_assets() {
  local root=$1
  local compressed_file
  local expanded_file
  local temporary_file
  local count=0

  while IFS= read -r -d '' compressed_file; do
    expanded_file=${compressed_file%.gz}
    temporary_file="${expanded_file}.publishing-tmp"
    gzip -cd -- "$compressed_file" >"$temporary_file"
    mv -f -- "$temporary_file" "$expanded_file"
    rm -f -- "$compressed_file"
    count=$((count + 1))
  done < <(find "$root" -type f -name '*.gz' -print0)

  if ((count > 0)); then
    echo "Expanded $count gzip-compressed BlueMap assets for Netlify."
  fi
}

[[ -n "${COMMIT_MESSAGE//[[:space:]]/}" ]] || {
  usage >&2
  exit 2
}

for command_name in date docker find git grep gzip jq mktemp rg rsync sed sort; do
  command -v "$command_name" >/dev/null 2>&1 ||
    fail "required command not found: $command_name"
done

require_non_negative_integer "BLUEMAP_RENDER_TIMEOUT" "$BLUEMAP_RENDER_TIMEOUT"
require_non_negative_integer "BLUEMAP_POLL_SECONDS" "$BLUEMAP_POLL_SECONDS"
require_non_negative_integer "BLUEMAP_IDLE_CONFIRMATIONS" "$BLUEMAP_IDLE_CONFIRMATIONS"
((BLUEMAP_RENDER_TIMEOUT > 0)) ||
  fail "BLUEMAP_RENDER_TIMEOUT must be greater than zero"
((BLUEMAP_IDLE_CONFIRMATIONS > 0)) ||
  fail "BLUEMAP_IDLE_CONFIRMATIONS must be greater than zero"

[[ "$MAP_DEST_NAME" != */* && "$MAP_DEST_NAME" != "." && "$MAP_DEST_NAME" != ".." ]] ||
  fail "MAP_DEST_NAME must be one directory name"

[[ -d "$MAP_REPO_INPUT" ]] ||
  fail "public map repository not found: $MAP_REPO_INPUT"
MAP_REPO_ABS=$(cd "$MAP_REPO_INPUT" && pwd -P)
MAP_REPO_TOP=$(git -C "$MAP_REPO_ABS" rev-parse --show-toplevel 2>/dev/null || true)
[[ "$MAP_REPO_TOP" == "$MAP_REPO_ABS" ]] ||
  fail "MAP_REPO must be the root of a Git repository: $MAP_REPO_ABS"
[[ "$MAP_REPO_ABS" != "$REPO_ROOT" ]] ||
  fail "the public map repository must be separate from minecraft-server"

if [[ -n "$(git -C "$MAP_REPO_ABS" status --porcelain)" ]]; then
  fail "public map repository has uncommitted changes; commit or discard them first"
fi

[[ -d "$MAP_SOURCE_INPUT" ]] ||
  fail "BlueMap webroot not found: $MAP_SOURCE_INPUT"
MAP_SOURCE_ABS=$(cd "$MAP_SOURCE_INPUT" && pwd -P)

case "$MAP_SOURCE_ABS" in
  "$REPO_ROOT/data/world" | "$REPO_ROOT/data/world/"* | \
    "$REPO_ROOT/data/world_nether" | "$REPO_ROOT/data/world_nether/"* | \
    "$REPO_ROOT/data/world_the_end" | "$REPO_ROOT/data/world_the_end/"* | \
    "$REPO_ROOT/data/playerdata" | "$REPO_ROOT/data/playerdata/"* | \
    "$REPO_ROOT/data/plugins" | "$REPO_ROOT/data/plugins/"* | \
    "$REPO_ROOT/data/logs" | "$REPO_ROOT/data/logs/"*)
    fail "MAP_SOURCE points at private server data: $MAP_SOURCE_ABS"
    ;;
esac

container_running=$(docker inspect -f '{{.State.Running}}' "$MINECRAFT_CONTAINER" 2>/dev/null || true)
[[ "$container_running" == "true" ]] ||
  fail "Minecraft container is not running: $MINECRAFT_CONTAINER"

SERVER_WAS_RUNNING=true
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

STAGING_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/minecraft-map-publish.XXXXXX")
STAGING_SITE="$STAGING_ROOT/site"
KNOWN_VALUES_FILE="$STAGING_ROOT/known-private-values.txt"
mkdir -p "$STAGING_SITE"

echo "Flushing Minecraft world data..."
run_rcon "save-all flush"

if is_true "$BLUEMAP_TRIGGER_UPDATE"; then
  echo "Queuing a BlueMap update..."
  run_rcon "bluemap update"
fi

wait_for_bluemap

echo "Stopping Minecraft server cleanly..."
docker compose stop "$MINECRAFT_SERVICE"

live_file_count=$(
  find "$MAP_SOURCE_ABS" -path '*/maps/*/live/*' -type f -print |
    awk 'END { print NR + 0 }'
)
if ((live_file_count > 0)); then
  echo "Excluding $live_file_count BlueMap live-data files from the public export."
fi

echo "Staging BlueMap static site..."
rsync -a \
  --exclude='/maps/*/live/' \
  --exclude='*.php' \
  "$MAP_SOURCE_ABS/" \
  "$STAGING_SITE/"

if is_true "$NETLIFY_EXPAND_GZIP"; then
  expand_gzip_assets "$STAGING_SITE"
fi

collect_known_private_values "$KNOWN_VALUES_FILE"
"$SCRIPT_DIR/check-map-privacy.sh" "$STAGING_SITE" "$KNOWN_VALUES_FILE"

MAP_DEST="$MAP_REPO_ABS/$MAP_DEST_NAME"
mkdir -p "$MAP_DEST"

echo "Updating public map site..."
rsync -a --delete "$STAGING_SITE/" "$MAP_DEST/"

if [[ -z "$(git -C "$MAP_REPO_ABS" status --porcelain -- "$MAP_DEST_NAME")" ]]; then
  echo "No map changes to publish."
  echo "Checking that the public map branch is pushed..."
  git -C "$MAP_REPO_ABS" push
  exit 0
fi

git -C "$MAP_REPO_ABS" add --all -- "$MAP_DEST_NAME"
git -C "$MAP_REPO_ABS" commit -m "$COMMIT_MESSAGE" -- "$MAP_DEST_NAME"
git -C "$MAP_REPO_ABS" push

echo "Published BlueMap site successfully."
