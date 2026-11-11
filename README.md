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
- **Uses what you have first**: reagents you already own count at their vendor
  price (what you give up), not the auction price, so a route that uses your stock
  can win over one that is cheaper to buy. The route says which reagents it uses and
  how much that saves. Looting or receiving more reagents re-plans the route.
- **What to do with the results**: sell, vendor, disenchant or keep.
- **Your own choices**: exclude recipes, lock a skill range to a recipe, save and
  load named routes.
- **Which profession is right for you**: the Professions window compares every
  crafting profession for your character. Each one shows the gear it makes for you
  over the next 10 levels, by slot (scored for your spec, with Pawn if you use it);
  the cost to max from your current skill, after what you already own; how much of
  its materials a gathering profession supplies (Skinning for Leatherworking, Mining
  for Blacksmithing, cloth drops for Tailoring) and whether you or an alt has it;
  craft count and recipes you would have to find. A line at the top says which fits
  you best and why, e.g. "Leatherworking fits you best: upgrades for Legs, Chest,
  Head... Blacksmithing: Two-hand, One-hand." Sort by Best for you, Cheapest or
  Fewest crafts. Your own and your alts' professions are listed first, with the next
  rank to train.
- **Make now**: a tab in the profession column listing everything you know that
  your bags can make right now, skill-ups first, marking gear upgrades and value.
- **Leveling gear helper**: craftable upgrades for your level, shown as percent
  better than what you wear: scored by Pawn if you use it, otherwise by Pawn's own
  weights built into Profs!.
- **Level-up alerts**: when you ding, a small notice lists craftable gear that just
  became an upgrade. Click a row to open the recipe.
- **Gathering guide** for Herbalism, Mining and Skinning: where to gather at every
  skill level, from every herb and ore spawn and every skinnable mob in the data
  grouped into areas, the zone and coordinates for each step with a waypoint on click,
  how many herbs, nodes or mobs to expect, and when to train the next rank. It stays
  on your continent and avoids the other faction's zones and mobs above your level. With **GatherMate2**, the nodes you recorded join the guide,
  and one button adds Profs!' node positions to GatherMate2's map pins.
- **Nearest vendor in item tooltips**: hover anything a vendor sells (thread, vials,
  flux, food, ammo...) to see the nearest friendly or neutral vendor, its
  coordinates and how many yards away it is. Turn it off in the options.
- **Waylaid Crates**: hover a crate to see which bundle you can fill it with from
  your bags, what the rest costs, the Merchant's Favor it pays and where to turn it
  in. `/profs crates` lists the crates you carry and points the arrow at Marcy Baker
  or Dokimi. Recipes bought with Merchant's Favor join your routes once you hold
  enough Favor, priced at what that Favor costs to earn.
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
**Pawn**, **GatherMate2**. None of them are required.

## Usage

Open any profession window: it gets a third column on the right, after the recipe
list and the recipe details, with the route, the shopping list and the next recipe
to craft. The column is part of the window: it moves and closes with it, follows the
profession tab you select (it is not shown on the professions overview), and leaves the profession tabs along the window's right
edge free to click. It uses the same art and border as the recipe details beside it,
so the window reads as one piece. `/profs show` hides or shows the column (remembered
per character).

The **Craft** button never crafts past the end of the current step (the skill where
the route switches recipe, or your target). Addons cannot stop a craft once it is
queued, so it queues at most one craft per skill point left: "Craft 9" at 50 of a
step ending at 59, even if about 58 crafts are expected. Click it again after each
batch. Shift-click queues all the expected crafts instead (may go past the step).
When the step needs something the route makes itself (Cured Light Hide, Bolt of
Linen Cloth, ...) and you have none, the button makes that first ("Make 4") from what
is in your bags, down the chain if needed (hide, then cured hide, then leather).
Esc stops a running craft.

In the route list, click a step to select its recipe in Blizzard's list; right-click
it for options (never use this recipe, lock the skill range to it, unlock, clear all).
Shift-, Ctrl- and Alt-click do the same without the menu. Rows with an item (shopping
list, outputs, gear upgrades) show the item's tooltip; Shift-click links the item in
chat, Ctrl-click previews it. **Route / Shopping / Outputs** are tabs above the list,
which scrolls with a scrollbar when it is longer than the column. Route steps show
the recipe's tooltip, then the expected crafts and where to learn it.

