-- Profession recommendation: which pair of primary crafting professions (and which
-- secondaries) is cheapest to level, counting synergy between the two.
--
-- Each profession gets a cheapest route 1 -> its max skill. A pair's cost is the
-- sum, minus synergy: the materials one route's OUTPUTS turn into that the other
-- route BUYS. V1 models the synergy the data can support:
--   disenchant  crafted greens of A disenchant into dust/essence B's shopping list
--               needs (Tailoring -> Enchanting); the value counted is the purchase
--               it avoids, capped at what B needs, minus the vendor value A gives up
--   direct      an output of A that is a reagent on B's list (e.g. bolts, bandages)
-- Everything is an estimate on expected craft counts; the UI says so.
local _, ns = ...
local RE = ns:NewModule("Recommend")

local function routeFor(ds, profId, opts)
  local max = ns.Professions.MaxSkill(profId, ds)
  local r = ns.Optimizer.Plan(ds, profId, 1, max, opts)
  local list = ns.Shopping.Build(ds, r, { pricer = opts.pricer })
  return { prof = profId, route = r, list = list, cost = list.total,
    reach = r.unreachable or max, complete = r.unreachable == nil }
end

-- Materials a route's crafted outputs yield: { [itemId] = expected count }, plus
-- the vendor value given up when those outputs are disenchanted instead of sold.
local function outputs(ds, plan, deSkill)
  local direct, de, lostVendor = {}, {}, 0
  for recipeId, n in pairs(plan.list.crafts) do
    local r = ds.recipes[recipeId]
    if r.creates then
      local out = r.creates[1]
      local qty = n * ns.Optimizer.AvgQty(r)
      direct[out] = (direct[out] or 0) + qty
      local y, req = ns.Recovery.DisenchantYield(ds, out)
      if y and (req or 0) <= deSkill then
        for _, row in ipairs(y) do
          local mn, mx = row[3] or 1, row[4] or row[3] or 1
          de[row[1]] = (de[row[1]] or 0) + qty * row[2] * (mn + mx) / 2
        end
        local it = ds.items[out]
        lostVendor = lostVendor + qty * ((it and it.vsell) or 0)
      end
    end
  end
  return direct, de, lostVendor
end

local function needs(plan)
  local n = {}
  for _, l in ipairs(plan.list.items) do n[l.itemId] = l end
  return n
end

-- Value of A's outputs to B. Returns copper, explanation lines.
function RE.Synergy(ds, a, b, pricer)
  local why, value = {}, 0
  local bNeeds = needs(b)
  local bIsEnchanting = ns.Professions.list[b.prof] and ns.Professions.list[b.prof].enchanting
  local direct, de, lost = outputs(ds, a, bIsEnchanting and b.reach or -1)

  for itemId, qty in pairs(direct) do
    local l = bNeeds[itemId]
    if l and l.unit then
      local used = math.min(qty, l.need)
      value = value + used * l.unit
      why[#why + 1] = { kind = "direct", item = itemId, qty = used, value = used * l.unit }
    end
  end
  if bIsEnchanting then
    -- Only the share of the disenchanted output whose materials B actually uses is
    -- disenchanted; the rest is still vendored. So the vendor value given up is
    -- charged in proportion: lost * (used material value / all material value).
    pricer = pricer or ns.Pricing.New(ds)
    local deValue, totalValue = 0, 0
    for itemId, qty in pairs(de) do
      local unit = (bNeeds[itemId] and bNeeds[itemId].unit) or pricer:Buy(itemId)
      if unit then totalValue = totalValue + qty * unit end
      local l = bNeeds[itemId]
      if l and l.unit then
        local used = math.min(qty, l.need)
        deValue = deValue + used * l.unit
        why[#why + 1] = { kind = "disenchant", item = itemId, qty = used, value = used * l.unit }
      end
    end
    if deValue > 0 then
      local lostShare = totalValue > 0 and lost * (deValue / totalValue) or lost
      value = value + deValue - lostShare
      why[#why + 1] = { kind = "lostVendor", value = -lostShare }
    end
  end
  table.sort(why, function(x, y) return math.abs(x.value) > math.abs(y.value) end)
  return math.max(0, value), why
end

-- opts: pricer, allowSources, known, mode...  Returns
-- { pairs = { {a, b, cost, base, synergy, why}, ... sorted }, secondary = {...}, solo = {...} }
function RE.Rank(ds, opts)
  opts = opts or {}
  local solo, primaries, secondary = {}, {}, {}
  for profId, meta in pairs(ns.Professions.list) do
    if meta.crafting and ds.recipesByProf[profId] then
      local plan = routeFor(ds, profId, opts)
      solo[profId] = plan
      if meta.kind == "primary" then primaries[#primaries + 1] = profId
      else secondary[#secondary + 1] = plan end
    end
  end
  table.sort(primaries)
  local out = {}
  for i = 1, #primaries do
    for j = i + 1, #primaries do
      local a, b = solo[primaries[i]], solo[primaries[j]]
      local s1, w1 = RE.Synergy(ds, a, b, opts.pricer)
      local s2, w2 = RE.Synergy(ds, b, a, opts.pricer)
      local why = {}
      for _, w in ipairs(w1) do w.from, w.to = a.prof, b.prof; why[#why + 1] = w end
      for _, w in ipairs(w2) do w.from, w.to = b.prof, a.prof; why[#why + 1] = w end
      local base = a.cost + b.cost
      out[#out + 1] = { a = a.prof, b = b.prof, base = base, synergy = s1 + s2,
        cost = base - s1 - s2, complete = a.complete and b.complete, why = why }
    end
  end
  table.sort(out, function(x, y)
    if x.complete ~= y.complete then return x.complete end
    if x.cost ~= y.cost then return x.cost < y.cost end
    return x.a * 1000 + x.b < y.a * 1000 + y.b
  end)
  table.sort(secondary, function(x, y) return x.cost < y.cost end)
  return { pairs = out, secondary = secondary, solo = solo }
end
