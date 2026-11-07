-- Native Auction House price store (pure; the scanner in Adapters/AHScan.lua feeds it).
--
-- Persisted in ProfsDB.ah, one bucket per SCOPE (realm + faction; the client's AH is
-- shared by a realm's faction):
--   ah[scope] = {
--     items = { [itemId] = { p = min unit buyout (copper), q = units listed,
--                            n = listings, t = scan time (server seconds),
--                            how = "list"|"full", none = true when the scan saw no
--                            listing at all } },
--     lastFull = server time of the last COMPLETE full (replicate) scan,
--     last = { kind, started, finished, status, total, done, priced, none, errors },
--   }
-- Only what the user's own scans saw is stored; a missing entry means "never scanned",
-- `none` means "scanned and nothing was listed". Nothing here talks to the game.
local _, ns = ...
local AH = ns:NewModule("AHPrices")

AH.DEFAULT_MAX_AGE = 24 * 3600     -- a scan older than this is stale
AH.FULL_SCAN_COOLDOWN = 15 * 60    -- client/server limit on ReplicateItems (see AHScan)

function AH.Bucket(store, scope)
  local b = store[scope]
  if not b then b = { items = {} }; store[scope] = b end
  b.items = b.items or {}
  return b
end

-- obs = { p, q, n } or { none = true }
function AH.Record(store, scope, itemId, obs, t, how)
  local b = AH.Bucket(store, scope)
  if obs.none then
    b.items[itemId] = { none = true, t = t, how = how }
  else
    b.items[itemId] = { p = obs.p, q = obs.q, n = obs.n, t = t, how = how }
  end
end

function AH.Get(store, scope, itemId)
  local b = store[scope]
  return b and b.items and b.items[itemId] or nil
end

-- Reduce raw listings { {itemId, count, buyout}, ... } (buyout = whole listing) to
-- { [itemId] = { p = cheapest unit price, q = units, n = listings } }. Listings
-- without a buyout (bid-only) or with count 0 do not price an item.
function AH.ReduceListings(rows)
  local out = {}
  for _, r in ipairs(rows) do
    local id, count, buyout = r[1], r[2], r[3]
    if id and count and count > 0 and buyout and buyout > 0 then
      local unit = buyout / count
      local e = out[id]
      if not e then
        out[id] = { p = unit, q = count, n = 1 }
      else
        if unit < e.p then e.p = unit end
        e.q = e.q + count
        e.n = e.n + 1
      end
    end
  end
  for _, e in pairs(out) do e.p = math.floor(e.p + 0.5) end
  return out
end

-- Commodity results (already sorted by price by the server): { {qty, unitPrice} }.
-- Returns { p = cheapest, q, n, fill = average unit price paying for `want` units }.
function AH.ReduceCommodity(results, want)
  local out = { q = 0, n = 0 }
  local remaining, spent, bought = want or 0, 0, 0
  for _, r in ipairs(results) do
    local qty, unit = r[1], r[2]
    if qty and qty > 0 and unit and unit > 0 then
      out.n = out.n + 1
      out.q = out.q + qty
      if not out.p or unit < out.p then out.p = unit end
      if remaining > 0 then
        local take = math.min(qty, remaining)
        spent, bought, remaining = spent + take * unit, bought + take, remaining - take
      end
    end
  end
  if not out.p then return { none = true } end
  if bought > 0 then out.fill = math.floor(spent / bought + 0.5) end
  return out
end

-- A Pricing source over the store, for one scope.
--   opts.now()      current server time
--   opts.maxAge     seconds before an entry counts as stale
function AH.Source(store, scope, opts)
  opts = opts or {}
  local maxAge = opts.maxAge or AH.DEFAULT_MAX_AGE
  return {
    name = "ahscan", kind = "ahscan",
    quote = function(itemId)
      local e = AH.Get(store, scope, itemId)
      if not e or e.none or not e.p then return nil end
      local now = opts.now and opts.now() or nil
      local age = now and e.t and (now - e.t) or nil
      return { price = e.p, at = e.t, age = age, stale = age ~= nil and age > maxAge,
        scope = scope, detail = e.how == "full" and "full scan" or "list scan" }
    end,
  }
end

-- Scan status summary for the UI.
function AH.Status(store, scope, now)
  local b = store[scope]
  if not b then return { scanned = 0 } end
  local scanned, priced, newest, oldest = 0, 0, nil, nil
  for _, e in pairs(b.items) do
    scanned = scanned + 1
    if e.p then priced = priced + 1 end
    if e.t then
      if not newest or e.t > newest then newest = e.t end
      if not oldest or e.t < oldest then oldest = e.t end
    end
  end
  local cooldown = 0
  if b.lastFull and now then cooldown = math.max(0, AH.FULL_SCAN_COOLDOWN - (now - b.lastFull)) end
  return { scanned = scanned, priced = priced, newest = newest, oldest = oldest,
    last = b.last, lastFull = b.lastFull, fullCooldown = cooldown }
end

function AH.FormatAge(seconds)
  if not seconds then return "unknown age" end
  if seconds < 90 then return "just now" end
  if seconds < 3600 then return ("%d min ago"):format(math.floor(seconds / 60 + 0.5)) end
  if seconds < 48 * 3600 then return ("%.0f h ago"):format(seconds / 3600) end
  return ("%.0f days ago"):format(seconds / 86400)
end
