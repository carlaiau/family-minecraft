# Family Minecraft map

This repository contains:

- `site/`: the generated static BlueMap website published by Netlify.
- `server/`: a sanitized, reproducible description of the Minecraft server and
  the scripts used to publish BlueMap safely.

The running Minecraft server, raw world, player records, logs, generated plugin
configuration, credentials, and BlueMap working data remain in a separate
private repository. They must never be copied here.

Do not edit `site/` by hand. It is replaced and published deliberately from a
sibling checkout of the private server repository:

```text
parent-folder/
├── minecraft-server/
└── minecraft-map/
```

From `minecraft-server`, publish with:

```bash
./scripts/publish-map.sh "Describe the map update"
```

The publisher waits for BlueMap, stops Minecraft for a consistent snapshot,
excludes live-player data, blocks identifiable metadata, replaces only `site/`,
commits and pushes this repository, and restarts Minecraft even if publication
fails.

See [`server/README.md`](server/README.md) for the server architecture, pinned
dependencies, BlueMap privacy configuration, operating commands, and a
step-by-step explanation of the publication process.
