-- Native Auction House scanner. USER-INITIATED ONLY: every scan starts from a click
-- on the Profs! panel beside the open Auction House window, runs only while that
-- window is open, uses read queries only (no bids, buyouts or posts), and waits for
-- the client's own throttle (C_AuctionHouse.IsThrottledMessageSystemReady /
-- AUCTION_HOUSE_THROTTLED_SYSTEM_READY) before every request. Closing the AH stops
-- it; what was already priced is kept (partial scan).
--
-- APIs (Blizzard UI source, branch `forever`, 1.60.1 build 70840):
--   list scan  C_AuctionHouse.MakeItemKey + SendSearchQuery(itemKey, sorts, false)
--              -> COMMODITY_SEARCH_RESULTS_UPDATED(itemID): GetNumCommoditySearchResults
--                 / GetCommoditySearchResultInfo -> {quantity, unitPrice}
--              -> ITEM_SEARCH_RESULTS_UPDATED(itemKey): GetNumItemSearchResults /
--                 GetItemSearchResultInfo -> {quantity, buyoutAmount} (buyoutAmount is
--                 the whole auction: Blizzard's buy frame passes it to PlaceBid)
--   full scan  C_AuctionHouse.ReplicateItems -> REPLICATE_ITEM_LIST_UPDATE ->
--              GetNumReplicateItems / GetReplicateItemInfo(index), index 0-based (its
--              doc type is `number`, not `luaIndex`); fields 3 count, 10 buyoutPrice,
--              17 itemID
-- UNVERIFIED on Forever (no live scan yet): the full-scan server cooldown (15 min on
-- retail; enforced here client-side), whether commodity search covers every stackable
-- reagent, and result latency.
local _, ns = ...
local S = ns:NewModule("AHScan")

S.ITEM_TIMEOUT = 10        -- seconds to wait for one item's results
S.MAX_RETRIES = 2          -- per item, after a dropped/throttled message
S.REPLICATE_TIMEOUT = 90   -- seconds to wait for the full-scan list
S.BATCH = 1000             -- replicate rows processed per frame

S.state = { running = false }
S.open = false

local function AHapi(name) return C_AuctionHouse and C_AuctionHouse[name] end

local function plain(v)
  -- secret values (C_Secrets era): never do arithmetic on them
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

function S.Now()
  if GetServerTime then return GetServerTime() end
  return time and time() or 0
end

function S.Scope()
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName())
    or (GetRealmName and GetRealmName()) or "realm"
  local faction = UnitFactionGroup and UnitFactionGroup("player") or "?"
  if realm == "" then realm = "realm" end
  return tostring(realm) .. "|" .. tostring(faction)
end

local function store() return ns.db.ah end

local function bucket() return ns.AHPrices.Bucket(store(), S.Scope()) end

local function fire() ns.Events.Fire("PROFS_AH_SCAN", S.state) end

function S.Supported()
  return AHapi("SendSearchQuery") ~= nil and AHapi("MakeItemKey") ~= nil
end

function S.FullSupported() return AHapi("ReplicateItems") ~= nil and AHapi("GetReplicateItemInfo") ~= nil end

function S.FullCooldown()
  local b = bucket()
  if not b.lastFull then return 0 end
  return math.max(0, ns.AHPrices.FULL_SCAN_COOLDOWN - (S.Now() - b.lastFull))
end

local function after(sec, fn) if C_Timer and C_Timer.After then C_Timer.After(sec, fn) end end

local function finish(status, err)
  local st = S.state
  if not st.running then return end
  st.running = false
  st.status = status
  st.error = err
  st.finished = S.Now()
  st.pending = nil
  local b = bucket()
  b.last = { kind = st.kind, started = st.started, finished = st.finished, status = status,
    total = st.total, done = st.done, priced = st.priced, none = st.none, errors = st.errors, error = err }
  if st.kind == "full" and status == "complete" then b.lastFull = st.started end
  if ns.Sidecar and ns.Sidecar.frame and ns.Sidecar.frame:IsShown() then ns.Sidecar.Refresh() end
  fire()
