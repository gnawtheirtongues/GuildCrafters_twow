# GuildCraftDB

GuildCraftDB is a Turtle WoW addon for sharing and browsing guild crafting recipes.

## Features

- Guild-wide profession and recipe database.
- Queued and throttled guild sync transmission for better stability under load.
- Recipe search by profession and crafter.
- Collapsible recipe categories with a `Collapse/Expand` button.
- Predefined profession category grouping (consistent across characters).
- Bottom-right preview hover only (top-right list hover disabled).
- Recipe preview green text suppression for selected equipment categories (Blacksmithing/Engineering/Leatherworking/Tailoring rules).
- Crafter online/offline listing.
- SavedVariables export support.
- Recipe ownership sync by default (heavy metadata sync disabled for stability).
- Preview icon rendering intentionally disabled; tooltip hover still works over the icon area.

## Installation

### Turtle WoW Launcher (recommended)

1. Open the Turtle WoW Launcher.
2. Go to the Addons tab.
3. Click `+ Add new addon`.
4. Paste your repository URL.
5. Install and launch the game.

### Manual install

1. Download this repository as a ZIP.
2. Extract into `Interface/AddOns/`.
3. Ensure the folder is `Interface/AddOns/GuildCraftDB/`.

## Updating from older versions

1. Replace addon files.
2. Run:

```txt
/guildcraft cleanup
/guildcraft rewrite
/reload
```

## Commands

```txt
/guildcraft
/guildcraft cleanup
/guildcraft rewrite
```

## How it works

1. A player opens a profession window.
2. The addon scans recipe ownership data.
3. Sync messages are queued and throttled to avoid burst lag/crashes.
4. Guild members update local recipe ownership data.

## License

MIT License

