-- Profession advisor: what each profession would do for THIS character, so a choice
-- such as Leatherworking or Blacksmithing can be made on what matters to you.
--
-- One card per crafting profession:
--   gear     craftable upgrades for you over the next A.WINDOW levels (the gear
--            scoring of the character-frame column: Pawn for your spec, else
--            built-in weights), grouped by slot, with the skill each needs
--   cost     cheapest route from your current skill to max, netted against what you
--            own (bags, bank, mail, alts), recipes and training included
--   gather   the share of its materials a gathering profession supplies (Skinning
--            for Leatherworking, ...), and cloth, which drops while you quest
--   crafts   expected crafts, recipes you must find (drops, quests, reputation)
-- A.Rank orders the cards ("you": gear for you, then cost; "cost"; "crafts") and
-- A.Verdict says in a sentence which fits you best and why, against the runner-up.
--
-- Everything is an estimate: expected craft counts, current prices, the gear the
-- data knows. Pure functions over (dataset, context); the UI drives them one
-- profession per frame.
local _, ns = ...
local A = ns:NewModule("Advisor")

A.WINDOW = 10        -- levels of gear ahead of the character to count
A.SLOT_CAP = 100     -- an upgrade counts at most as "100% better" for ranking

local MINING, HERBALISM, SKINNING = 186, 182, 393

-- Gathered materials by item id (Classic ids, stable across 1.x clients). Herbs are
-- recognised by item class (trade goods / herb); ore, stone, bars and hides are mixed
-- in with crafted materials in their subclasses, so they are listed.
local MINED = {
  2770, 2771, 2772, 2775, 2776, 3858, 7911, 10620, 11370,          -- ores
  2835, 2836, 2838, 7912, 12365,                                    -- stone
  2840, 3576, 2841, 2842, 3575, 3577, 3859, 3860, 6037, 12359, 11371, -- bars (smelting is Mining)
  774, 818, 1210, 1705, 1206, 7909, 3864, 7910, 12361, 12364, 12800, 12799, 12363, -- gems from veins
}
local SKINNED = {
  2934, 783, 2318, 4232, 2319, 4235, 4234, 8169, 4304, 8171, 8170,  -- scraps, hides, leather
  7286, 7392, 8167, 8154, 15412, 15415, 15416, 15414, 15417, 15408, 15419, 17012, -- scales, special
}
A.GATHERED = {}
for _, id in ipairs(MINED) do A.GATHERED[id] = MINING end
for _, id in ipairs(SKINNED) do A.GATHERED[id] = SKINNING end

-- Which gathering profession supplies an item: Mining, Herbalism, Skinning, "cloth"
-- (drops from humanoids while questing), or nil (bought: thread, dyes, vials, ...).
function A.Source(ds, itemId)
  if A.GATHERED[itemId] then return A.GATHERED[itemId] end
  local it = ds.items[itemId]
  if it and it.c == 7 and it.sc == 9 then return HERBALISM end
  if it and it.c == 7 and it.sc == 5 then return "cloth" end
  return nil
end

-- What each profession is for, in one line (shown on its card).
A.NOTES = {
  [171] = "Potions, elixirs and flasks for yourself. Pairs with Herbalism.",
  [164] = "Mail and plate armor, weapons, sharpening stones. Pairs with Mining.",
  [333] = "Enchants for your own gear. Materials come from disenchanting greens (pairs with Tailoring).",
  [202] = "Gadgets, bombs, guns, scopes and goggles. Pairs with Mining.",
  [165] = "Leather and mail armor, armor kits, quivers. Pairs with Skinning.",
  [197] = "Cloth armor and bags. Cloth drops while you quest: no gathering needed.",
  [185] = "Food: health regeneration and Well Fed buffs.",
  [129] = "Bandages: healing between fights for any class.",
}

-- Pure: how much an upgrade counts for ranking, 0..A.SLOT_CAP. Pawn gives a percent;
-- built-in scores are made relative to what is worn (an empty slot counts fully).
function A.Relative(c)
  local v
  if c.pct then v = c.gain
  else
    local cur = (c.score or 0) - (c.gain or 0)
    v = cur > 0 and (c.gain / cur * 100) or A.SLOT_CAP
  end
  return math.max(0, math.min(A.SLOT_CAP, v))
end

