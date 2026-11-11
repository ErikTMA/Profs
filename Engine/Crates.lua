-- Waylaid Crates (WoW Forever): a Waylaid Crate drops, "Read the label" makes it one
-- crate of Data/Crates.lua, one bundle from its list fills it into a Sealed crate, and
-- the faction's trade representative pays Merchant's Favor for that (currency 3402).
-- Favor buys recipes: Optimizer token sources are priced with C.FavorPrice.
--
-- Pure: data from ns.CrateData (or a table passed in), item counts and prices through
-- the caller's have(itemId) -> n and pricer (Engine/Pricing).
local _, ns = ...
local C = ns:NewModule("Crates")

C.CURRENCY = 3402   -- Merchant's Favor

local function data(d) return d or ns.CrateData or { crates = {}, sealed = {}, turnin = {} } end

function C.Crate(itemId, d) return data(d).crates[itemId] end
function C.Sealed(itemId, d) return data(d).sealed[itemId] end
function C.IsUnread(itemId, d) return itemId ~= nil and itemId == data(d).unread end

-- Merchant's Favor a crate (or a sealed crate) pays when turned in; nil = not known.
function C.Favor(itemId, d)
  local c = C.Crate(itemId, d) or C.Sealed(itemId, d)
  return c and c.favor or nil
end

-- Turn-in NPCs for side "A"/"H" (both when the side is unknown), the data's order.
function C.TurnIn(side, d)
  local out = {}
  for _, t in ipairs(data(d).turnin or {}) do
    if not side or t.side == side or t.side == "B" then out[#out + 1] = t end
  end
  return out
end

-- Every bundle of a crate against what you have: { item, count, have, missing, cost,
-- ready } with cost = copper to buy the missing part (nil = some of it unpriced).
-- Ready bundles first, then the cheapest to complete, unpriced last.
function C.Fill(crate, have, pricer)
  local rows = {}
  for i, b in ipairs(crate and crate.bundles or {}) do
    local n = have and have(b[1]) or 0
    local missing = math.max(0, b[2] - n)
    local cost = 0
    if missing > 0 then
      local unit = pricer and pricer:Buy(b[1])
      cost = unit and unit * missing or nil
    end
    rows[#rows + 1] = { item = b[1], count = b[2], have = n, missing = missing, cost = cost,
      ready = missing == 0, order = i }
  end
  table.sort(rows, function(a, b)
    if a.ready ~= b.ready then return a.ready end
    if (a.cost == nil) ~= (b.cost == nil) then return a.cost ~= nil end
    if a.cost and a.cost ~= b.cost then return a.cost < b.cost end
    return a.order < b.order
  end)
  return rows
end

-- Copper to fill a crate from nothing with its cheapest bundle: cost, bundle row.
function C.FillCost(crate, pricer)
  local best
  for _, row in ipairs(C.Fill(crate, nil, pricer)) do
    if row.cost and (not best or row.cost < best.cost) then best = row end
  end
  return best and best.cost, best
end

-- Gold value of one Merchant's Favor: the cheapest copper per Favor of filling a crate
-- you can open (opts.charLevel against its required level) by buying its cheapest
-- bundle. The crate itself drops; its market price is added when a source quotes it.
-- Returns copperPerFavor, crateId, bundleRow; nil when no crate is priced.
function C.FavorPrice(pricer, opts, d)
  opts = opts or {}
  local best, bestId, bestRow
  for id, crate in pairs(data(d).crates) do
    if crate.favor and crate.favor > 0 and (not opts.charLevel or (crate.rl or 0) <= opts.charLevel) then
      local cost, row = C.FillCost(crate, pricer)
      if cost then
        local own = pricer and pricer.Market and pricer:Market(id)
        local per = (cost + (own or 0)) / crate.favor
        if not best or per < best or (per == best and id < bestId) then
          best, bestId, bestRow = per, id, row
        end
      end
    end
  end
  return best and math.floor(best + 0.5), bestId, bestRow
end

-- Crates whose bundle list uses itemId: { {crate=id, count=n}, ... } by crate id.
function C.ForItem(itemId, d)
  d = data(d)
  if not d._byItem then
    local idx = {}
    for id, crate in pairs(d.crates) do
      for _, b in ipairs(crate.bundles or {}) do
        idx[b[1]] = idx[b[1]] or {}
        table.insert(idx[b[1]], { crate = id, count = b[2] })
      end
    end
    for _, l in pairs(idx) do table.sort(l, function(a, b) return a.crate < b.crate end) end
    d._byItem = idx
  end
  return d._byItem[itemId] or {}
end

-- Merchant's Favor a token source costs (its currencies entry for C.CURRENCY), or 0.
function C.SourceFavor(src)
  local n = 0
  for _, c in ipairs(src and src.currencies or {}) do
    if c[1] == C.CURRENCY then n = n + (c[2] or 0) end
  end
  return n
end
