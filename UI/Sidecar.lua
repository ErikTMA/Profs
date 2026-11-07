-- The Profs! route view: a third column INSIDE the native ProfessionsFrame, right of
-- the recipe details (UI/Embed.lua; or a detached, movable panel when another addon
-- such as TradeSkillMaster replaces the native window). Shows the route to the
-- persistent target, the next guided step with a Craft button, the consolidated
-- shopping list and output recommendations, for whichever profession is selected.
--
-- The text builders (Sidecar.Format*) are pure and unit tested; the frame code only
-- renders their output.
local _, ns = ...
local S = ns:NewModule("Sidecar")
local U = ns.Util

S.MODES = { "cheapest", "fastest", "balanced" }
S.MODE_LABEL = { cheapest = "Cheapest", fastest = "Fastest", balanced = "Balanced" }

local function color(c, text) return "|cff" .. c .. text .. "|r" end

local function itemName(ds, id)
  local it = ds.items[id]
  local live = ns.Game and ns.Game.ItemName and ns.Game.ItemName(id)
  return live or (it and it.n) or ("item " .. id)
end
S.ItemName = itemName

local function npcText(ds, npcId)
  local n = ds.npcs[npcId]
  if not n then return "npc " .. npcId end
  local where = n.zone or "?"
  if n.x and n.y then where = ("%s (%.1f, %.1f)"):format(where, n.x, n.y) end
  return ("%s - %s"):format(n.n or ("npc " .. npcId), where)
end

local CLASSIFICATION = { [1] = "elite", [2] = "rare elite", [3] = "boss", [4] = "rare" }

local function pct(p)
  if p >= 10 then return ("%.0f%%"):format(p) end
  if p >= 1 then return ("%.1f%%"):format(p) end
  return (("%.3f"):format(p):gsub("0+$", "")) .. "%"
end