-- Gear summary from upgrade candidates: { value, slots = { {name, best, items} } }.
function A.GearSummary(ds, upgrades)
  local out = { value = 0, slots = {}, count = #upgrades }
  for _, g in ipairs(ns.Gear.BySlot(upgrades)) do
    local best = g.items[1]
    local r = ds.recipes[best.recipe]
    out.slots[#out.slots + 1] = { name = g.name, best = best, items = g.items, skill = r and r.learn or 0 }
    out.value = out.value + A.Relative(best)
  end
  return out
end

-- Cost side of a card: route from the current skill to max, netted against stock.
-- ctx: pricer, have(itemId)->{bags,...}, known, side, charLevel, allowSources
function A.Cost(ds, profId, skill, ctx)
  local max = ns.Professions.MaxSkill(profId, ds)
  if skill >= max then return { done = true, max = max, cost = 0, crafts = 0, find = 0, gather = {} } end
  local route = ns.Optimizer.Plan(ds, profId, math.max(1, skill), max, {
    pricer = ctx.pricer, known = ctx.known, side = ctx.side, charLevel = ctx.charLevel,
    allowSources = ctx.allowSources })
  local list = ns.Shopping.Build(ds, route, { pricer = ctx.pricer, have = ctx.have })
  local gather, materials = {}, 0
  for _, l in ipairs(list.items) do
    local v = (l.unit or 0) * l.need
    materials = materials + v
    local src = A.Source(ds, l.itemId)
    if src then
      local g = gather[src] or { value = 0, buy = 0, items = {} }
      g.value = g.value + v
      g.buy = g.buy + (l.unit or 0) * l.buy
      g.items[#g.items + 1] = l.itemId
      gather[src] = g
    end
  end
  for _, g in pairs(gather) do g.share = materials > 0 and g.value / materials or 0 end
  local find = 0
  for _, a in ipairs(list.acquire or {}) do
    local t = a.how and a.how.t
    if t and t ~= "trainer" and t ~= "starter" and t ~= "known" then find = find + 1 end
  end
  return { max = max, cost = list.total, crafts = route.totalCrafts, find = find, gather = gather,
    materials = materials, complete = route.unreachable == nil, reach = route.unreachable or max }
end

-- The gathering profession (or cloth) supplying the largest share, or nil.
function A.BestPartner(cost)
  local best, bestK
  for k, g in pairs(cost.gather or {}) do
    if not best or g.value > best.value then best, bestK = g, k end
  end
  if not best or best.share < 0.1 then return nil end
  return bestK, best
end

-- One card. ctx adds: skills = { [prof] = rank }, gear(profId) -> upgrades
function A.Card(ds, profId, ctx)
  local skill = (ctx.skills or {})[profId] or 0
  local card = { prof = profId, name = ns.Professions.Name(profId), skill = skill, have = skill > 0,
    kind = ns.Professions.list[profId] and ns.Professions.list[profId].kind, note = A.NOTES[profId] }
  card.cost = A.Cost(ds, profId, skill, ctx)
  card.gear = A.GearSummary(ds, ctx.gear and ctx.gear(profId) or {})
  card.partner, card.partnerInfo = A.BestPartner(card.cost)
  return card
end

A.SORTS = {
  you = function(a, b)
    if a.gear.value ~= b.gear.value then return a.gear.value > b.gear.value end
    if a.cost.cost ~= b.cost.cost then return a.cost.cost < b.cost.cost end
    return a.prof < b.prof
  end,
  cost = function(a, b)
    if a.cost.cost ~= b.cost.cost then return a.cost.cost < b.cost.cost end
    return a.prof < b.prof
  end,
  crafts = function(a, b)
    if a.cost.crafts ~= b.cost.crafts then return a.cost.crafts < b.cost.crafts end
    return a.prof < b.prof
  end,
}

function A.Rank(cards, by)
  local out = {}
  for _, c in ipairs(cards) do out[#out + 1] = c end
  table.sort(out, A.SORTS[by] or A.SORTS.you)
  return out
end

local function slotNames(card, n)
  local t = {}
  for i, s in ipairs(card.gear.slots) do
    if i > (n or 3) then t[#t + 1] = "..."; break end
    t[#t + 1] = s.name
  end
  return table.concat(t, ", ")
end

-- One or two sentences: which profession fits you best and why, against the runner-up.
-- cards: primary professions you do not have yet (or all, for a re-think).
function A.Verdict(cards, window)
  window = window or A.WINDOW
  local ranked = A.Rank(cards, "you")
  local a, b = ranked[1], ranked[2]
  if not a then return "No profession data." end
  local U = ns.Util
  if a.gear.value <= 0 then
    local cheap = A.Rank(cards, "cost")[1]
    return ("No profession makes gear upgrades for you in the next %d levels. Cheapest to level: %s (%s)."):format(
      window, cheap.name, U.money(cheap.cost.cost))
  end
  local s = ("%s fits you best: upgrades for %s in the next %d levels."):format(a.name, slotNames(a), window)
  if b then
    if b.gear.value > 0 then
      s = s .. (" %s: %s."):format(b.name, slotNames(b))
    else
      s = s .. (" %s makes nothing you would wear yet."):format(b.name)
    end
    local diff = b.cost.cost - a.cost.cost
    if diff > 0 then
      s = s .. (" %s is also %s cheaper to level."):format(a.name, U.money(diff))
    elseif diff < 0 then
      s = s .. (" %s costs %s more to level."):format(a.name, U.money(-diff))
    end
  end
  return s
end
