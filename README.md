# Family Minecraft

This map records our shared family world, served locally and played together using Java on my computer and Bedrock on iOS.

We believe Minecraft’s cooperative nature makes it a valuable learning tool for our six and and four year old, and for us. Building together encourages creativity, communication, planning, problem-solving, and learning from mistakes. It gives the children space to explore independently while we participate as collaborators. The real value isn’t just what we create, but learning how to create it together.

## About this repository

This repository contains:

- `site/`: the generated static BlueMap website.
- `server/`: a sanitized, reproducible description of the Minecraft server and
  the scripts used to publish BlueMap safely.

The running Minecraft server, raw world, player records, logs, generated plugin
configuration, credentials, and BlueMap working data remain in a separate
private repository.

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
