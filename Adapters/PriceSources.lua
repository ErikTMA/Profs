-- Market data sources, all optional and all used side by side (Engine/Pricing.lua
-- picks by the configured precedence):
--   ahscan      Profs!' own Auction House scans (Adapters/AHScan.lua), this
--               realm+faction only, with scan time
--   tsm         TSM_API.GetCustomPriceValue(priceString, "i:<id>"): AuctionDB data the
--               TSM desktop app refreshes externally; no timestamp in the API
--   auctionator Auctionator.API.v1.GetAuctionPriceByItemID(callerId, itemId), age via
--               Auctionator.API.v1.GetAuctionAgeByItemID when that function exists
--   dataset     added by Pricing itself (average bundled with the dataset)
-- TSM and Auctionator are used only when their addon exposes the API at runtime.
local _, ns = ...
local PS = ns:NewModule("PriceSources")

PS.epoch = 0   -- bumped when price settings change (cached routes re-plan)

PS.TSM_PRICE = "dbmarket"   -- TSM price string for buying; dbminbuyout as fallback

local function tsm()
  if type(TSM_API) ~= "table" or type(TSM_API.GetCustomPriceValue) ~= "function" then return nil end
  local function value(str, id)
    local ok, v = pcall(TSM_API.GetCustomPriceValue, str, "i:" .. id)
    return ok and type(v) == "number" and v > 0 and v or nil
  end
  return {
    name = "TSM", kind = "tsm",
    quote = function(id)
      local v, which = value(PS.TSM_PRICE, id), PS.TSM_PRICE
      if not v then v, which = value("dbminbuyout", id), "dbminbuyout" end
      if not v then return nil end
      return { price = v, external = true, detail = "TSM " .. which .. " (refreshed by the TSM app)" }
    end,
    saleRate = function(id)
      local v = value("dbregionsalerate", id)
      -- TSM reports sale rate as a fraction; some builds return it scaled by 1000.
      if v and v > 1 then v = v / 1000 end
      return v
    end,
  }
end

local function auctionator(maxAge)
  local api = type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1
  if type(api) ~= "table" or type(api.GetAuctionPriceByItemID) ~= "function" then return nil end
  return {
    name = "Auctionator", kind = "auctionator",
    quote = function(id)
      local ok, v = pcall(api.GetAuctionPriceByItemID, ns.name, id)
      if not ok or type(v) ~= "number" or v <= 0 then return nil end
      local q = { price = v, detail = "Auctionator scan" }
      if type(api.GetAuctionAgeByItemID) == "function" then
        local ok2, days = pcall(api.GetAuctionAgeByItemID, ns.name, id)
        if ok2 and type(days) == "number" then
          q.age = days * 86400
          q.stale = q.age > maxAge
        end
      end
      return q
    end,
  }
end

function PS.Settings()
  local s = ns.db and ns.db.settings or {}
  return {
    precedence = s.pricePrecedence or ns.Pricing.DEFAULT_PRECEDENCE,
    maxAge = ns.Util.merge(ns.Pricing.DEFAULT_MAX_AGE, s.priceMaxAge or {}),
    policy = s.pricePolicy or "precedence",
  }
end

function PS.Available()
  local cfg = PS.Settings()
  local list = {}
  if ns.db and ns.db.ah and ns.AHScan then
    list[#list + 1] = ns.AHPrices.Source(ns.db.ah, ns.AHScan.Scope(),
      { now = ns.AHScan.Now, maxAge = cfg.maxAge.ahscan })
  end
  local t = tsm()
  if t then list[#list + 1] = t end
  local a = auctionator(cfg.maxAge.auctionator)
  if a then list[#list + 1] = a end
  return list
end

function PS.Pricer(ds)
  local cfg = PS.Settings()
  local manual = ns.db and ns.db.settings.manualPrices or {}
  return ns.Pricing.New(ds, { sources = PS.Available(), manual = manual,
    precedence = cfg.precedence, policy = cfg.policy })
end

-- "AH scan, 12 min ago" / "TSM (external)" / "Dataset (historical)" ...
function PS.Describe(q, kind)
  if kind == "vendor" then return "vendor" end
  if kind == "manual" then return "manual" end
  if not q then return "no price" end
  local label = ns.Pricing.LABEL[q.source] or tostring(q.name)
  if q.source == "ahscan" then
    label = label .. ", " .. ns.AHPrices.FormatAge(q.age)
  elseif q.external then
    label = label .. " (external)"
  elseif q.historical then
    label = label .. " (historical)"
  elseif q.age then
    label = label .. ", " .. ns.AHPrices.FormatAge(q.age)
  end
  if q.stale and not q.historical then label = label .. ", stale" end
  return label
end

-- /profs prices [order a,b,c | maxage <source> <hours> | lowest | precedence]
ns.commands.prices = function(rest)
  local s = ns.db.settings
  local cmd, arg1, arg2 = (rest or ""):match("^(%S*)%s*(%S*)%s*(%S*)")
  if cmd == "order" and arg1 ~= "" then
    local list, known = {}, { ahscan = true, tsm = true, auctionator = true, dataset = true }
    for k in arg1:gmatch("[^,]+") do
      if not known[k] then ns.Log("warn", "unknown source '" .. k .. "' (ahscan, tsm, auctionator, dataset)"); return end
      list[#list + 1] = k
    end
    s.pricePrecedence = list
  elseif cmd == "maxage" and tonumber(arg2) then
    s.priceMaxAge = s.priceMaxAge or {}
    s.priceMaxAge[arg1] = tonumber(arg2) * 3600
  elseif cmd == "lowest" or cmd == "precedence" then
    s.pricePolicy = cmd
  elseif cmd == "reset" then
    s.pricePrecedence, s.priceMaxAge, s.pricePolicy = nil, nil, nil
  end
  PS.epoch = PS.epoch + 1
  -- the shown route was priced with the old settings: re-plan it now
  if ns.Sidecar and ns.Sidecar.frame and ns.Sidecar.frame:IsShown() then ns.Sidecar.RequestRefresh() end
  local cfg = PS.Settings()
  ns.Log("info", ("price policy %s, order: %s"):format(cfg.policy, table.concat(cfg.precedence, " > ")))
  ns.Log("info", ("stale after: AH scan %.0f h, Auctionator %.0f h; TSM external, dataset historical"):format(
    cfg.maxAge.ahscan / 3600, cfg.maxAge.auctionator / 3600))
  local names = {}
  for _, src in ipairs(PS.Available()) do names[#names + 1] = src.name end
  ns.Log("info", "available: " .. table.concat(names, ", ") .. ", dataset")
end