end

function S.Stop(reason) finish("stopped", reason) end

-- list scan --------------------------------------------------------------------

local sendNext

local function advance(ok)
  local st = S.state
  st.pending = nil
  st.done = st.done + 1
  if not ok then st.errors = st.errors + 1 end
  fire()
  sendNext()
end

local function recordItem(id, obs)
  local st = S.state
  ns.AHPrices.Record(store(), S.Scope(), id, obs, S.Now(), "list")
  if obs.none then st.none = st.none + 1 else st.priced = st.priced + 1 end
end

sendNext = function()
  local st = S.state
  if not st.running then return end
  if not S.open then finish("interrupted", "Auction House closed"); return end
  if st.pending then return end
  local id = st.queue[st.done + 1]
  if not id then finish("complete"); return end
  local ready = AHapi("IsThrottledMessageSystemReady")
  if ready and not ready() then st.waiting = "throttle"; fire(); return end -- resumed by event / poll
  st.waiting = nil
  local key = C_AuctionHouse.MakeItemKey(id)
  local priceSort = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0
  local ok, err = pcall(C_AuctionHouse.SendSearchQuery, key, { { sortOrder = priceSort, reverseSort = false } }, false)
  if not ok then
    finish("error", "search failed: " .. tostring(err)); return
  end
  local token = {}
  st.pending = { id = id, token = token, tries = (st.retry and st.retry[id] or 0) }
  after(S.ITEM_TIMEOUT, function()
    if st.pending and st.pending.token == token then
      st.timeouts = (st.timeouts or 0) + 1
      advance(false)
    end
  end)
end