-- Lines for a drop source: the best mobs (exporter order: well-sampled first, then the
-- lower bound of the chance) with level, zone and spawn point, drop chance and sample.
-- mobs = { {npcId, percent (-1 = not measured), kills, pickpocket?}, ... }, nmobs = mobs
-- dropping it in all.
function S.DropLines(ds, src, max)
  local lines = {}
  local mobs = src.mobs or {}
  if #mobs == 0 then
    lines[1] = color(ns.Theme.color.muted, "  The data does not say which mob drops it.")
    return lines
  end
  local n = src.nmobs or #mobs
  if n > #mobs then
    lines[1] = ("  Drops from %d mobs%s; best chances:"):format(n, n >= 30 and " (world drop)" or "")
  end
  for i, m in ipairs(mobs) do
    if i > (max or 3) then break end
    local npc = ds.npcs[m[1]] or {}
    local tags = {}
    if npc.lv then tags[#tags + 1] = npc.lv[1] == npc.lv[2] and tostring(npc.lv[1]) or (npc.lv[1] .. "-" .. npc.lv[2]) end
    if npc.cl and CLASSIFICATION[npc.cl] then tags[#tags + 1] = CLASSIFICATION[npc.cl] end
    local where = npc.zone or "zone unknown"
    if npc.x and npc.y then where = ("%s (%.1f, %.1f)"):format(where, npc.x, npc.y)
    elseif npc.zone then where = where .. " (instance)" end
    lines[#lines + 1] = ("  %s%s%s - %s: %s"):format(m[4] == 1 and "Pick-pocket " or "",
      npc.n or ("npc " .. m[1]), #tags > 0 and (" (" .. table.concat(tags, ", ") .. ")") or "", where,
      m[2] < 0 and color(ns.Theme.color.muted, "chance unknown")
        or (pct(m[2]) .. color(ns.Theme.color.muted, (" (%d kills seen)"):format(m[3]))))
  end
  return lines
end

-- Acquisition instructions for one recipe source. side = "A"/"H"/nil (player faction):
-- only NPCs that faction can use are listed (Engine/Faction.lua); NPCs whose access the
-- data does not establish are labelled, never presented as accessible.
function S.FormatAcquire(ds, recipeId, how, side)
  local r = ds.recipes[recipeId]
  local lines = { ("Learn %s (skill %d)"):format(r.name or ("recipe " .. recipeId), r.learn) }
  if not how then return lines end
  local src = how.source or {}
  if how.t == "known" then
    lines[#lines + 1] = "Already known."
  elseif how.t == "starter" then
    lines[#lines + 1] = "Granted when you learn the profession."
  elseif how.t == "trainer" then
    lines[#lines + 1] = src.unknownCost and "Trainer (cost not in the data)."
      or ("Trainer, %s."):format(U.money(src.cost or how.cost))
  elseif how.t == "vendor" then
    if src.unknownCost then
      lines[#lines + 1] = ("Vendor recipe (price and vendor not in the data; %s assumed)."):format(U.money(how.cost))
    else
      lines[#lines + 1] = ("Buy %s from a vendor, %s%s."):format(itemName(ds, src.item or 0),
        U.money(src.cost or how.cost), src.limited and " (limited stock)" or "")
    end
  elseif how.t == "token" then
    local parts = {}
    for _, c in ipairs(src.currencies or {}) do
      local n = ns.Game.CurrencyName and ns.Game.CurrencyName(c[1])
      parts[#parts + 1] = ("%d %s"):format(c[2], n or ("of currency #" .. c[1]))
    end
    for _, c in ipairs(src.costItems or {}) do
      parts[#parts + 1] = ("%d x %s"):format(c[2], itemName(ds, c[1]))
    end
    if (src.cost or 0) > 0 then parts[#parts + 1] = U.money(src.cost) end
    lines[#lines + 1] = ("Buy %s from a vendor for %s%s."):format(itemName(ds, src.item or 0),
      table.concat(parts, " + "), src.limited and " (limited stock)" or "")
  elseif how.t == "reputation" then
    lines[#lines + 1] = ("Reputation vendor (standing %s), %s."):format(tostring(src.standing),
      U.money(src.cost))
  elseif how.t == "drop" then
    lines[#lines + 1] = ("Pattern drops: %s."):format(itemName(ds, src.item or 0))
    for _, l in ipairs(S.DropLines(ds, src)) do lines[#lines + 1] = l end
  elseif how.t == "locked" then
    lines[#lines + 1] = "You locked this recipe; source not in your allowed list."
  else
    lines[#lines + 1] = ("Source: %s%s."):format(how.t, src.item and (" (" .. itemName(ds, src.item) .. ")") or "")
  end
  local F = ns.Faction
  if src.npcs and #src.npcs > 0 then
    local best, shown = F.Source(ds.npcs, src, side)
    local who = how.t == "trainer" and "trainer" or "vendor"
    if #shown == 0 then
      lines[#lines + 1] = ("  No %s for the %s in the data (only %s)."):format(who,
        side and F.NAME[side] or "your faction", best == "territory" and "in enemy cities" or "for the other faction")
    else
      for i, e in ipairs(shown) do
        if i > 3 then break end
        lines[#lines + 1] = "  " .. npcText(ds, e.id)
          .. (e.access == "unknown" and color(ns.Theme.color.muted, "  (faction access unknown)") or "")
      end
    end
    if not side then
      lines[#lines + 1] = color(ns.Theme.color.muted, "  Your faction could not be read: access to these NPCs is not confirmed.")
    end
  elseif how.t == "trainer" or how.t == "vendor" then
    lines[#lines + 1] = color(ns.Theme.color.muted, "  The data names no NPC for this; check in game.")
  end
  return lines
end

-- Route rows: one per segment plus training steps, in skill order. Each row has the
-- step text on the left and its gold cost on the right; iconItem is the crafted item.
function S.FormatRoute(ds, route, overrides)
  local rows = {}
  local locks = overrides and overrides.locks or {}
  local cb = ns.Theme.Colorblind()
  local function lockedAt(seg)
    for _, l in ipairs(locks) do
      if l.recipe == seg.recipe and l.from <= seg.from and l.to >= seg.to then return true end
    end
    return false
  end
  local function trainRow(t)
    return { kind = "train", text = color(ns.Theme.color.train, ("Train %s by %d"):format(t.rank, t.by)),
      right = U.money(t.cost), step = t, icon = "Interface\\Icons\\INV_Misc_Book_09" }
  end
  local training = {}
  for _, t in ipairs(route.training or {}) do training[#training + 1] = t end
  local ti = 1
  for _, seg in ipairs(route.segments) do
    while training[ti] and training[ti].by <= seg.from do
      rows[#rows + 1] = trainRow(training[ti])
      ti = ti + 1
    end
    local c = ns.Theme.SKILL[seg.colorAtStart] or "ffffff"
    local r = ds.recipes[seg.recipe]
    local marker = cb and ns.Theme.SKILL_MARKER[seg.colorAtStart] or ""
    local text = ("%3d-%3d %s%s x%s%d%s%s"):format(seg.from, seg.to,
      color(c, seg.name or tostring(seg.recipe)), marker ~= "" and (" " .. marker) or "",
      r and r.est and "~" or "", seg.craftsCeil,
      seg.acquire and color(ns.Theme.color.learn, "  [learn]") or "",
      lockedAt(seg) and color(ns.Theme.color.locked, " [locked]") or "")
    rows[#rows + 1] = { kind = "segment", text = text, right = U.money(seg.gold), segment = seg,
      recipe = seg.recipe, recipeName = r and r.name,
      recipeProf = r and r.prof and ns.Professions.Name(r.prof) or nil,
      iconItem = r and r.creates and r.creates[1] }
  end
  while training[ti] do
    rows[#rows + 1] = trainRow(training[ti])
    ti = ti + 1
  end
  if route.stock and next(route.stock) then
    local tip, n = { "Reagents you already have, used before buying:" }, 0
    for _, id in ipairs(ns.Util.sortedKeys(route.stock)) do
      n = n + 1
      tip[#tip + 1] = ("%d x %s"):format(route.stock[id], itemName(ds, id))
    end
    tip[#tip + 1] = "They count at their vendor price (what you give up), not the buy price."
    rows[#rows + 1] = { kind = "stock", summary = true,
      text = color(ns.Theme.color.muted, ("Uses %d reagent type%s you have"):format(n, n == 1 and "" or "s")),
      right = (route.stockSaved or 0) > 0 and color(ns.Theme.color.done, "saves " .. U.money(route.stockSaved)) or nil,
      tooltip = tip }
  end
  for _, w in ipairs(route.warnings or {}) do
    rows[#rows + 1] = { kind = "warning", text = color(ns.Theme.color.warn, w) }
  end
  return rows
end

local WHERE_ORDER = { "bags", "bank", "mail", "alts" }

-- "AH scan, 12 min ago" / "TSM (external)" / "Dataset (historical)" / "vendor"
function S.PriceLabel(line)
  if ns.PriceSources and ns.PriceSources.Describe then return ns.PriceSources.Describe(line.quote, line.kind) end
  return tostring(line.kind)
end

function S.FormatShopping(ds, list)
  local rows = {}
  for _, l in ipairs(list.items) do
    local have = {}
    for _, k in ipairs(WHERE_ORDER) do
      if l.have and l.have[k] and l.have[k] > 0 then have[#have + 1] = k .. " " .. l.have[k] end
    end
    local status = l.done and color(ns.Theme.color.done, "done") or ("buy " .. l.buy)
    local name = itemName(ds, l.itemId)
    rows[#rows + 1] = { item = l.itemId,
      text = ("%s  %d/%d  %s%s"):format(name, l.owned, l.need, status,
        #have > 0 and color(ns.Theme.color.muted, "  (" .. table.concat(have, ", ") .. ")") or ""),
      right = l.unit and (U.money(l.unit) .. " ea") or color(ns.Theme.color.warn, "no price"),
      tooltip = { name, l.unit and ("Price: " .. S.PriceLabel(l)) or "No price from any source." } }
  end
  rows[#rows + 1] = { text = "Total to spend", right = U.money(list.total), summary = true }
  return rows
end

-- Outputs of the route with what to do with them.
function S.FormatOutputs(ds, route, pricer, ctx)
  local rows, seen = {}, {}
  for _, seg in ipairs(route.segments) do
    local r = ds.recipes[seg.recipe]
    local out = r.creates and r.creates[1]
    if out and not seen[out] then
      seen[out] = true
      local v = ns.Recovery.Evaluate(ds, pricer, out, ctx)
      local parts = { ("Vendor %s"):format(U.money(v.vendor)) }
      if v.ah then
        parts[#parts + 1] = ("AH ~%s%s"):format(U.money(v.ah),
          v.saleRate and (" (sells %d%% of the time)"):format(math.floor(v.saleRate * 100 + 0.5)) or "")
      end
      if v.deValue then
        parts[#parts + 1] = ("DE ~%s%s"):format(U.money(v.deValue), v.deEstimated and " (est.)" or "")
      end
      local name = itemName(ds, out)
      local tip = { name, "Best: " .. v.action }
      for _, p in ipairs(parts) do tip[#tip + 1] = p end
      rows[#rows + 1] = { item = out, action = v.action, text = name,
        right = color(ns.Theme.color.gold, v.action), tooltip = tip }
    end
  end
  if #rows > 0 then
    rows[#rows + 1] = { summary = true,
      text = color(ns.Theme.color.muted, "AH and DE values are speculative; Cheapest counts vendor value only.") }
  end
  return rows
end

-- Controller -----------------------------------------------------------------

S.state = {}

function S.Options(prof)
  local cdb = ns.cdb
  local o = ns.Routes.Overrides(cdb, prof)
  local t = cdb.targets[prof] or {}
  local known = cdb.known and cdb.known[prof] or {}
  local settings = ns.db and ns.db.settings or {}
  return {
    mode = t.mode or "cheapest",
    known = known,
    exclude = o.exclude,
    locks = o.locks,
    charLevel = UnitLevel and UnitLevel("player") or nil,
    allowSources = settings.allowSources,
    craftValue = settings.craftValue,
    side = ns.Game.Faction(),
  }
end

-- Route cache (per session, per profession). Planning a full route costs 60-230 ms
-- on Lua 5.1 with the forever dataset, and switching profession tabs fires several
-- events, so routes are only re-planned when something that shapes them changes:
-- everything in PlanKey. Gaining skill along the cached route is NOT such a change:
-- the route is trimmed to the new skill (Routes.Remaining). Inventory changes only
-- rebuild the shopping list and the next step, which are cheap.
S.cache = {}
S.stats = { plans = 0, hits = 0 }

local function sortedIds(set)
  local t = {}
  for id, on in pairs(set or {}) do if on then t[#t + 1] = id end end
  table.sort(t)
  return table.concat(t, ",")
end

function S.PlanKey(ds, prof, target, opts)
  local locks = {}
  for _, l in ipairs(opts.locks or {}) do locks[#locks + 1] = l.from .. "-" .. l.to .. ":" .. l.recipe end
  local manual = {}
  for id, v in pairs(ns.db and ns.db.settings.manualPrices or {}) do manual[#manual + 1] = id .. "=" .. v end
  table.sort(manual)
  return table.concat({
    tostring(ds.meta and ds.meta.generated), prof, target, opts.mode, tostring(opts.side),
    tostring(opts.charLevel), tostring(opts.craftValue), sortedIds(opts.allowSources),
    sortedIds(opts.known), sortedIds(opts.exclude), table.concat(locks, ","),
    table.concat(manual, ","), ns.AHPrices.epoch, ns.PriceSources.epoch,
  }, "|")
end

function S.ClearCache() S.cache = {} end

-- What the player owns of this profession's reagents (bags, bank, mail, alts: the
-- same counts the shopping list nets against). The optimizer uses it before buying.
function S.Owned(ds, prof)
  local out, seen = {}, {}
  for _, r in ipairs(ds.recipesByProf[prof] or {}) do
    for _, rg in ipairs(r.reagents or {}) do
      local id = rg[1]
      if not seen[id] then
        seen[id] = true
        local n = 0
        for _, c in pairs(ns.Inventory.Have(id) or {}) do n = n + c end
        if n > 0 then out[id] = n end
      end
    end
  end
  return out
end

-- Using up reagents while following the route is expected and keeps the cached route;
-- getting more of one (loot, mail, the AH) can make another route cheaper: re-plan.
function S.StockGrew(before, now)
  before = before or {}
  for id, n in pairs(now or {}) do
    if n > (before[id] or 0) then return true end
  end
  return false
end

-- Recompute the route for the open profession. Returns the state or nil.
function S.Plan()
  local info = ns.Game.OpenProfession()
  local ds = ns.ActiveDataset()
  local st = S.state
  st.info, st.ds = info, ds
  st.gathering = false
  if not info or not info.own or not ds then st.route = nil; return st end
  local prof = info.prof
  local meta = ns.Professions.list[prof]
  if not meta or meta.crafting == false then st.route = nil; st.gathering = true; return st end
  -- remember learned recipes for this profession
  ns.cdb.known = ns.cdb.known or {}
  local known = ns.cdb.known[prof] or {}
  local skillUps = {}
  for id, r in pairs(ns.Game.ScanRecipes()) do
    if r.learned then known[id] = true end
    skillUps[id] = r.numSkillUps
  end
  ns.cdb.known[prof] = known
  local target = (ns.cdb.targets[prof] and ns.cdb.targets[prof].to) or ns.Professions.MaxSkill(prof, ds)
  st.target = target
  local opts = S.Options(prof)
  st.pricer = ns.PriceSources.Pricer(ds)
  opts.pricer = st.pricer
  st.mode = opts.mode
  if info.skill >= target then st.route = nil; st.done = true; return st end
  st.done = false
  opts.owned = S.Owned(ds, prof)
  local key = S.PlanKey(ds, prof, target, opts)
  local c = S.cache[prof]
  if c and c.key == key and info.skill >= c.skill
      and info.skill <= (c.route.unreachable or c.route.to) and not S.StockGrew(c.owned, opts.owned) then
    st.route = ns.Routes.Remaining(ds, c.route, info.skill, opts.charLevel)
    S.stats.hits = S.stats.hits + 1
  else
    st.route = ns.Optimizer.Plan(ds, prof, info.skill, target, opts)
    S.cache[prof] = { key = key, route = st.route, skill = info.skill, owned = opts.owned }
    S.stats.plans = S.stats.plans + 1
  end
  local items = {}
  for _, seg in ipairs(st.route.segments) do
    for _, rg in ipairs(seg.reagents) do items[#items + 1] = rg[1] end
  end
  ns.Inventory.Track(items)
  st.list = ns.Shopping.Build(ds, st.route, { pricer = st.pricer, have = ns.Inventory.Have,
    margin = (ns.db.settings.margin or 0) })
  -- what the AH shopping-list scan should price for this profession
  ns.cdb.scanList = ns.cdb.scanList or {}
  local scan = {}
  for _, l in ipairs(st.list.items) do
    if not (l.kind == "vendor" and l.unit) then scan[l.itemId] = math.max(l.buy, 1) end
  end
  ns.cdb.scanList[prof] = scan
  st.next = ns.Routes.Next(ds, st.route, info.skill, function(id) return ns.Game.ItemCount(id, false) end,
    function(id) return skillUps[id] end)
  return st
end

-- Craft button: queues the crafts that cannot overshoot the step's end (Routes.SafeCount;
-- an addon cannot interrupt a queued craft). Shift-click queues every expected craft.
function S.CraftNext()
  local n = S.state.next
  if not n or n.batch <= 0 then return false end
  local count = (IsShiftKeyDown and IsShiftKeyDown()) and n.batch or (n.safe or n.batch)
  if count <= 0 then return false end
  return ns.Game.Craft(n.segment.recipe, count)
end

function S.CraftTooltip(n)
  local t = { ("Craft %s"):format(n.segment.name or tostring(n.segment.recipe)) }
  if n.safe < n.batch then
    t[#t + 1] = ("Queues %d: one per skill point left before %d, so it stops by %d at the latest. "
      .. "Click again after it finishes."):format(n.safe, n.segment.to, n.segment.to)
    t[#t + 1] = ("Shift-click: queue all ~%d expected crafts (may craft past %d)."):format(n.batch, n.segment.to)
  else
    t[#t + 1] = ("Queues %d, enough to reach %d."):format(n.safe, n.segment.to)
  end
  t[#t + 1] = ns.Theme.Wrap("muted", "Esc stops a running craft.")
  return t
end

function S.SetTarget(to)
  local st = S.state
  if not st.info then return end
  ns.Routes.SetTarget(ns.cdb, st.info.prof, to, st.mode or "cheapest")
  S.Refresh()
end

S.MODE_TIP = {
  cheapest = "Lowest gold cost (default).",
  fastest = "Fewest crafts, whatever the cost.",
  balanced = "Trade gold against crafts (craftValue setting).",
}

-- Choose a route mode for the open profession (persisted per profession).
function S.SetMode(mode)
  local st = S.state
  if not st.info or not S.MODE_LABEL[mode] then return end
  ns.Routes.SetTarget(ns.cdb, st.info.prof, st.target, mode)
  S.Refresh()
end

function S.OnSegmentClick(seg, button)
  local prof = S.state.info and S.state.info.prof
  if not prof then return end
  if IsShiftKeyDown and IsShiftKeyDown() then
    ns.Routes.Exclude(ns.cdb, prof, seg.recipe, true)
  elseif IsControlKeyDown and IsControlKeyDown() then
    ns.Routes.Lock(ns.cdb, prof, seg.from, seg.to, seg.recipe)
  elseif IsAltKeyDown and IsAltKeyDown() then
    ns.Routes.Unlock(ns.cdb, prof, seg.from)
  elseif button == "RightButton" then
    -- no context menu API: right-click keeps its old meaning
    ns.Routes.Exclude(ns.cdb, prof, seg.recipe, true)
  else
    S.ShowRecipe(seg.recipe)
    return
  end
  S.Refresh()
end

-- Select the recipe in Blizzard's recipe list (left-click on a route step).
function S.ShowRecipe(recipeId)
  if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then pcall(C_TradeSkillUI.OpenRecipe, recipeId) end
end

-- Right-click menu of a route step: the same actions as the modifier clicks.
function S.SegmentMenu(seg)
  return function(root)
    local prof = S.state.info and S.state.info.prof
    if not prof then return end
    local function act(fn) return function() fn(); S.Refresh() end end
    root:CreateButton("Show the recipe", function() S.ShowRecipe(seg.recipe) end)
    root:CreateButton("Never use this recipe (Shift-click)",
      act(function() ns.Routes.Exclude(ns.cdb, prof, seg.recipe, true) end))
    root:CreateButton(("Lock %d-%d to this recipe (Ctrl-click)"):format(seg.from, seg.to),
      act(function() ns.Routes.Lock(ns.cdb, prof, seg.from, seg.to, seg.recipe) end))
    root:CreateButton("Unlock this range (Alt-click)", act(function() ns.Routes.Unlock(ns.cdb, prof, seg.from) end))
    root:CreateButton("Clear all exclusions and locks", act(function() ns.cdb.overrides[prof] = nil end))
  end
end

-- View -------------------------------------------------------------------------
--
-- Hosts (same content, built by S.BuildContent):
--   column   ProfsColumn, the third column INSIDE the native ProfessionsFrame
--            (UI/Embed.lua does the layout). Default whenever the native window is up.
--            Drawn like the recipe details pane beside it: the open profession's art
--            card (cropped, not stretched) inside the same common-insideframe border.
--   panel    ProfsSidecar, a detached window (W.Window), only when another addon (e.g.
--            TradeSkillMaster) replaces the native window, so there is nothing to embed in.

local PANEL_WIDTH, PANEL_HEIGHT = 350, 560
local ROWS = 19
S.TABS = { { "route", "Route" }, { "shop", "Shopping" }, { "out", "Outputs" } }
S.HINT = "Click a step: show the recipe. Right-click: options."

-- Content laid out top-down in a host of the given inner width, starting at y = top.
-- opts.noTitle: the host has its own title (the detached window).
function S.BuildContent(f, width, opts)
  opts = opts or {}
  local W = ns.Widgets
  local top = opts.top or 0
  local function y(v) return top + v end
  if not opts.noTitle then
    f.title = W.Text(f, "large"); f.title:SetPoint("TOPLEFT", 10, y(-10)); f.title:SetText(ns.displayName)
    W.TitleIcon(f, f.title)
    f.logo:ClearAllPoints(); f.logo:SetPoint("TOPLEFT", 8, y(-8))
  end
  -- always visible, whatever the column shows: craftable gear for your level from all
  -- your professions (needs no profession window; also /profs gear)
  f.gear = W.Button(f, "Gear upgrades", 110, function() ns.GearColumn.Open() end)
  f.gear:SetPoint("TOPRIGHT", -10, y(-8))
  f.skill = W.Text(f); f.skill:SetPoint("TOPLEFT", 10, y(-34))
  f.targetLabel = W.Text(f, "small"); f.targetLabel:SetPoint("TOPLEFT", 10, y(-56)); f.targetLabel:SetText("Target")
  f.target = W.Input(f, 40, function(v) if v and v > 0 then S.SetTarget(v) end end)
  f.target:SetPoint("LEFT", f.targetLabel, "RIGHT", 8, 0)
  -- route mode: three buttons, the active one pushed in (not a cycling button whose
  -- label could be read as the current or the next mode)
  f.modeLabel = W.Text(f, "small"); f.modeLabel:SetPoint("TOPLEFT", 10, y(-84)); f.modeLabel:SetText("Mode")
  f.modes = {}
  local mw = math.floor((width - 20 - 44 - 8) / 3)
  for i, m in ipairs(S.MODES) do
    local b = W.Button(f, S.MODE_LABEL[m], mw, function() S.SetMode(m) end)
    b:SetPoint("TOPLEFT", 54 + (i - 1) * (mw + 4), y(-78))
    b.mode = m
    b:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(S.MODE_LABEL[m]); GameTooltip:AddLine(S.MODE_TIP[m], 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.modes[m] = b
  end
  f.step = W.Text(f); f.step:SetPoint("TOPLEFT", 10, y(-108)); f.step:SetWidth(width - 20)
  f.craft = W.Button(f, "Craft", 120, function() S.CraftNext() end)
  f.craft:SetScript("OnEnter", function(self)
    local n = S.state.next
    if not (n and GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local t = S.CraftTooltip(n)
    GameTooltip:SetText(t[1])
    for i = 2, #t do GameTooltip:AddLine(t[i], 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  f.craft:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.craft:SetPoint("TOPLEFT", 10, y(-140))
  -- Route / Shopping / Outputs as tabs sitting on the list
  f.tabs = {}
  local x, tabH = 10, 22
  for _, t in ipairs(S.TABS) do
    local b, h = W.Tab(f, t[2], function() S.tab = t[1]; S.Render() end)
    tabH = h
    f.tabs[t[1]] = b
    f.tabs[#f.tabs + 1] = b
    b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", x, y(-166 - h))
    x = x + (b:GetWidth() or 90) + 2
  end
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", 10, y(-170 - tabH))
  f.body:SetPoint("BOTTOMRIGHT", -10, 24)
  f.body:SetSize(width - 20, ROWS * ns.Theme.ROW_HEIGHT)
  f.list = W.List(f.body, ROWS, ns.Theme.ROW_HEIGHT, width - 20)
  f.hint = W.Text(f, "small"); f.hint:SetPoint("BOTTOMLEFT", 10, 8); f.hint:SetWidth(width - 20)
  f.hint:SetText(S.HINT)
  S.tab = S.tab or "route"
  return f
end

-- The column's background: the art card of the open profession, as Blizzard shows it
-- behind the recipe details (Professions.GetProfessionBackgroundAtlas; on forever the
-- format is "Profession-background-card-%s"). Read from the details pane itself when
-- it has one, so the two always match.
function S.ProfessionArt()
  -- computed from the open profession first: on a profession switch Blizzard may update
  -- the details pane after our refresh, so reading it could give the previous card
  if Professions and Professions.GetProfessionBackgroundAtlas and C_TradeSkillUI
      and C_TradeSkillUI.GetBaseProfessionInfo then
    local ok, atlas = pcall(function()
      return Professions.GetProfessionBackgroundAtlas(C_TradeSkillUI.GetBaseProfessionInfo())
    end)
    if ok and type(atlas) == "string" and atlas ~= "" then return atlas end
  end
  local pf = ns.Embed.Frame()
  local sf = pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
  local bg = type(sf) == "table" and sf.Background
  if type(bg) == "table" and type(bg.GetAtlas) == "function" then
    local ok, atlas = pcall(bg.GetAtlas, bg)
    if ok and type(atlas) == "string" and atlas ~= "" then return atlas end
  end
  return nil
end

-- Column background follows the open profession (called on every render: cheap when
-- the atlas is unchanged).
function S.UpdateArt(f)
  if f.host ~= "column" then return end
  local art = S.ProfessionArt()
  ns.Widgets.PaneArt(f, art)
  if f.inset then if art then f.inset:Hide() else f.inset:Show() end end
end

-- The third column (child of ProfessionsFrame once Embed.Apply runs).
function S.BuildColumn()
  if S.column then return S.column end
  local f = CreateFrame("Frame", "ProfsColumn", UIParent)
  f:Hide()
  -- grey inset until the profession art is known (and wherever it is not)
  local inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  inset:SetAllPoints(f)
  f.inset = inset
  S.BuildContent(f, ns.Embed.COLUMN_WIDTH - 10)
  f.host = "column"
  S.column = f
  return f
end

function S.BuildPanel()
  if S.panel then return S.panel end
  local W = ns.Widgets
  -- positions saved before W.Window existed
  local old = ns.db.settings.sidecarStore and ns.db.settings.sidecarStore.point
  if old then
    ns.db.settings.frames = ns.db.settings.frames or {}
    ns.db.settings.frames.ProfsSidecar = ns.db.settings.frames.ProfsSidecar or old
    ns.db.settings.sidecarStore = nil
  end
  local f = W.Window("ProfsSidecar", ns.displayName, PANEL_WIDTH, PANEL_HEIGHT, { point = { "CENTER", 300, 0 } })
  S.BuildContent(f, PANEL_WIDTH, { noTitle = true, top = f.top + 8 })
  if f.native then f.gear:ClearAllPoints(); f.gear:SetPoint("TOPRIGHT", -10, -28) end
  f.host = "panel"
  S.panel = f
  return f
end

-- Choose the host for the window that is actually showing.
function S.Attach()
  local pf = ns.Embed.Frame()
  if pf and pf:IsShown() and not S.collapsed and ns.Embed.ShowingRecipes(pf) then
    if S.panel then S.panel:Hide() end
    local f = S.BuildColumn()
    ns.Embed.Apply(f)
    S.frame, S.detached = f, false
  elseif pf and pf:IsShown() then
    -- overview page (no profession selected) or collapsed by /profs show: native
    -- layout, nothing of ours on screen
    if S.column then ns.Embed.Restore(S.column) end
    if S.panel then S.panel:Hide() end
    S.frame, S.detached = nil, false
  else
    -- native window not shown (replaced by another addon): detached window
    if S.column then ns.Embed.Restore(S.column) end
    S.frame, S.detached = S.BuildPanel(), true
  end
  return S.frame
end

-- Message-only state (no plannable route for what the window shows).
local function message(f, text)
  f.skill:SetText(""); f.step:SetText(text); f.craft:Hide(); f.list:Set({})
  f.list:SetEmptyText(nil)
  f.target:Hide(); f.targetLabel:Hide(); f.modeLabel:Hide()
  for _, b in pairs(f.modes) do b:Hide() end
  for _, b in ipairs(f.tabs) do b:Hide() end
end

local EMPTY = {
  route = "Nothing to craft: the route is empty.",
  shop = "Nothing to buy: you have every reagent.",
  out = "The route makes nothing to sell or disenchant.",
}

function S.Render()
  local f = S.frame
  if not f then return end
  local st = S.state
  local ds = st.ds
  f:Show()
  S.UpdateArt(f)
  if not st.info then
    -- column stays in the shared window, e.g. on the profession overview page
    if f.host == "panel" then f:Hide(); return end
    message(f, "Select a crafting profession tab to see its leveling route.")
    return
  end
  if not st.info.own then
    message(f, "Viewing someone else's recipes: routes are planned for your own professions.")
    return
  end
  f.skill:SetText(("%s %d / %d"):format(ns.Professions.Name(st.info.prof), st.info.skill, st.info.max))
  if st.gathering then
    message(f, ns.Professions.Name(st.info.prof)
      .. " is a gathering profession: Profs! plans crafting routes only.")
    f.skill:SetText(("%s %d / %d"):format(ns.Professions.Name(st.info.prof), st.info.skill, st.info.max))
    return
  end
  f.target:Show(); f.targetLabel:Show(); f.modeLabel:Show()
  for key, b in pairs(f.tabs) do
    if type(key) == "string" then b:Show(); ns.Widgets.SetSelected(b, key == S.tab) end
  end
  f.target:SetNumber(st.target or 0)
  for m, b in pairs(f.modes) do
    b:Show()
    ns.Widgets.SetSelected(b, m == (st.mode or "cheapest"))
  end
  if not ds then
    f.step:SetText("No recipe dataset for this client yet. See /profs status.")
    f.craft:Hide(); f.list:SetEmptyText(nil); f.list:Set({}); return
  end
  if st.done then
    f.step:SetText("Target reached.")
    f.craft:Hide(); f.list:SetEmptyText("Raise the target to plan further."); f.list:Set({}); return
  end
  local n = st.next
  if n then
    local missing = #n.missing > 0 and (" - missing " .. #n.missing .. " reagent(s)") or ""
    f.step:SetText(("Next: %s  ~%.0f crafts to %d%s"):format(n.segment.name or n.segment.recipe,
      n.remainingCrafts, n.segment.to, missing))
    f.craft:SetText(n.batch > 0 and ("Craft " .. n.safe) or "Nothing craftable")
    f.craft:Show()
  else
    f.step:SetText("No route."); f.craft:Hide()
  end
  local rows
  if S.tab == "shop" then
    rows = S.FormatShopping(ds, st.list)
  elseif S.tab == "out" then
    rows = S.FormatOutputs(ds, st.route, st.pricer, { enchanting = ns.Inventory.EnchantingSkill(),
      minSaleRate = ns.db.settings.minSaleRate })
  else
    rows = S.FormatRoute(ds, st.route, ns.Routes.Overrides(ns.cdb, st.info.prof))
    for _, row in ipairs(rows) do
      if row.segment then
        local seg = row.segment
        row.onClick = function(button) S.OnSegmentClick(seg, button) end
        row.menu = S.SegmentMenu(seg)
        row.menuTitle = seg.name or tostring(seg.recipe)
        row.tooltip = function()
          local t = { seg.name or tostring(seg.recipe),
            ("Expected crafts: %.1f (buy for %d)"):format(seg.crafts, seg.craftsCeil) }
          if ds.recipes[seg.recipe].est then
            t[#t + 1] = "Skill bands estimated: the source data lacks them for this recipe."
          end
          for _, l in ipairs(S.FormatAcquire(ds, seg.recipe, seg.acquire or { t = "known" }, ns.Game.Faction())) do
            t[#t + 1] = l
          end
          t[#t + 1] = ns.Theme.Wrap("muted", "Shift: never use. Ctrl: lock range. Alt: unlock.")
          return t
        end
      end
    end
  end
  -- the list ignores the summary row when deciding whether it is empty
  local real = 0
  for _, r in ipairs(rows) do if not r.summary then real = real + 1 end end
  f.list:SetEmptyText(EMPTY[S.tab])
  f.list:Set(real > 0 and rows or {}, S.lastTab == S.tab)
  S.lastTab = S.tab
end

function S.Refresh()
  local ok, err = pcall(S.Plan)
  if not ok then ns.Log("error", "planning failed: " .. tostring(err)) end
  S.Render()
end

-- Coalesce bursts (TRADE_SKILL_LIST_UPDATE, SKILL_LINES_CHANGED and bag updates often
-- fire several times in a row) into one refresh on the next frame.
function S.RequestRefresh()
  if not (C_Timer and C_Timer.After) then return S.Refresh() end
  if S.refreshPending then return end
  S.refreshPending = true
  C_Timer.After(0, function()
    S.refreshPending = false
    if S.frame and S.frame:IsShown() then S.Refresh() end
  end)
end

function S.OnShow()
  S.Attach()
  S.Refresh()
end

-- The native window opened, switched profession tab, or showed the overview page.
function S.OnNativeChange()
  if S.collapsed then return end
  S.OnShow()
end

local function hookNative()
  local pf = ns.Embed.Frame()
  if not pf or S.nativeHooked then return end
  S.nativeHooked = true
  -- the column is a child of the frame, so hiding the frame hides it; these hooks only
  -- (re)apply the layout and refresh content when the shared window shows
  pf:HookScript("OnShow", function() S.OnNativeChange() end)
  -- overview <-> profession: Blizzard shows the incoming page in both directions
  -- (SelectBookPage: BookPage:Show() then CraftingPage:Hide(); ShowSelectedCraftingPage:
  -- BookPage:Hide() then CraftingPage:Show()), so following each page's OnShow is enough
  for _, page in ipairs({ pf.CraftingPage, pf.BookPage }) do
    if page and page.HookScript then
      page:HookScript("OnShow", function() if pf:IsShown() then S.OnNativeChange() end end)
    end
  end
end

-- wiring ---------------------------------------------------------------------

ns.Events.On("PROFS_LOADED", function()
  S.collapsed = ns.cdb.columnCollapsed == true
  if not CreateFrame then return end
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
    "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "MAIL_INBOX_UPDATE",
    "ADDON_LOADED", "PLAYER_REGEN_ENABLED" }) do
    ev:RegisterEvent(e)
  end
  ev:SetScript("OnEvent", function(_, e, arg1)
    if e == "ADDON_LOADED" then
      if arg1 == "Blizzard_Professions" then hookNative() end
    elseif e == "PLAYER_REGEN_ENABLED" then
      ns.Embed.OnCombatEnded()
    elseif e == "TRADE_SKILL_SHOW" then
      hookNative()
      S.OnShow()
    elseif e == "TRADE_SKILL_CLOSE" then
      -- the shared window may stay open on its overview page (Blizzard keeps it open
      -- when the book page is shown); the column then shows the overview hint. The
      -- detached panel has no window to belong to and closes.
      if S.frame and S.frame.host == "panel" then S.frame:Hide()
      elseif S.frame and S.frame:IsShown() then S.RequestRefresh() end
    elseif e == "MAIL_INBOX_UPDATE" then
      ns.Inventory.ScanMail()
    elseif e == "BANKFRAME_OPENED" or e == "BAG_UPDATE_DELAYED" then
      ns.Inventory.Snapshot()
      if S.frame and S.frame:IsShown() then S.RequestRefresh() end
    elseif S.frame and S.frame:IsShown() then
      S.RequestRefresh()
    end
  end)
  S.events = ev
end)

-- Bring the route view up (minimap/compartment left-click): expands a collapsed column.
function S.Open()
  if S.collapsed then S.collapsed = false; ns.cdb.columnCollapsed = nil end
  S.OnShow()
end

-- /profs show: collapse or restore the column (or toggle the detached panel).
ns.commands.show = function()
  local pf = ns.Embed.Frame()
  if pf and pf:IsShown() then
    S.collapsed = not S.collapsed
    ns.cdb.columnCollapsed = S.collapsed or nil
    S.OnShow()
    ns.Log("info", S.collapsed and "Profs! column hidden (/profs show to bring it back)" or "Profs! column shown")
  elseif S.frame and S.frame:IsShown() then
    S.frame:Hide()
  else
    S.OnShow()
  end
end

ns.commands.save = function(name)
  local st = S.state
  if not st.info or name == "" then ns.Log("warn", "open a profession and give a name: /profs save <name>"); return end
  local o = ns.Routes.Overrides(ns.cdb, st.info.prof)
  ns.Routes.Save(ns.db, name, { prof = st.info.prof, to = st.target, mode = st.mode,
    exclude = o.exclude, locks = o.locks })
  ns.Log("info", "saved route '" .. name .. "'")
end

ns.commands.load = function(name)
  local spec = ns.Routes.Load(ns.db, name)
  if not spec then ns.Log("warn", "no saved route '" .. tostring(name) .. "'. Saved: "
    .. table.concat(ns.Routes.List(ns.db), ", ")); return end
  ns.Routes.SetTarget(ns.cdb, spec.prof, spec.to, spec.mode)
  local o = ns.Routes.Overrides(ns.cdb, spec.prof)
  o.exclude, o.locks = spec.exclude or {}, spec.locks or {}
  ns.Log("info", "loaded route '" .. name .. "'")
  S.Refresh()
end

ns.commands.reset = function()
  local st = S.state
  if not st.info then return end
  ns.cdb.overrides[st.info.prof] = nil
  ns.Log("info", "overrides cleared")
  S.Refresh()
end
