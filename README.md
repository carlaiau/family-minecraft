# Family Minecraft map

This repository contains only the generated static BlueMap website for the
family Minecraft world. Netlify publishes the contents of `site/`.

The Minecraft server, raw world, player records, logs, plugin configuration,
and BlueMap working data are kept in a separate private repository. They must
never be copied here.

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
