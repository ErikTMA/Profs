-- Character leveling gear helper: craftable items the character can make (or have
-- made by an alt's profession) that beat what is equipped.
--
-- Scoring: Pawn when it is installed (Adapters/Pawn.lua supplies `scorer`), else the
-- built-in AUTOMATIC weights below — picked from the class, and for hybrid classes
-- from whichever role profile best matches the primary stats already equipped. There
-- is deliberately no manual weight editor.
local _, ns = ...
local G = ns:NewModule("Gear")

local STR, AGI, STA, INT, SPI = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT",
  "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT"
local ARMOR, DPS = "RESISTANCE0_NAME", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"

local PROFILES = {
  melee_str = { [STR] = 1.0, [AGI] = 0.5, [STA] = 0.5, [ARMOR] = 0.01, [DPS] = 3.0 },
  melee_agi = { [AGI] = 1.0, [STR] = 0.4, [STA] = 0.5, [ARMOR] = 0.01, [DPS] = 3.0 },
  ranged    = { [AGI] = 1.0, [INT] = 0.3, [STA] = 0.5, [ARMOR] = 0.01, [DPS] = 2.0 },
  caster    = { [INT] = 1.0, [SPI] = 0.6, [STA] = 0.5, [ARMOR] = 0.005 },
  healer    = { [INT] = 1.0, [SPI] = 0.8, [STA] = 0.4, [ARMOR] = 0.005 },
}
G.PROFILES = PROFILES

local CLASS_PROFILES = {
  WARRIOR = { "melee_str" },
  ROGUE   = { "melee_agi" },
  HUNTER  = { "ranged" },
  MAGE    = { "caster" },
  WARLOCK = { "caster" },
  PRIEST  = { "caster", "healer" },
  PALADIN = { "melee_str", "healer" },
  SHAMAN  = { "melee_str", "caster", "healer" },
  DRUID   = { "melee_agi", "caster", "healer" },
}

-- armor subclass (1 cloth, 2 leather, 3 mail, 4 plate) -> minimum character level
local ARMOR_PROF = {
  WARRIOR = { [1] = 0, [2] = 0, [3] = 0, [4] = 40 }, PALADIN = { [1] = 0, [2] = 0, [3] = 0, [4] = 40 },
  HUNTER = { [1] = 0, [2] = 0, [3] = 40 }, SHAMAN = { [1] = 0, [2] = 0, [3] = 40 },
  ROGUE = { [1] = 0, [2] = 0 }, DRUID = { [1] = 0, [2] = 0 },
  MAGE = { [1] = 0 }, WARLOCK = { [1] = 0 }, PRIEST = { [1] = 0 },
}

local function score(stats, w)
  local s = 0
  for k, v in pairs(stats or {}) do s = s + (w[k] or 0) * v end
  return s
end
G.Score = score

-- Equip slot (inventory type) -> slot group shown in the upgrade lists.
G.SLOT_GROUP = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulder", [16] = "Back", [5] = "Chest", [20] = "Chest",
  [4] = "Shirt", [19] = "Tabard", [9] = "Wrist", [10] = "Hands", [6] = "Waist", [7] = "Legs",
  [8] = "Feet", [11] = "Finger", [12] = "Trinket", [13] = "One-hand", [21] = "Main hand",
  [17] = "Two-hand", [14] = "Off hand", [22] = "Off hand", [23] = "Off hand", [15] = "Ranged",
  [25] = "Ranged", [26] = "Ranged", [18] = "Bag",
}

