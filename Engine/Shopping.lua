-- Consolidated shopping list for a route.
--
-- Walks the segments in order with a rounded-up craft count each (plus an optional
-- safety margin), expands reagents the planner decided to craft (seg.via) into their
-- own reagents, and lets later segments consume what earlier ones produced (a bolt
-- made at skill 40 feeds a recipe at skill 75). What is left is netted against what
-- the player already owns (bags, bank, alts, mail — whatever `have` reports).
local _, ns = ...
local SH = ns:NewModule("Shopping")

local function ceil(x) return math.ceil(x - 1e-9) end

-- have(itemId) -> { bags=n, bank=n, alts=n, mail=n } (any subset) or nil
function SH.Build(ds, route, opts)
  opts = opts or {}
  local pricer = opts.pricer or ns.Pricing.New(ds)
  local margin = opts.margin or 0
  local need, produced, crafts = {}, {}, {}

  local function addNeed(itemId, n)
    need[itemId] = (need[itemId] or 0) + n
  end

  -- Consume n of itemId: from produced stock first, else craft (via) or buy.
  local function consume(itemId, n, via, depth)
    local stock = produced[itemId] or 0
    local use = math.min(stock, n)
    if use > 0 then produced[itemId] = stock - use; n = n - use end
    if n <= 0 then return end
    local viaId = via and via[itemId]
    local r = viaId and ds.recipes[viaId]
    if r and depth < 8 then
      local per = ns.Optimizer.AvgQty(r)
      local times = ceil(n / per)
      crafts[viaId] = (crafts[viaId] or 0) + times
      local made = times * per
      produced[itemId] = (produced[itemId] or 0) + made - n
      for _, rg in ipairs(r.reagents) do consume(rg[1], rg[2] * times, via, depth + 1) end
    else
      addNeed(itemId, n)
    end
  end

  for _, seg in ipairs(route.segments) do
    local r = ds.recipes[seg.recipe]
    local times = ceil(seg.crafts * (1 + margin))
    crafts[seg.recipe] = (crafts[seg.recipe] or 0) + times
    for _, rg in ipairs(r.reagents) do consume(rg[1], rg[2] * times, seg.via, 0) end
    if r.creates then
      local out = r.creates[1]
      produced[out] = (produced[out] or 0) + times * ns.Optimizer.AvgQty(r)
    end
  end

  local list = { items = {}, crafts = crafts, leftovers = {}, total = 0, unpriced = {} }
  for _, itemId in ipairs(ns.Util.sortedKeys(need)) do
    local n = ceil(need[itemId])
    local have = opts.have and opts.have(itemId) or nil
    local owned = 0
    if have then for _, c in pairs(have) do owned = owned + c end end
    local buy = math.max(0, n - owned)
    local price, kind, quote = pricer:Buy(itemId)
    local line = { itemId = itemId, need = n, have = have, owned = owned, buy = buy,
      unit = price, kind = kind, quote = quote, done = buy == 0 }
    if price then
      line.total = price * buy
      list.total = list.total + line.total
    elseif buy > 0 then
      list.unpriced[#list.unpriced + 1] = itemId
    end
    list.items[#list.items + 1] = line
  end
  for itemId, n in pairs(produced) do
    if n >= 1 then list.leftovers[itemId] = math.floor(n + 1e-9) end
  end

  -- One-time purchases: recipes and rank training.
  list.acquire = {}
  for _, seg in ipairs(route.segments) do
    if seg.acquire then
      list.acquire[#list.acquire + 1] = { recipe = seg.recipe, at = seg.from, how = seg.acquire }
      list.total = list.total + (seg.acquire.cost or 0)
    end
  end
  for _, st in ipairs(route.training or {}) do list.total = list.total + st.cost end
  return list
end
