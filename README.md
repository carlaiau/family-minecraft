# Family Minecraft map

## Introduction

This map records our shared family Minecraft world. The server runs locally on
my computer: I connect directly using Minecraft Java Edition, while our
children join over the local network from iPads running Minecraft Bedrock
Edition. Although we use different editions and devices, we all play together
in the same persistent world.

We believe Minecraft's cooperative nature makes it a valuable learning and
collaboration tool for our children and for ourselves. Shared projects invite
us to explain ideas, make plans, divide responsibilities, solve problems,
experiment, negotiate different priorities, and recover from mistakes
together. It gives the children room to exercise creativity and independence
while the adults participate as collaborators rather than simply directing the
activity. The things we build are enjoyable in their own right, but the real
value is in learning how to build them together.

## About this repository

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