-- Pure: upgrades grouped by slot: { { name, items = {...} } }, each group's items by
-- gain (biggest first), groups ordered by their biggest upgrade.
function G.BySlot(upgrades)
  local byName, groups = {}, {}
  for _, c in ipairs(upgrades) do
    local name = G.SLOT_GROUP[c.slot] or "Other"
    local g = byName[name]
    if not g then g = { name = name, items = {} }; byName[name] = g; groups[#groups + 1] = g end
    g.items[#g.items + 1] = c
  end
  for _, g in ipairs(groups) do
    table.sort(g.items, function(a, b)
      if a.gain ~= b.gain then return a.gain > b.gain end
      return a.itemId < b.itemId
    end)
  end
  table.sort(groups, function(a, b)
    if a.items[1].gain ~= b.items[1].gain then return a.items[1].gain > b.items[1].gain end
    return a.name < b.name
  end)
  return groups
end

-- Profile per specialization (talent tree) index, in the client's tree order, for the
-- classes whose trees want different stats. Trees not listed use the class list.
G.SPEC_PROFILES = {
  PALADIN = { "healer", "melee_str", "melee_str" },   -- Holy, Protection, Retribution
  SHAMAN  = { "caster", "melee_str", "healer" },      -- Elemental, Enhancement, Restoration
  DRUID   = { "caster", "melee_agi", "healer" },      -- Balance, Feral, Restoration
  PRIEST  = { "healer", "healer", "caster" },         -- Discipline, Holy, Shadow
}

-- The profile for the class: the specialization's when known (spec = tree index),
-- else the class profile that best explains the equipped totals.
function G.AutoWeights(class, equippedTotals, spec)
  local bySpec = spec and G.SPEC_PROFILES[class] and G.SPEC_PROFILES[class][spec]
  if bySpec then return PROFILES[bySpec], bySpec end
  local list = CLASS_PROFILES[class] or { "melee_str" }
  if #list == 1 or not equippedTotals then return PROFILES[list[1]], list[1] end
  local bestName, best = list[1], -1
  for _, name in ipairs(list) do
    local s = score(equippedTotals, PROFILES[name])
    if s > best then best, bestName = s, name end
  end
  return PROFILES[bestName], bestName
end

-- weapon subclass -> classes that can train it (Classic Era proficiencies; unverified
-- for Forever). 0 1H axe, 1 2H axe, 2 bow, 3 gun, 4 1H mace, 5 2H mace, 6 polearm,
-- 7 1H sword, 8 2H sword, 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand
local WEAPON_PROF = {
  WARRIOR = { [0]=1, [1]=1, [2]=1, [3]=1, [4]=1, [5]=1, [6]=1, [7]=1, [8]=1, [10]=1, [13]=1, [15]=1, [16]=1, [18]=1 },
  PALADIN = { [0]=1, [1]=1, [4]=1, [5]=1, [6]=1, [7]=1, [8]=1 },
  HUNTER  = { [0]=1, [1]=1, [2]=1, [3]=1, [6]=1, [7]=1, [8]=1, [10]=1, [13]=1, [15]=1, [16]=1, [18]=1 },
  ROGUE   = { [2]=1, [3]=1, [4]=1, [7]=1, [13]=1, [15]=1, [16]=1, [18]=1 },
  PRIEST  = { [4]=1, [10]=1, [15]=1, [19]=1 },
  SHAMAN  = { [0]=1, [1]=1, [4]=1, [5]=1, [10]=1, [13]=1, [15]=1 },
  MAGE    = { [7]=1, [10]=1, [15]=1, [19]=1 },
  WARLOCK = { [7]=1, [10]=1, [15]=1, [19]=1 },
  DRUID   = { [4]=1, [5]=1, [10]=1, [13]=1, [15]=1 },
}

function G.CanWear(class, level, item)
  if item.c == 2 then
    local allowed = WEAPON_PROF[class]
    if not allowed or item.sc == nil then return true end
    return allowed[item.sc] ~= nil
  end
  if item.c ~= 4 or not item.sc or item.sc == 0 then return true end -- misc/jewelry/unknown
  local allowed = ARMOR_PROF[class]
  if not allowed then return true end
  local minLevel = allowed[item.sc]
  return minLevel ~= nil and level >= minLevel
end

-- How the character can get recipe r: known, or a source the default route policy
-- allows (trainer, vendor, starter), or a vendor selling it for a currency or items
-- (token, e.g. Merchant's Favor: earned, not bought, so not in default leveling routes,
-- but a real way to get one piece of gear). nil = unobtainable for gear suggestions
-- (drops, quests, reputation, cooldown or specialization recipes).
G.SOURCES = { trainer = true, vendor = true, starter = true, token = true }
-- The upgrades column also lists patterns that drop (marked, with mob, zone and chance):
-- farmable or on the Auction House. Level-up alerts keep G.SOURCES (act-now only).
G.SOURCES_WITH_DROPS = { trainer = true, vendor = true, starter = true, token = true, drop = true }
-- faction = { side = "A"|"H"|nil, npcs = ds.npcs }: sources only enemy NPCs offer
-- are not obtainable (Engine/Faction.lua).
function G.Obtainable(r, known, faction, sources)
  if known and known[r.id] then return { t = "known", cost = 0, crafts = 0, access = "ok" } end
  if ns.Cooldowns and ns.Cooldowns.Has(r.id) then return nil end
  if r.spec then return nil end
  faction = faction or {}
  return ns.Optimizer.Acquisition(r, ns.Util.merge(ns.Optimizer.DEFAULTS,
    { known = known, side = faction.side, npcs = faction.npcs, allowSources = sources or G.SOURCES }))
end

-- opts: profs={[profId]=skill}, level, class, weights|nil, scorer(itemId)|nil, known,
--       stats(itemId)|nil (runtime stat lookup), equipped={[slot]=score},
--       lookahead (levels above `level` to include, default 3),
--       drops (true: also patterns that drop; candidates carry how = acquisition),
--       pending = {} (filled with items the scorer could not rate yet)
function G.Candidates(ds, opts)
  local w = opts.weights or G.AutoWeights(opts.class, opts.equippedTotals, opts.spec)
  local out = {}
  for profId, skill in pairs(opts.profs or {}) do
    for _, r in ipairs(ds.recipesByProf[profId] or {}) do
      local out_id = r.creates and r.creates[1]
      local it = out_id and ds.items[out_id]
      local how = it and it.slot and it.slot > 0 and r.learn <= skill
        and G.Obtainable(r, opts.known, { side = opts.side, npcs = ds.npcs }, opts.drops and G.SOURCES_WITH_DROPS or nil)
      if how then
        local rl = it.rl or 0
        if rl <= (opts.level or 60) + (opts.lookahead or 3) and G.CanWear(opts.class, opts.level or 60, it) then
          local sc, pct
          if opts.scorer then
            -- Pawn rates in percent; built-in weights in stat points. Never mix the two
            -- in one list: an item Pawn cannot rate yet (its data is not loaded) is
            -- left out and noted in opts.pending, and the caller re-runs on arrival.
            sc = opts.scorer(out_id)
            pct = sc ~= nil
            if sc == nil and opts.pending then opts.pending[out_id] = true end
          else
            local st = it.stats or (opts.stats and opts.stats(out_id))
            sc = st and score(st, w) or nil
          end
          if sc then
            local cur = opts.equipped and opts.equipped[it.slot] or 0
            out[#out + 1] = { itemId = out_id, recipe = r.id, prof = profId, slot = it.slot,
              reqLevel = rl, score = sc, gain = sc - cur, usableNow = rl <= (opts.level or 60), how = how,
              pct = pct or nil }   -- pct: gain is Pawn's upgrade percent
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.gain ~= b.gain then return a.gain > b.gain end
    return a.itemId < b.itemId
  end)
  local upgrades = {}
  for _, c in ipairs(out) do if c.gain > 0 then upgrades[#upgrades + 1] = c end end
  return upgrades, out
end
