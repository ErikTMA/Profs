# Profs!

A World of Warcraft addon for **WoW Forever** that levels your crafting professions
for you: it plans the cheapest, fastest or a balanced route from your current skill
to your target, builds the complete shopping list, and walks you through it from an
extra column built into the profession window.

## Features

- **Leveling routes** for every crafting profession, including Cooking and First
  Aid. Modes: **Cheapest** (default), **Fastest**, **Balanced**: three buttons in
  the Profs! column, the active one shown pressed in; your choice is remembered per
  profession.
- **Expected craft counts** from the real skill-up chance at each skill level.
  Trainer and vendor recipes are preferred; drop, quest and reputation recipes are
  only used if you already know them or allow them.
- **Where to learn each recipe**: trainer fee, vendor and location, plus when to
  train the next rank (Journeyman, Expert, ...).
- **Shopping list** for the whole route, counted against what you already have in
  your bags, bank, mail and on your alts. Intermediates such as cloth bolts are
  crafted when that is cheaper.
- **What to do with the results**: sell, vendor, disenchant or keep.
- **Your own choices**: exclude recipes, lock a skill range to a recipe, save and
  load named routes.
- **Profession recommendations**: which pair of professions is cheapest to level
  together (for example Tailoring + Enchanting).
- **Leveling gear helper**: craftable upgrades for your level, scored with Pawn if
  you use it, otherwise with built-in stat weights.
- **Level-up alerts**: when you ding, a small notice lists craftable gear that just
  became an upgrade. Click a row to open the recipe.
- **Auction House prices** from your own scans, TradeSkillMaster or Auctionator,
  whichever is freshest. Scans only run when you press a button at the Auction
  House.

## Installation

1. Download **`Profs-<version>.zip`** from the
   [latest release](https://github.com/ErikTMA/Profs/releases/latest).
2. Unzip it into your AddOns folder,
   `World of Warcraft/_forever_/Interface/AddOns/` (the exact game folder name may
   differ on your install). The zip already contains the `Profs` folder, so the
   result is `.../AddOns/Profs/Profs.toc`.
3. Start the game and make sure **Profs!** is enabled in the AddOns list on the
   character screen (category: *Professions*).

To update, delete the old `Profs` folder and unzip the new release. Your settings
and saved routes are kept (they live in the game's SavedVariables, not in the
addon folder).

From source instead: `git clone https://github.com/ErikTMA/Profs.git` inside the
AddOns folder (or use **Code > Download ZIP** and rename `Profs-main` to `Profs`).

Optional addons that Profs! uses when present: **TradeSkillMaster**, **Auctionator**,
**Pawn**. None of them are required.

## Usage

Open any profession window: it gets a third column on the right, after the recipe
list and the recipe details, with the route, the shopping list and the next recipe
to craft. The column is part of the window: it moves and closes with it, follows the
profession tab you select (it is not shown on the professions overview), and leaves the profession tabs along the window's right
edge free to click. `/profs show` hides or shows the column (remembered per
character). You can also open Profs! from the
addon button on the minimap (left-click: route, right-click: profession
recommendations, shift-click: gear upgrades).

### Craftable gear upgrades

Recipes bought with a currency (for example Merchant's Favor from the Azeroth
Commerce Authority) count for gear suggestions; they are not used in leveling routes.

Patterns that drop are listed too, marked **drop**. Hover one to see which mobs drop
it: level, elite or boss, zone and coordinates (dungeon mobs: the dungeon), and the
drop chance with how many kills it was measured on. World drops say how many mobs
drop them and show the best chances. Drop patterns are often on the Auction House.

Open your character window (C): when you can craft gear that beats what you wear,
Profs! adds a **Craftable upgrades** column to it, right of your stats, listing each
item with its profession and required level. Hover a row to see where to get the
recipe; click it to open the recipe. When there
is nothing to upgrade, the character window stays as it is. Your professions and your
alts' count, scored with Pawn if you use it.

The **Gear upgrades** button in the Profs! profession column, shift-click on the
Profs! entry in the minimap's addon menu, and `/profs gear` all open the character
window on that page (and tell you in chat when there are no upgrades).

| Command | What it does |
|---|---|
| `/profs show` | hide or show the Profs! column in the profession window |
| `/profs recommend` | profession pair recommendations |
| `/profs gear` | craftable gear upgrades for your level |
| `/profs save <name>` / `/profs load <name>` | save or load a route |
| `/profs reset` | clear your excluded and locked recipes for this profession |
| `/profs ah` | open the price panel (at the Auction House) |
| `/profs prices` | price sources, their order and freshness |
| `/profs prices order tsm,ahscan,auctionator,dataset` | change the source order |
| `/profs alerts on` / `off` / `pct 10` / `test` | level-up gear alert settings |
| `/profs help` | list all commands |

### Trainers and your faction

Profs! only suggests trainers and recipe vendors your faction can use: Alliance
characters never get Horde-only trainers and vice versa. Neutral NPCs (for example in
Booty Bay or Gadgetzan) are offered to both. NPCs in the other faction's capital
cities are never suggested. Where the data does not say whether your faction can use
an NPC, it is still listed but marked "faction access unknown", so check in game. A
recipe that only the other faction's NPCs teach or sell is left out of your routes and
gear suggestions.

### Where prices come from

| Source | Meaning |
|---|---|
| `ahscan` | your own Auction House scans (this realm and faction), stale after 24 h |
| `tsm` | TradeSkillMaster AuctionDB values, refreshed by the TSM app |
| `auctionator` | Auctionator's scans, stale after 3 days |
| `dataset` | historical average shipped with the addon, used only as a last resort |

The first source with a fresh price wins. Vendor-sold items always use the vendor
price when it is cheaper. Every price in the shopping list shows its source and age.

## Status

This is an early release. It targets WoW Forever 1.60.x (interface 16001) and has
not yet been tested extensively in the live game. Known gaps:

- If the addon shows as "out of date", check your client's interface number with
  `/dump select(4, GetBuildInfo())` and report it.
- First Aid routes stop at 270: the last bandage recipes have no known source in
  the bundled data.
- Some recipes new to WoW Forever have no known source yet.
- Profession rank caps and training costs use Classic Era values where the data
  has none.

Bug reports and suggestions are welcome in
[Issues](https://github.com/ErikTMA/Profs/issues).
