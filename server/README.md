# Minecraft server and BlueMap publication

This directory documents the configuration used to run the private family
Minecraft server and publish its map. It deliberately contains no world data,
player data, credentials, logs, generated BlueMap data, or plugin binaries.

The files are a sanitized reference copy. The live server runs from a separate
private repository with this layout:

```text
parent-folder/
├── minecraft-server/
│   ├── docker-compose.yml
│   ├── dependencies.sha256
│   ├── scripts/
│   └── data/                   # private and ignored
└── minecraft-map/              # this public repository
    ├── server/                 # public reference configuration
    └── site/                   # generated BlueMap export
```

## How the server works

Docker Compose runs one `itzg/minecraft-server` container:

- Paper provides the Java Minecraft server on TCP port `25565`.
- Geyser translates Bedrock clients and listens on UDP port `19132`.
- Floodgate allows the configured Bedrock authentication flow.
- ViaVersion supplies protocol compatibility.
- BlueMap renders the overworld, Nether, and End into
  `data/bluemap/web`; its integrated webserver is disabled.
- The entire mutable server state is mounted at `./data:/data` and stays in the
  private repository.

The container image is pinned by digest. Paper, Geyser, Floodgate, and BlueMap
are pinned to exact versions or builds in `docker-compose.yml`. Installed JAR
hashes, including ViaVersion, are recorded in `dependencies.sha256`.

## Start and operate

These commands are run from the private server repository, not this public
reference directory:

```bash
docker compose up -d
docker compose logs -f minecraft
docker compose stop
docker compose start
docker compose down
```

`docker compose down` removes the container but preserves the `data/` volume
directory. Back up `data/` before dependency upgrades.

Optional, non-secret settings can be copied from `.env.example` to `.env`.
Never commit `.env`, server-generated configuration, or anything under `data/`
to this repository.

## BlueMap privacy configuration

The files under `bluemap-config/` show the material settings applied after
BlueMap generates its default configuration. The important publication/privacy
choices are:

- the BlueMap web app writes to `bluemap/web`;
- the integrated BlueMap webserver is disabled;
- live player markers and persisted player snapshots are disabled;
- player skin downloads and metrics are disabled;
- file storage is used for the rendered map;
- all three standard dimensions are rendered.
- the default camera opens at
  `#world:89:53:-106:108:2.54:1.08:0:0:perspective`.

These files contain only the settings that differ from, or are important
alongside, BlueMap defaults. Apply their values to the generated configuration
in the private server's `data/plugins/BlueMap/` directory.

## Publish the map

From the private server repository:

```bash
./scripts/publish-map.sh "Describe the map update"
```

The script performs this sequence:

1. Requires a clean, separate public map Git repository and a running server.
2. Runs `save-all flush` and queues a BlueMap update.
3. Polls `bluemap tasks` until BlueMap reports idle twice.
4. Stops Minecraft for a consistent copy.
5. Copies only the BlueMap static webroot into a temporary directory.
6. Excludes `maps/*/live/` and all PHP helpers, and expands gzip assets for
   ordinary static Netlify hosting.
7. Blocks publication if the staged site contains UUIDs, known player/server
   values, local paths, raw server artifacts, symlinks, server metadata, or
   live-map files.
8. Replaces only `minecraft-map/site`, commits it, and pushes it.
9. Restarts Minecraft through an exit trap after success or failure.

The default sibling layout is shown above. Override paths or timing when needed:

```bash
MAP_REPO=/path/to/minecraft-map \
MAP_SOURCE=./data/bluemap/web \
BLUEMAP_RENDER_TIMEOUT=1800 \
./scripts/publish-map.sh "Updated map"
```

Other supported settings are documented by running the publisher without a
commit message.

## Verify dependency pins

After the server has downloaded the pinned artifacts:

```bash
./scripts/verify-dependencies.sh
```

The script verifies the installed JAR hashes, checks that Compose still
contains each expected pin, and validates the resolved Compose configuration.

## Public/private boundary

Safe to publish:

- this Compose definition and `.env.example`;
- the scripts in this directory;
- the selected BlueMap configuration values;
- dependency versions, URLs, and cryptographic hashes;
- the generated static map only after the privacy gate passes.

Keep private:

- `data/`, worlds, region files, player data, logs, bans, whitelist, and ops;
- RCON passwords, `.env`, generated `server.properties`, IP addresses, and
  local filesystem paths;
- BlueMap render state, debug logs, live endpoints, skins, and plugin binaries.
