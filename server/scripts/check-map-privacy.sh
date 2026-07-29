#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: check-map-privacy.sh WEBROOT [KNOWN_VALUES_FILE]

Checks a staged BlueMap static webroot for data that should not be published.
KNOWN_VALUES_FILE may contain one sensitive literal per line, such as player
names, server addresses, or local filesystem paths. Values are never printed.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

WEBROOT_INPUT=$1
KNOWN_VALUES_FILE=${2:-}

if [[ ! -d "$WEBROOT_INPUT" ]]; then
  echo "Privacy check failed: webroot is not a directory: $WEBROOT_INPUT" >&2
  exit 2
fi

for command_name in find gzip rg; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Privacy check failed: required command not found: $command_name" >&2
    exit 2
  fi
done

if [[ -n "$KNOWN_VALUES_FILE" && ! -f "$KNOWN_VALUES_FILE" ]]; then
  echo "Privacy check failed: known-values file not found: $KNOWN_VALUES_FILE" >&2
  exit 2
fi

WEBROOT=$(cd "$WEBROOT_INPUT" && pwd -P)
FINDINGS_FILE=$(mktemp "${TMPDIR:-/tmp}/minecraft-map-privacy.XXXXXX")

cleanup() {
  rm -f -- "$FINDINGS_FILE"
}
trap cleanup EXIT

record_finding() {
  local category=$1
  local path=$2
  local relative_path=${path#"$WEBROOT"/}
  printf '%s\t%s\n' "$category" "$relative_path" >>"$FINDINGS_FILE"
}

scan_text_regex() {
  local category=$1
  local pattern=$2
  local path

  while IFS= read -r path; do
    [[ -n "$path" ]] && record_finding "$category" "$path"
  done < <(rg -I -l --pcre2 -- "$pattern" "$WEBROOT" 2>/dev/null || true)
}

scan_structured_text_regex() {
  local category=$1
  local pattern=$2
  local path

  while IFS= read -r path; do
    [[ -n "$path" ]] && record_finding "$category" "$path"
  done < <(
    rg -I -l --pcre2 \
      -g '*.json' \
      -g '*.html' \
      -g '*.txt' \
      -g '*.xml' \
      -- "$pattern" "$WEBROOT" 2>/dev/null || true
  )
}

scan_compressed_json_regex() {
  local category=$1
  local pattern=$2
  local path

  while IFS= read -r -d '' path; do
    if gzip -cd -- "$path" 2>/dev/null |
      rg --pcre2 -- "$pattern" >/dev/null; then
      record_finding "$category" "$path"
    fi
  done < <(find "$WEBROOT" -type f -name '*.json.gz' -print0)
}

while IFS= read -r -d '' path; do
  record_finding "symbolic link" "$path"
done < <(find "$WEBROOT" -type l -print0)

while IFS= read -r -d '' path; do
  record_finding "raw server or world artifact" "$path"
done < <(
  find "$WEBROOT" \
    \( -type f -o -type d \) \
    \( \
      -name '*.mca' -o \
      -name 'level.dat' -o \
      -name 'level.dat_old' -o \
      -name 'session.lock' -o \
      -name 'server.properties' -o \
      -name 'ops.json' -o \
      -name 'whitelist.json' -o \
      -name 'banned-players.json' -o \
      -name 'banned-ips.json' -o \
      -name 'usercache.json' -o \
      -name '*.php' -o \
      -name '*.pem' -o \
      -name '.rcon-cli*' -o \
      -path '*/playerdata/*' -o \
      -path '*/players/data/*' -o \
      -path '*/plugins/*' -o \
      -path '*/logs/*' \
    \) \
    -print0
)

while IFS= read -r -d '' path; do
  record_finding "live map data" "$path"
done < <(find "$WEBROOT" -path '*/maps/*/live/*' -print0)

UUID_PATTERN='(?i)(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f])'
INTERNAL_PATH_PATTERN='(/Users/|/home/|/private/var/|[A-Za-z]:[\\/](Users|Documents and Settings)[\\/])'
HIDDEN_MARKER_PATTERN='(?i)"?default[-_]?hidden"?[[:space:]]*[:=][[:space:]]*true'
SERVER_METADATA_PATTERN='(?i)"?(server[-_]?(ip|address|host(name)?)|rcon|motd)"?[[:space:]]*[:=]'

scan_text_regex "UUID" "$UUID_PATTERN"
scan_text_regex "internal filesystem path" "$INTERNAL_PATH_PATTERN"
scan_structured_text_regex "hidden marker configuration" "$HIDDEN_MARKER_PATTERN"
scan_structured_text_regex "server metadata" "$SERVER_METADATA_PATTERN"

scan_compressed_json_regex "UUID" "$UUID_PATTERN"
scan_compressed_json_regex "internal filesystem path" "$INTERNAL_PATH_PATTERN"
scan_compressed_json_regex "hidden marker configuration" "$HIDDEN_MARKER_PATTERN"
scan_compressed_json_regex "server metadata" "$SERVER_METADATA_PATTERN"

if [[ -n "$KNOWN_VALUES_FILE" && -s "$KNOWN_VALUES_FILE" ]]; then
  while IFS= read -r path; do
    [[ -n "$path" ]] && record_finding "known private value" "$path"
  done < <(rg -I -l -F -f "$KNOWN_VALUES_FILE" -- "$WEBROOT" 2>/dev/null || true)

  while IFS= read -r -d '' path; do
    if gzip -cd -- "$path" 2>/dev/null |
      rg -F -f "$KNOWN_VALUES_FILE" >/dev/null; then
      record_finding "known private value" "$path"
    fi
  done < <(find "$WEBROOT" -type f -name '*.json.gz' -print0)
fi

if [[ -s "$FINDINGS_FILE" ]]; then
  echo "Privacy check failed. The staged map contains potentially private data:" >&2
  sort -u "$FINDINGS_FILE" |
    while IFS=$'\t' read -r category relative_path; do
      printf '  - %s: %s\n' "$category" "$relative_path" >&2
    done
  echo "No values were printed. Review or remove the reported files before publishing." >&2
  exit 1
fi

echo "Privacy check passed."
