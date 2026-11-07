-- Price model. All prices are copper.
--
-- SOURCES. Each is a plain table, so tests and the adapters plug in the same way:
--   { name, kind,
--     quote = function(itemId) -> { price, at?, age?, stale?, scope?, detail? } | nil
--     -- or, legacy/simple:  market = function(itemId) -> copper | nil
--     saleRate = function(itemId) -> 0..1 | nil }
-- Kinds and what their freshness means:
--   ahscan       this player's own Auction House scans (Engine/AHPrices.lua): scan time,
--                realm/faction scope; stale after maxAge.ahscan (default 24 h)
--   tsm          TradeSkillMaster price strings: AuctionDB data the TSM desktop app
--                refreshes EXTERNALLY, without visiting the AH; the API exposes no
--                timestamp, so it is labelled "external" and never marked stale
--   auctionator  Auctionator's own scans; age from its API when available, stale
--                after maxAge.auctionator (default 3 days)
--   dataset      average buyout bundled with the profession dataset when it was
--                generated: historical, always treated as stale (used only when
--                nothing better)
--
-- PRECEDENCE (configurable, ProfsDB.settings.pricePrecedence): the first source in
-- order with a FRESH quote wins; if none is fresh, the first stale quote is used and
-- flagged stale. Default: ahscan, tsm, auctionator, dataset. Sources of other kinds are
-- tried after auctionator in the order given. policy = "lowest" instead takes the
-- cheapest quote (the pre-AH-sync behaviour).
--
-- BUY PRICE = manual override, else the cheaper of the vendor price (only items an
-- unlimited vendor sells, items[id].vbuy; always available, so it wins ties) and the
-- selected market quote.
local _, ns = ...
local PR = ns:NewModule("Pricing")

PR.DEFAULT_PRECEDENCE = { "ahscan", "tsm", "auctionator", "dataset" }
PR.DEFAULT_MAX_AGE = { ahscan = 24 * 3600, auctionator = 3 * 86400 }
PR.LABEL = { ahscan = "AH scan", tsm = "TSM", auctionator = "Auctionator", dataset = "Dataset",
  vendor = "vendor", manual = "manual" }

local Pricer = {}
Pricer.__index = Pricer

-- The dataset's bundled average buyout as a source.
function PR.DatasetSource(ds)
  return {
    name = "dataset", kind = "dataset",
    quote = function(itemId)
      local it = ds.items[itemId]
      if not (it and it.ah and it.ah > 0) then return nil end
      return { price = it.ah, stale = true, historical = true,
        detail = "dataset average, generated " .. tostring(ds.meta and ds.meta.generated or "?") }
    end,
  }
end

local function rank(precedence)
  local r = {}
  for i, k in ipairs(precedence) do r[k] = i end
  return r
end

function PR.New(ds, opts)
  opts = opts or {}
  local sources = {}
  for _, s in ipairs(opts.sources or {}) do sources[#sources + 1] = s end
  if opts.useDatasetAH ~= false then sources[#sources + 1] = PR.DatasetSource(ds) end
  local precedence = opts.precedence or PR.DEFAULT_PRECEDENCE
  local r = rank(precedence)
  local unknownRank = (r.auctionator or #precedence) + 0.5
  -- stable order: by precedence rank, then the order given
  local order = {}
  for i, s in ipairs(sources) do order[#order + 1] = { s = s, i = i, r = r[s.kind or s.name] or unknownRank } end
  table.sort(order, function(a, b) if a.r ~= b.r then return a.r < b.r end return a.i < b.i end)
  local sorted = {}
  for _, o in ipairs(order) do sorted[#sorted + 1] = o.s end
  return setmetatable({
    ds = ds,
    sources = sorted,
    manual = opts.manual or {},     -- [itemId] = copper (user override, wins outright)
    policy = opts.policy or "precedence",
    cache = {},
  }, Pricer)
end

function Pricer:Item(itemId) return self.ds.items[itemId] end

function Pricer:VendorBuy(itemId)
  local it = self.ds.items[itemId]
  return it and it.vbuy or nil
end

function Pricer:VendorSell(itemId)
  local it = self.ds.items[itemId]
  return it and it.vsell or 0
end

local function sourceQuote(src, itemId)
  if src.quote then
    local ok, q = pcall(src.quote, itemId)
    if ok and type(q) == "table" and type(q.price) == "number" and q.price > 0 then return q end
    return nil
  end
  if src.market then
    local ok, v = pcall(src.market, itemId)
    if ok and type(v) == "number" and v > 0 then return { price = v } end
  end
  return nil
end

-- Every source's quote for an item, in precedence order, each tagged with its source.
function Pricer:Quotes(itemId)
  local list = {}
  for _, src in ipairs(self.sources) do
    local q = sourceQuote(src, itemId)
    if q then
      q.source = src.kind or src.name
      q.name = src.name
      list[#list + 1] = q
    end
  end
  return list
end

-- The market quote precedence selects, with the alternatives it passed over.
function Pricer:Quote(itemId)
  local hit = self.cache[itemId]
  if hit ~= nil then return hit or nil end
  local list = self:Quotes(itemId)
  local chosen
  if self.policy == "lowest" then
    for _, q in ipairs(list) do if not chosen or q.price < chosen.price then chosen = q end end
  else
    for _, q in ipairs(list) do if not q.stale then chosen = q; break end end
    chosen = chosen or list[1]
  end
  if chosen then
    chosen.alternatives = {}
    for _, q in ipairs(list) do if q ~= chosen then chosen.alternatives[#chosen.alternatives + 1] = q end end
  end
  self.cache[itemId] = chosen or false
  return chosen
end

-- Selected market price and the source name it came from.
function Pricer:Market(itemId)
  local q = self:Quote(itemId)
  if not q then return nil end
  return q.price, q.name
end

function Pricer:SaleRate(itemId)
  for _, src in ipairs(self.sources) do
    if src.saleRate then
      local ok, v = pcall(src.saleRate, itemId)
      if ok and type(v) == "number" then return v, src.name end
    end
  end
  return nil
end

-- Returns copper, kind ("manual"|"vendor"|"market:<source name>"), quote|nil.
-- nil when nothing prices the item.
function Pricer:Buy(itemId)
  if self.manual[itemId] then return self.manual[itemId], "manual" end
  local v = self:VendorBuy(itemId)
  local q = self:Quote(itemId)
  if v and (not q or v <= q.price) then return v, "vendor", q end
  if q then return q.price, "market:" .. tostring(q.name), q end
  return nil
end

function Pricer:Invalidate() self.cache = {} end
