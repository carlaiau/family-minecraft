#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)
cd "$REPO_ROOT"

EXPECTED_IMAGE='itzg/minecraft-server@sha256:9e09d64e8cab977f0152e1ca5f75d9ca972617cb946ef2f76acd4348bb950825'
EXPECTED_GEYSER_URL='https://download.geysermc.org/v2/projects/geyser/versions/2.11.0/builds/1204/downloads/spigot'
EXPECTED_FLOODGATE_URL='https://download.geysermc.org/v2/projects/floodgate/versions/2.2.5/builds/138/downloads/spigot'
EXPECTED_BLUEMAP_URL='https://github.com/BlueMap-Minecraft/BlueMap/releases/download/v5.22/bluemap-5.22-paper.jar'

for command_name in docker rg shasum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Dependency verification failed: required command not found: $command_name" >&2
    exit 1
  fi
done

shasum -a 256 -c dependencies.sha256

rg -Fq "image: $EXPECTED_IMAGE" docker-compose.yml
rg -Fq 'VERSION: "26.2"' docker-compose.yml
rg -Fq 'PAPER_BUILD: "87"' docker-compose.yml
rg -Fq "$EXPECTED_GEYSER_URL" docker-compose.yml
rg -Fq "$EXPECTED_FLOODGATE_URL" docker-compose.yml
rg -Fq "$EXPECTED_BLUEMAP_URL" docker-compose.yml

docker compose config --quiet

echo "Dependency pins and installed artifact checksums are valid."