Trainers and vendors of the other faction are left out: an NPC that the data marks
friendly to one faction only (for example Chaw Stronghide in Mulgore) counts as that
faction's NPC.

### Minimap button and options

The Profs! button sits on the minimap's edge; drag it to move it (saved per
character). Click: route for the open profession. Shift-click: gear upgrades.
Right-click: the Professions window. Ctrl-click: options. Alt-click: the gathering
guide. The same actions are on
the Profs! entry in the minimap's addon menu. `/profs minimap` hides or shows the button.

**Options** (Esc > Options > AddOns > Profs!, or `/profs options`): the profession
column, the character-frame column, level-up alerts and their threshold, colour-blind
markers (+++ / ++ / + after orange / yellow / green steps; on by default when the
game's colour-blind mode is on), how prices are chosen, the minimap button, and a reset
for window positions. Profs! windows close with Esc, stay on screen, and remember where
you put them; `/profs resetui` puts them back.

### Gathering guide

`/profs gather` (or alt-click the minimap button) opens it; `/profs gather mining`,
`/profs gather herbalism` or `/profs gather skinning` picks the profession. Each row is
a step: skill range, zone and coordinates, and about how many herbs, nodes or mobs it
takes. Click a row for a waypoint: an arrow on screen points the way (the same arrow as
Lvls!, if you have that too) and the map gets a pin. Right-click the arrow to clear it.
Hover it for the nodes or mobs there in skill-up colours (mobs with their level), the
level of the area and whose zone it is. Mining's own window shows the same guide in the
Profs! column. With GatherMate2, **Add to GatherMate2** copies
Profs!' node positions into it (it asks first; GatherMate2's options can clear them).

### Craftable gear upgrades

Recipes bought with a currency (for example Merchant's Favor from the Azeroth
Commerce Authority) count for gear suggestions; they are not used in leveling routes.

Patterns that drop are listed too, marked **drop**. Hover one to see which mobs drop
it: level, elite or boss, zone and coordinates (dungeon mobs: the dungeon), and the
drop chance with how many kills it was measured on. World drops say how many mobs
drop them and show the best chances. Drop patterns are often on the Auction House.

Upgrades are grouped by slot (Feet, Chest, ...): each slot lists every craftable
upgrade for it, biggest first, and the slot with the biggest upgrade comes first.

Gear is scored for your active specialization: with Pawn, Pawn's scale for that
specialization (for example "Shaman: Enhancement"), shown as percent better than what
you wear; without Pawn, the same percent from Pawn's own weights for that
specialization, built into Profs!. The
column's top line says which. To score for another specialization or a specific Pawn
scale, use **Score gear for** in the options or `/profs gearspec 3`,
`/profs gearspec pawn <scale>`, `/profs gearspec auto` (per character).

Open your character window (C): when you can craft gear that beats what you wear,
Profs! adds a **Craftable upgrades** column to it, right of your stats, listing each
item with its icon, required level and how much better it is. Hover a row for the
recipe's own tooltip (as when someone links the recipe: reagents, the ones you lack in
red, and the item) followed by where to get the recipe; click it to open the recipe,
Shift-click to link the recipe in chat. When there
is nothing to upgrade, the character window stays as it is. Your professions and your
alts' count, scored with Pawn if you use it.

The **Gear upgrades** button in the Profs! profession column, shift-click on the
minimap button or the Profs! entry in the minimap's addon menu, and `/profs gear` all open the character
window on that page (and tell you in chat when there are no upgrades).

| Command | What it does |
|---|---|
| `/profs show` | hide or show the Profs! column in the profession window |
| `/profs options` | open the Profs! options |
| `/profs minimap` | hide or show the minimap button |
| `/profs resetui` | put every Profs! window back at its default place |
| `/profs recommend` | Professions window: which profession fits your character |
| `/profs gear` | craftable gear upgrades for your level |
| `/profs gearspec auto` / `<n>` / `pawn <scale>` | which specialization scores gear |
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
