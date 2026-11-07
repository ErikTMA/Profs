-- The sidecar: a panel attached to the right of the native ProfessionsFrame (or a
-- detached, movable panel when another addon such as TradeSkillMaster replaces the
-- native window). Shows the route to the persistent target, the next guided step
-- with a Craft button, the consolidated shopping list and output recommendations.
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

-- Acquisition instructions for one recipe source.
function S.FormatAcquire(ds, recipeId, how)
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
  elseif how.t == "reputation" then
    lines[#lines + 1] = ("Reputation vendor (standing %s), %s."):format(tostring(src.standing),
      U.money(src.cost))
  elseif how.t == "locked" then
    lines[#lines + 1] = "You locked this recipe; source not in your allowed list."
  else
    lines[#lines + 1] = ("Source: %s%s."):format(how.t, src.item and (" (" .. itemName(ds, src.item) .. ")") or "")
  end
  for i, npc in ipairs(src.npcs or {}) do
    if i > 3 then break end
    lines[#lines + 1] = "  " .. npcText(ds, npc)
  end
  return lines
end

-- Route rows: one per segment plus training steps, in skill order.
function S.FormatRoute(ds, route, overrides)
  local rows = {}
  local locks = overrides and overrides.locks or {}
  local function lockedAt(seg)
    for _, l in ipairs(locks) do
      if l.recipe == seg.recipe and l.from <= seg.from and l.to >= seg.to then return true end
    end
    return false
  end
  local training = {}
  for _, t in ipairs(route.training or {}) do training[#training + 1] = t end
  local ti = 1
  for _, seg in ipairs(route.segments) do
    while training[ti] and training[ti].by <= seg.from do
      local t = training[ti]
      rows[#rows + 1] = { kind = "train", text = color("80c0ff", ("Train %s by %d (%s)"):format(
        t.rank, t.by, U.money(t.cost))), step = t }
      ti = ti + 1
    end
    local c = (ns.Widgets and ns.Widgets.COLORS[seg.colorAtStart]) or "ffffff"
    local est = ds.recipes[seg.recipe] and ds.recipes[seg.recipe].est
    local text = ("%3d-%3d %s x%s%d  %s%s%s"):format(seg.from, seg.to,
      color(c, seg.name or tostring(seg.recipe)), est and "~" or "", seg.craftsCeil, U.money(seg.gold),
      seg.acquire and color("c0c0c0", "  [learn]") or "", lockedAt(seg) and color("ff6060", " [locked]") or "")
    rows[#rows + 1] = { kind = "segment", text = text, segment = seg }
  end
  while training[ti] do
    local t = training[ti]
    rows[#rows + 1] = { kind = "train", text = color("80c0ff", ("Train %s by %d (%s)"):format(
      t.rank, t.by, U.money(t.cost))), step = t }
    ti = ti + 1
  end
  for _, w in ipairs(route.warnings or {}) do
    rows[#rows + 1] = { kind = "warning", text = color("ff4040", w) }
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
    local status = l.done and color("40ff40", "done") or ("buy " .. l.buy)
    rows[#rows + 1] = { item = l.itemId, text = ("%s  %d/%d  %s  %s%s"):format(itemName(ds, l.itemId),
      l.owned, l.need, status, l.unit and (U.money(l.unit) .. " ea "
        .. color("a0a0a0", "(" .. S.PriceLabel(l) .. ")")) or color("ff4040", "no price"),
      #have > 0 and ("  (" .. table.concat(have, ", ") .. ")") or "") }
  end
  rows[#rows + 1] = { text = ("Total to spend: %s"):format(U.money(list.total)) }
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
      local parts = { ("vendor %s"):format(U.money(v.vendor)) }
      if v.ah then
        parts[#parts + 1] = ("AH ~%s%s"):format(U.money(v.ah),
          v.saleRate and (" @%d%%"):format(math.floor(v.saleRate * 100 + 0.5)) or "")
      end
      if v.deValue then
        parts[#parts + 1] = ("DE ~%s%s"):format(U.money(v.deValue), v.deEstimated and " (est.)" or "")
      end
      rows[#rows + 1] = { item = out, action = v.action, text = ("%s: %s  [%s]"):format(
        itemName(ds, out), color("ffd100", v.action), table.concat(parts, ", ")) }
    end
  end
  if #rows > 0 then
    rows[#rows + 1] = { text = color("a0a0a0", "AH and DE values are speculative; Cheapest counts vendor value only.") }
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
  }
end

-- Recompute the route for the open profession. Returns the state or nil.
function S.Plan()
  local info = ns.Game.OpenProfession()
  local ds = ns.ActiveDataset()
  local st = S.state
  st.info, st.ds = info, ds
  if not info or not info.own or not ds then st.route = nil; return st end
  local prof = info.prof
  -- remember learned recipes for this profession
  ns.cdb.known = ns.cdb.known or {}
  local known = ns.cdb.known[prof] or {}
  for id, r in pairs(ns.Game.ScanRecipes()) do
    if r.learned then known[id] = true end
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
  st.route = ns.Optimizer.Plan(ds, prof, info.skill, target, opts)
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
  st.next = ns.Routes.Next(ds, st.route, info.skill, function(id) return ns.Game.ItemCount(id, false) end)
  return st
end

function S.CraftNext()
  local n = S.state.next
  if not n or n.batch <= 0 then return false end
  return ns.Game.Craft(n.segment.recipe, n.batch)
end

function S.SetTarget(to)
  local st = S.state
  if not st.info then return end
  ns.Routes.SetTarget(ns.cdb, st.info.prof, to, st.mode or "cheapest")
  S.Refresh()
end

function S.CycleMode()
  local st = S.state
  if not st.info then return end
  local cur = st.mode or "cheapest"
  local nextMode = S.MODES[1]
  for i, m in ipairs(S.MODES) do if m == cur then nextMode = S.MODES[i % #S.MODES + 1] end end
  ns.Routes.SetTarget(ns.cdb, st.info.prof, st.target, nextMode)
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
    ns.Routes.Exclude(ns.cdb, prof, seg.recipe, true)
  else
    return
  end
  S.Refresh()
end

-- View -------------------------------------------------------------------------

local WIDTH, HEIGHT, ROWS = 340, 520, 22

function S.Build()
  if S.frame then return S.frame end
  local W = ns.Widgets
  local f = W.Panel("ProfsSidecar", UIParent, WIDTH, HEIGHT)
  f:Hide()
  f.title = W.Text(f, "large"); f.title:SetPoint("TOPLEFT", 10, -10); f.title:SetText(ns.displayName)
  W.TitleIcon(f, f.title)
  f.skill = W.Text(f); f.skill:SetPoint("TOPLEFT", 10, -32)
  f.targetLabel = W.Text(f, "small"); f.targetLabel:SetPoint("TOPLEFT", 10, -54); f.targetLabel:SetText("Target")
  f.target = W.Input(f, 40, function(v) if v and v > 0 then S.SetTarget(v) end end)
  f.target:SetPoint("LEFT", f.targetLabel, "RIGHT", 8, 0)
  f.mode = W.Button(f, "Cheapest", 90, function() S.CycleMode() end)
  f.mode:SetPoint("LEFT", f.target, "RIGHT", 8, 0)
  f.close = W.Button(f, "x", 22, function() f:Hide() end)
  f.close:SetPoint("TOPRIGHT", -6, -6)

  f.step = W.Text(f); f.step:SetPoint("TOPLEFT", 10, -80); f.step:SetWidth(WIDTH - 20)
  f.craft = W.Button(f, "Craft", 120, function() S.CraftNext() end)
  f.craft:SetPoint("TOPLEFT", 10, -118)

  f.tabs = {}
  local x = 10
  for _, t in ipairs({ { "route", "Route" }, { "shop", "Shopping" }, { "out", "Outputs" } }) do
    local b = W.Button(f, t[2], 90, function() S.tab = t[1]; S.Render() end)
    b:SetPoint("TOPLEFT", x, -146)
    x = x + 96
    f.tabs[t[1]] = b
  end
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", 10, -172)
  f.body:SetSize(WIDTH - 20, ROWS * 15)
  f.list = W.List(f.body, ROWS, 15, WIDTH - 20)
  for i, row in ipairs(f.list.rows) do row:SetPoint("TOPLEFT", 0, -(i - 1) * 15) end
  f.hint = W.Text(f, "small"); f.hint:SetPoint("BOTTOMLEFT", 10, 8); f.hint:SetWidth(WIDTH - 20)
  f.hint:SetText("Shift/right-click: exclude. Ctrl-click: lock range. Alt-click: unlock.")
  S.frame = f
  S.tab = "route"
  return f
end

function S.Attach()
  local f = S.Build()
  f:ClearAllPoints()
  local pf = _G.ProfessionsFrame
  if pf and pf.IsShown and pf:IsShown() then
    f:SetPoint("TOPLEFT", pf, "TOPRIGHT", 2, 0)
    S.detached = false
  else
    -- native window not shown (e.g. replaced by TradeSkillMaster): detached panel
    local store = ns.db.settings.sidecarStore or {}
    ns.db.settings.sidecarStore = store
    local p = store.point
    if p then f:SetPoint(p[1], UIParent, p[2] or p[1], p[3], p[4]) else f:SetPoint("CENTER", 300, 0) end
    S.detached = true
    if not S.movable then ns.Widgets.Movable(f, store); S.movable = true end
  end
end

function S.Render()
  local f = S.frame
  if not f then return end
  local st = S.state
  local ds = st.ds
  if not st.info or not st.info.own then f:Hide(); return end
  f:Show()
  f.skill:SetText(("%s %d / %d"):format(ns.Professions.Name(st.info.prof), st.info.skill, st.info.max))
  f.target:SetNumber(st.target or 0)
  f.mode:SetText(S.MODE_LABEL[st.mode or "cheapest"])
  if not ds then
    f.step:SetText("No recipe dataset for this client yet. See /profs status.")
    f.craft:Hide(); f.list:Set({}); return
  end
  if st.done then
    f.step:SetText("Target reached.")
    f.craft:Hide(); f.list:Set({}); return
  end
  local n = st.next
  if n then
    local missing = #n.missing > 0 and (" - missing " .. #n.missing .. " reagent(s)") or ""
    f.step:SetText(("Next: %s  ~%.0f crafts to %d%s"):format(n.segment.name or n.segment.recipe,
      n.remainingCrafts, n.segment.to, missing))
    f.craft:SetText(n.batch > 0 and ("Craft " .. n.batch) or "Nothing craftable")
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
        row.tooltip = function()
          local t = { seg.name or tostring(seg.recipe),
            ("Expected crafts: %.1f (buy for %d)"):format(seg.crafts, seg.craftsCeil) }
          if ds.recipes[seg.recipe].est then
            t[#t + 1] = "Skill bands estimated: the source data lacks them for this recipe."
          end
          for _, l in ipairs(S.FormatAcquire(ds, seg.recipe, seg.acquire or { t = "known" })) do t[#t + 1] = l end
          return t
        end
      end
    end
  end
  f.list:Set(rows)
end

function S.Refresh()
  local ok, err = pcall(S.Plan)
  if not ok then ns.Log("error", "planning failed: " .. tostring(err)) end
  S.Render()
end

function S.OnShow()
  S.Attach()
  S.Refresh()
end

-- wiring ---------------------------------------------------------------------

ns.Events.On("PROFS_LOADED", function()
  if not CreateFrame then return end
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
    "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "MAIL_INBOX_UPDATE" }) do
    ev:RegisterEvent(e)
  end
  ev:SetScript("OnEvent", function(_, e)
    if e == "TRADE_SKILL_SHOW" then
      S.OnShow()
    elseif e == "TRADE_SKILL_CLOSE" then
      if S.frame then S.frame:Hide() end
    elseif e == "MAIL_INBOX_UPDATE" then
      ns.Inventory.ScanMail()
    elseif e == "BANKFRAME_OPENED" or e == "BAG_UPDATE_DELAYED" then
      ns.Inventory.Snapshot()
      if S.frame and S.frame:IsShown() then S.Refresh() end
    elseif S.frame and S.frame:IsShown() then
      S.Refresh()
    end
  end)
  S.events = ev
end)

ns.commands.show = function()
  if S.frame and S.frame:IsShown() then S.frame:Hide() else S.OnShow() end
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
