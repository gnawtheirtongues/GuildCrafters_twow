# GuildCraftDB

GuildCraftDB is a Turtle WoW addon for sharing and browsing guild crafting recipes.

## Features

- Guild-wide profession and recipe database
- Recipe search by crafter and profession
- Engineering recipe handling fixed for Turtle WoW
- SavedVariables export support
- Crafter name and online-state support

## Installation

### Turtle WoW Launcher (recommended)

1. Open the **Turtle WoW Launcher**
2. Go to the **Addons** tab
3. Click **+ Add new addon**
4. Paste this repository URL:

https://github.com/YOURNAME/GuildCraftDB.git


5. Install and launch the game.

---

### Manual Install

1. Download this repository as a ZIP.
2. Extract into:


Interface/AddOns/


3. Your folder should look like:


Interface/AddOns/GuildCraftDB/
GuildCraftDB.toc
GuildCraftDB.lua
GuildCraftSafeLib_hoverfix.lua


---

## Updating from older versions

Replace the addon files, then run:


/guildcraft cleanup
/guildcraft rewrite
/reload


---

## Commands


/guildcraft
/guildcraft cleanup
/guildcraft rewrite


---

## How the addon works

1. A player opens a profession window
2. The addon scans the recipes
3. Recipe data is sent to guild members
4. Everyone's database updates automatically



## License

MIT License
