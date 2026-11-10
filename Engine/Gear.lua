-- Character leveling gear helper: craftable items the character can make (or have
-- made by an alt's profession) that beat what is equipped.
--
-- Scoring: Pawn when it is installed (Adapters/Pawn.lua supplies `scorer`), else
-- Pawn's own weights built in (Data/PawnWeights.lua, generated from Pawn's Forever
-- scales by `make pawn-weights`) and Pawn's own formula: the upgrade is
-- (new - current) / current in percent, an empty slot is a big upgrade, under 0.5%
-- is none. The scale is the specialization's; without one, the class scale that best
-- matches the stats already equipped. There is deliberately no manual weight editor.
local _, ns = ...
local G = ns:NewModule("Gear")

G.EMPTY_SLOT = 10000 -- percent: Pawn's "big upgrade" (PawnBigUpgradeThreshold, 100 = 10,000%)
G.MIN_PCT = 0.5      -- Pawn counts only upgrades at least 0.5% better

local DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
local RANGED = { [15] = true, [25] = true, [26] = true } -- inventory types of ranged weapons

-- The client's specialization name -> Pawn's scale name, where they differ.
local SPEC_ALIAS = { guardian = "feral (tank)", feral = "feral (damage)" }

-- armor subclass (1 cloth, 2 leather, 3 mail, 4 plate) -> minimum character level
local ARMOR_PROF = {
  WARRIOR = { [1] = 0, [2] = 0, [3] = 0, [4] = 40 }, PALADIN = { [1] = 0, [2] = 0, [3] = 0, [4] = 40 },
  HUNTER = { [1] = 0, [2] = 0, [3] = 40 }, SHAMAN = { [1] = 0, [2] = 0, [3] = 40 },
  ROGUE = { [1] = 0, [2] = 0 }, DRUID = { [1] = 0, [2] = 0 },
  MAGE = { [1] = 0 }, WARLOCK = { [1] = 0 }, PRIEST = { [1] = 0 },
}

-- An item's value on a scale (Data/PawnWeights.lua entry, or a plain { [stat] = w }).
-- invType decides melee or ranged weapon DPS.
local function score(stats, scale, invType)
  local w = scale.weights or scale
  local s = 0
  for k, v in pairs(stats or {}) do
    if k == DPS and scale.weights then
      s = s + (RANGED[invType] and scale.rangedDps or scale.meleeDps or 0) * v
    else
      s = s + (w[k] or 0) * v
    end
  end
  return s
end
G.Score = score

-- Upgrade percent of a score over the current one, Pawn's way.
function G.Percent(new, cur)
  if not cur or cur <= 0 then return new > 0 and G.EMPTY_SLOT or 0 end
  return (new - cur) / cur * 100
end

-- "+12%", or "empty slot" for an item that fills one.
function G.GainText(gain)
  if gain >= G.EMPTY_SLOT then return "empty slot" end
  return ("+%.0f%%"):format(gain)
end

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
      if (a.score or 0) ~= (b.score or 0) then return (a.score or 0) > (b.score or 0) end
      return a.itemId < b.itemId
    end)
  end
  table.sort(groups, function(a, b)
    local x, y = a.items[1], b.items[1]
    if x.gain ~= y.gain then return x.gain > y.gain end
    if (x.score or 0) ~= (y.score or 0) then return (x.score or 0) > (y.score or 0) end
    return a.name < b.name
  end)
  return groups
end

-- Pawn's scales for a class ({} for an unknown class).
function G.Scales(class)
  return ns.PawnWeights and ns.PawnWeights[class] or {}
end

-- The scale for the class: the specialization's when known (by the client's name for
-- it, else its tree index), else the class scale that best explains the equipped
-- totals. Returns the scale and its name ("Arms").
function G.AutoWeights(class, equippedTotals, spec, specName)
  local list = G.Scales(class)
  if #list == 0 then list = G.Scales("WARRIOR") end
  if specName then
    local want = specName:lower()
    want = SPEC_ALIAS[want] or want
    for _, sc in ipairs(list) do if sc.name:lower() == want then return sc, sc.name end end
    for _, sc in ipairs(list) do
      if sc.name:lower():match("^(.-) %(") == want then return sc, sc.name end
    end
  end
  if spec then
    for _, sc in ipairs(list) do if sc.spec == spec then return sc, sc.name end end
  end
  if #list == 1 or not equippedTotals or not next(equippedTotals) then return list[1], list[1].name end
  local best, bestScore = list[1], -1
  for _, sc in ipairs(list) do
    local v = score(equippedTotals, sc)
    if v > bestScore then best, bestScore = sc, v end
  end
  return best, best.name
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
    { known = known, side = faction.side, npcs = faction.npcs, allowSources = sources or G.SOURCES,
      dropNeedsMobs = true }))
end

-- opts: profs={[profId]=skill}, level, class, weights|nil, scorer(itemId)|nil, known,
--       stats(itemId)|nil (runtime stat lookup), equipped={[slot]=score},
--       lookahead (levels above `level` to include, default 3),
--       drops (true: also patterns that drop; candidates carry how = acquisition),
--       pending = {} (filled with items the scorer could not rate yet)
function G.Candidates(ds, opts)
  local w = opts.weights or G.AutoWeights(opts.class, opts.equippedTotals, opts.spec, opts.specName)
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
          -- gain: upgrade percent over what is worn, Pawn's or by Pawn's weights. An
          -- item Pawn cannot rate yet (its data is not loaded) is left out and noted
          -- in opts.pending, and the caller re-runs on arrival.
          local sc, gain
          if opts.scorer then
            gain = opts.scorer(out_id)
            sc = gain
            if gain == nil and opts.pending then opts.pending[out_id] = true end
          else
            -- the client's stats first: the equipped item is scored from them too
            local st = (opts.stats and opts.stats(out_id)) or it.stats
            sc = st and score(st, w, it.slot) or nil
            if sc then gain = G.Percent(sc, opts.equipped and opts.equipped[it.slot] or 0) end
          end
          if gain then
            out[#out + 1] = { itemId = out_id, recipe = r.id, prof = profId, slot = it.slot,
              reqLevel = rl, score = sc, gain = gain, usableNow = rl <= (opts.level or 60), how = how,
              pct = true }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.gain ~= b.gain then return a.gain > b.gain end
    -- equal gains (empty slots): the better item first
    if (a.score or 0) ~= (b.score or 0) then return (a.score or 0) > (b.score or 0) end
    return a.itemId < b.itemId
  end)
  local upgrades = {}
  for _, c in ipairs(out) do if c.gain >= G.MIN_PCT then upgrades[#upgrades + 1] = c end end
  return upgrades, out
end
