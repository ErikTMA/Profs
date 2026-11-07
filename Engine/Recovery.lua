-- What a crafted output is worth back, and what to do with it.
--   guaranteed  vendor sell value (the ONLY recovery the Cheapest mode counts)
--   speculative AH resale (market * (1 - AH cut), weighted by sale rate when known)
--   disenchant  expected value of the DE yield (measured dataset yield, else the
--               fallback table; only when an enchanter is available)
local _, ns = ...
local RC = ns:NewModule("Recovery")

RC.AH_CUT = 0.05

-- DE yields for an item: dataset-measured first, else the estimate table.
function RC.DisenchantYield(ds, itemId)
  local it = ds.items[itemId]
  if not it then return nil end
  if it.de and #it.de > 0 then return it.de, it.deSkill, false end
  local y, req = ns.DisenchantTable.Estimate(it)
  if y then return y, req, true end
  return nil
end

function RC.DisenchantValue(ds, pricer, itemId)
  local y, req, estimated = RC.DisenchantYield(ds, itemId)
  if not y then return nil end
  local ev, unpriced = 0, false
  for _, row in ipairs(y) do
    local id, chance, mn, mx = row[1], row[2], row[3] or 1, row[4] or row[3] or 1
    local p = pricer:Buy(id)
    if p then ev = ev + chance * (mn + mx) / 2 * p else unpriced = true end
  end
  return ev, req, estimated, unpriced
end

-- Per-unit valuation of one output item.
--   ctx.enchanting  enchanting skill available (self or alt with synergy), or nil
--   ctx.keep        [itemId]=true outputs the user wants to keep (gear, later reagent)
function RC.Evaluate(ds, pricer, itemId, ctx)
  ctx = ctx or {}
  local v = {
    itemId = itemId,
    vendor = pricer:VendorSell(itemId),
  }
  local market = pricer:Market(itemId)
  if market then
    local rate = pricer:SaleRate(itemId)
    v.market = market
    v.saleRate = rate
    v.ah = market * (1 - RC.AH_CUT) * (rate or 1)
  end
  local de, req, estimated, unpriced = RC.DisenchantValue(ds, pricer, itemId)
  if de then
    v.deValue, v.deSkill, v.deEstimated, v.deUnpriced = de, req, estimated, unpriced
    v.deAvailable = ctx.enchanting ~= nil and (req or 0) <= ctx.enchanting
  end

  -- Recommendation: keep > best of {ah (only if it sells), disenchant, vendor}.
  if ctx.keep and ctx.keep[itemId] then
    v.action = "keep"
  else
    v.action, v.best = "vendor", v.vendor
    if v.deAvailable and v.deValue > v.best then v.action, v.best = "disenchant", v.deValue end
    local rateOk = v.saleRate == nil or v.saleRate >= (ctx.minSaleRate or 0.1)
    if v.ah and rateOk and v.ah > v.best then v.action, v.best = "sell", v.ah end
  end
  v.guaranteed = v.vendor
  return v
end