function S.OnCommodityResults(itemID)
  local st = S.state
  if not (st.running and st.pending and st.pending.id == itemID) then return end
  local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
  local rows = {}
  for i = 1, n do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    if r then rows[#rows + 1] = { plain(r.quantity), plain(r.unitPrice) } end
  end
  recordItem(itemID, ns.AHPrices.ReduceCommodity(rows, st.want and st.want[itemID]))
  advance(true)
end

function S.OnItemResults(itemKey)
  local st = S.state
  local id = type(itemKey) == "table" and itemKey.itemID
  if not (st.running and st.pending and st.pending.id == id) then return end
  local n = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
  local rows = {}
  for i = 1, n do
    local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    if r then rows[#rows + 1] = { id, plain(r.quantity), plain(r.buyoutAmount) } end
  end
  local red = ns.AHPrices.ReduceListings(rows)[id]
  recordItem(id, red or { none = true })
  advance(true)
end

function S.OnThrottleReady()
  local st = S.state
  if st.running and st.kind == "list" and st.waiting == "throttle" then sendNext() end
end

function S.OnMessageDropped()
  local st = S.state
  if not (st.running and st.kind == "list" and st.pending) then return end
  local id = st.pending.id
  st.retry = st.retry or {}
  st.retry[id] = (st.retry[id] or 0) + 1
  st.pending = nil
  if st.retry[id] > S.MAX_RETRIES then advance(false) else after(1, sendNext) end
end

-- items = { itemId, ... }, want = { [itemId] = units needed } (for the fill price)
function S.StartList(items, want)
  if S.state.running then return false, "a scan is already running" end
  if not S.open then return false, "open the Auction House first" end
  if not S.Supported() then return false, "this client has no Auction House search API" end
  local queue, seen = {}, {}
  for _, id in ipairs(items or {}) do
    if not seen[id] then seen[id] = true; queue[#queue + 1] = id end
  end
  if #queue == 0 then return false, "nothing to scan: plan a route first (open a profession)" end
  S.state = { running = true, kind = "list", queue = queue, want = want or {}, total = #queue,
    done = 0, priced = 0, none = 0, errors = 0, started = S.Now() }
  if C_Timer and C_Timer.NewTicker then
    -- fallback poll in case the throttle-ready event is missed
    local st = S.state
    st.ticker = C_Timer.NewTicker(1, function()
      if not st.running then if st.ticker and st.ticker.Cancel then st.ticker:Cancel() end return end
      if st.waiting == "throttle" then sendNext() end
    end)
  end
  fire()
  sendNext()
  return true
end

-- full scan ----------------------------------------------------------------------

-- `track` = { [itemId] = true } items whose absence the full scan may record as
-- "none listed" (dataset items; keeps SavedVariables bounded).
function S.StartFull(track)
  if S.state.running then return false, "a scan is already running" end
  if not S.open then return false, "open the Auction House first" end
  if not S.FullSupported() then return false, "this client has no full-scan API" end
  local cd = S.FullCooldown()
  if cd > 0 then return false, ("full scan available again in %d min"):format(math.ceil(cd / 60)) end
  S.state = { running = true, kind = "full", total = 0, done = 0, priced = 0, none = 0, errors = 0,
    started = S.Now(), track = track or {}, phase = "requesting" }
  local st = S.state
  local ok, err = pcall(C_AuctionHouse.ReplicateItems)
  if not ok then finish("error", "full scan request failed: " .. tostring(err)); return false, err end
  after(S.REPLICATE_TIMEOUT, function()
    if st.running and st.phase == "requesting" then finish("error", "no full-scan data from the server (timeout)") end
  end)
  fire()
  return true
end

function S.OnReplicateList()
  local st = S.state
  if not (st.running and st.kind == "full" and st.phase == "requesting") then return end
  st.phase = "reading"
  st.total = C_AuctionHouse.GetNumReplicateItems() or 0
  st.rows = {}
  local index = 0
  local function batch()
    if not st.running then return end
    if not S.open then finish("interrupted", "Auction House closed while reading"); return end
    local stop = math.min(st.total, index + S.BATCH)
    while index < stop do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(index)
      itemID, count, buyout = plain(itemID), plain(count), plain(buyout)
      if itemID then st.rows[#st.rows + 1] = { itemID, count, buyout } end
      index = index + 1
    end
    st.done = index
    fire()
    if index < st.total then after(0, batch); return end
    local t = S.Now()
    local reduced = ns.AHPrices.ReduceListings(st.rows)
    st.rows = nil
    for id in pairs(st.track) do
      local e = reduced[id]
      if e then
        ns.AHPrices.Record(store(), S.Scope(), id, e, t, "full"); st.priced = st.priced + 1
      else
        ns.AHPrices.Record(store(), S.Scope(), id, { none = true }, t, "full"); st.none = st.none + 1
      end
    end
    finish("complete")
  end
  batch()
end

-- wiring ---------------------------------------------------------------------------

function S.OnEvent(event, ...)
  if event == "AUCTION_HOUSE_SHOW" then
    S.open = true
    if ns.AHPanel then ns.AHPanel.Show() end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    S.open = false
    if S.state.running then finish("interrupted", "Auction House closed") end
    if ns.AHPanel then ns.AHPanel.Hide() end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    S.OnThrottleReady()
  elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    S.OnMessageDropped()
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    S.OnCommodityResults(...)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    S.OnItemResults(...)
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    S.OnReplicateList()
  elseif event == "AUCTION_HOUSE_DISABLED" then
    if S.state.running then finish("error", "Auction House disabled") end
  elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
    local st = S.state
    if st.running then st.lastError = tostring((...)); st.errors = st.errors + 1; fire() end
  end
end

S.EVENTS = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "COMMODITY_SEARCH_RESULTS_UPDATED",
  "ITEM_SEARCH_RESULTS_UPDATED", "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_DISABLED",
  "AUCTION_HOUSE_SHOW_ERROR" }

ns.Events.On("PROFS_LOADED", function()
  ProfsDB.ah = ProfsDB.ah or {}
  if not CreateFrame then return end
  local f = CreateFrame("Frame")
  for _, e in ipairs(S.EVENTS) do f:RegisterEvent(e) end
  f:SetScript("OnEvent", function(_, e, ...) S.OnEvent(e, ...) end)
  S.frame = f
end)
