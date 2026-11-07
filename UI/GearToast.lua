-- Level-up notification: a small native-styled panel near the top of the screen
-- listing craftable upgrades that just became equippable (Engine/GearAlert.lua).
--   left-click a row   open the profession and select the recipe
--   hover a row        item tooltip + materials and cost
--   x / right-click    dismiss (the items are not announced again)
-- Settings: /profs alerts on|off|pct <n>|test. Shown only out of combat.
--
-- Events (forever docs): PLAYER_LEVEL_UP(level, ...) — UnitLevel can lag the event,
-- so the event's level is used; PLAYER_ENTERING_WORLD covers login and /reload (a
-- level gained but not yet evaluated, e.g. reload right after dinging, is caught by
-- the stored last-evaluated level); PLAYER_REGEN_ENABLED flushes a deferred alert.
local _, ns = ...
local T = ns:NewModule("GearToast")
local U = ns.Util

T.DELAY = 3          -- seconds after the level-up before evaluating (item data, UI settle)
T.SHOW_SECONDS = 30  -- auto-hide unless hovered

local function settings()
  ns.db.settings.gearAlerts = ns.db.settings.gearAlerts or {}
  return ns.db.settings.gearAlerts
end

local function charState()
  ns.cdb.gearAlert = ns.cdb.gearAlert or { seen = {} }
  ns.cdb.gearAlert.seen = ns.cdb.gearAlert.seen or {}
  return ns.cdb.gearAlert
end

-- Equipped items by inventory slot: { score?, stats, name }
function T.Equipped()
  local out, totals = {}, {}
  if not GetInventoryItemLink then return out, totals end
  local fn = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
  for inv = 1, 18 do
    local link = GetInventoryItemLink("player", inv)
    if link then
      local stats
      if fn then local ok, st = pcall(fn, link); if ok then stats = st end end
      local name = (C_Item and C_Item.GetItemInfo) and C_Item.GetItemInfo(link) or nil
      -- stats unreadable (item data not cached): unknown, never compared as empty
      out[inv] = { stats = stats or {}, name = name, unknown = stats == nil }
      for k, v in pairs(stats or {}) do totals[k] = (totals[k] or 0) + v end
    else
      out[inv] = { score = 0, stats = {} }
    end
  end
  return out, totals
end

function T.Context(level, prevLevel)
  local ds = ns.ActiveDataset()
  local me = ns.Game.PlayerInfo()
  local profs = {}
  for line, p in pairs(ns.Game.Professions()) do profs[line] = p.rank end
  local known = {}
  for _, set in pairs(ns.cdb.known or {}) do for id in pairs(set) do known[id] = true end end
  local equipped, totals = T.Equipped()
  return ds, {
    level = level, prevLevel = prevLevel, class = me.class, profs = profs, known = known,
    equipped = equipped, equippedTotals = totals, stats = ns.Game.ItemStats,
    scorer = ns.Pawn.Scorer(), pricer = ns.PriceSources.Pricer(ds),
    have = function(id) local h = ns.Inventory.Have(id); return (h.bags or 0) + (h.bank or 0) end,
    seen = charState().seen, settings = settings(),
  }
end

-- Pure: one row's text and tooltip lines.
function T.FormatAlert(ds, a)
  local name = ns.Sidecar.ItemName(ds, a.itemId)
  local gain = a.scoredBy == "Pawn" and ("+%.0f%% (Pawn)"):format(a.pct)
    or (a.pct == math.huge and "empty slot" or ("+%.0f%%"):format(a.pct))
  local text = ("%s  |cffa0a0a0%s|r  %s%s"):format(name, ns.Professions.Name(a.prof), gain,
    a.reason and a.reason ~= "" and ("  " .. a.reason) or "")
  local tip = { name, ("Requires level %d - %s"):format(a.reqLevel, ns.Professions.Name(a.prof)) }
  if a.replaces then tip[#tip + 1] = "Replaces: " .. a.replaces end
  if a.reason and a.reason ~= "" then tip[#tip + 1] = "Better: " .. a.reason end
  tip[#tip + 1] = ("Materials (%s to buy%s):"):format(U.money(a.cost), a.unpriced and ", some unpriced" or "")
  for _, m in ipairs(a.materials) do
    tip[#tip + 1] = ("  %s  %d/%d%s"):format(ns.Sidecar.ItemName(ds, m.itemId), math.min(m.have, m.need), m.need,
      m.unit and ("  " .. U.money(m.unit) .. " ea") or "")
  end
  if a.acquire and a.acquire.t ~= "known" then
    for _, l in ipairs(ns.Sidecar.FormatAcquire(ds, a.recipe, a.acquire)) do tip[#tip + 1] = l end
  end
  tip[#tip + 1] = "|cff80c0ffClick: open the recipe. Right-click: dismiss.|r"
  return text, tip
end

function T.OpenRecipe(a)
  if not C_TradeSkillUI then return false end
  local info = ns.Game.OpenProfession()
  local function select()
    if C_TradeSkillUI.OpenRecipe then pcall(C_TradeSkillUI.OpenRecipe, a.recipe) end
  end
  if info and info.prof == a.prof then select(); return true end
  if C_TradeSkillUI.OpenTradeSkill then
    local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, a.prof)
    if ok and opened ~= false then
      if C_Timer and C_Timer.After then C_Timer.After(0.5, select) else select() end
      return true
    end
  end
  return false
end

function T.Build()
  if T.frame then return T.frame end
  local W = ns.Widgets
  local f = W.Panel("ProfsGearToast", UIParent, 460, 40)
  f:SetPoint("TOP", 0, -140)
  f:Hide()
  f.title = W.Text(f); f.title:SetPoint("TOPLEFT", 10, -9)
  W.TitleIcon(f, f.title, 16)
  f.close = W.Button(f, "x", 20, function() T.Dismiss() end); f.close:SetPoint("TOPRIGHT", -5, -5)
  f.rows = {}
  for i = 1, ns.GearAlert.DEFAULTS.maxPerLevel + 2 do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(440, 16)
    b:SetPoint("TOPLEFT", 10, -10 - i * 17)
    b:RegisterForClicks("AnyUp")
    b.text = W.Text(b, "small"); b.text:SetAllPoints()
    b:SetScript("OnClick", function(self, button)
      if button == "RightButton" then T.Dismiss() elseif self.alert then T.OpenRecipe(self.alert) end
    end)
    b:SetScript("OnEnter", function(self)
      f.hovered = true
      if not self.tip or not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.alert.itemId) else GameTooltip:SetText(self.tip[1]) end
      for j = 2, #self.tip do GameTooltip:AddLine(self.tip[j], 1, 1, 1, true) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() f.hovered = false; if GameTooltip then GameTooltip:Hide() end end)
    f.rows[i] = b
  end
  T.frame = f
  return f
end

function T.Dismiss() if T.frame then T.frame:Hide() end end

function T.Show(ds, alerts, level, preview)
  local f = T.Build()
  f.title:SetText(("|cffd4a017Profs!|r %s at level %d"):format(
    #alerts == 1 and "a craftable upgrade" or (#alerts .. " craftable upgrades"), level)
    .. (preview and "  |cffa0a0a0(preview)|r" or ""))
  for i, b in ipairs(f.rows) do
    local a = alerts[i]
    if a then
      b.alert = a
      b.text:SetText((T.FormatAlert(ds, a)))
      b.tip = select(2, T.FormatAlert(ds, a))
      b:Show()
    else
      b.alert, b.tip = nil, nil; b:Hide()
    end
  end
  f:SetHeight(18 + (#alerts + 1) * 17)
  f:Show()
  local token = {}
  f.token = token
  if C_Timer and C_Timer.After then
    local function autohide()
      if f.token ~= token then return end
      if f.hovered then C_Timer.After(5, autohide) else f:Hide() end
    end
    C_Timer.After(T.SHOW_SECONDS, autohide)
  end
end

-- Evaluate (prevLevel, level] and show. Marks shown items as seen unless preview.
function T.Run(level, prevLevel, preview)
  local s = settings()
  if s.enabled == false and not preview then return {} end
  local ds, ctx = T.Context(level, prevLevel)
  if not ds then return {} end
  if preview then ctx.seen = {} end
  local alerts = ns.GearAlert.Evaluate(ds, ctx)
  if #alerts > 0 then
    if not preview then
      for _, a in ipairs(alerts) do charState().seen[a.itemId] = level end
    end
    T.Show(ds, alerts, level, preview)
  end
  return alerts
end

-- Called for a level change; defers out of combat. Records the evaluated level so a
-- /reload neither repeats nor loses an alert.
function T.OnLevel(level)
  local st = charState()
  local prev = st.level or (level - 1)
  if level <= prev then st.level = level; return end
  if InCombatLockdown and InCombatLockdown() then T.pending = level; return end
  T.pending = nil
  local ok, err = pcall(T.Run, level, prev)
  if not ok then ns.Log("error", "gear alert failed: " .. tostring(err)) end
  st.level = level
end

function T.OnEnteringWorld()
  local st = charState()
  local level = UnitLevel and UnitLevel("player") or 1
  if st.level == nil then st.level = level; return end   -- first run: no backlog
  if level > st.level then T.OnLevel(level) end
end

ns.Events.On("PROFS_LOADED", function()
  if not CreateFrame then return end
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_LEVEL_UP")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LEVEL_UP" then
      local level = tonumber(arg1)
      if not level then return end
      if C_Timer and C_Timer.After then C_Timer.After(T.DELAY, function() T.OnLevel(level) end)
      else T.OnLevel(level) end
    elseif event == "PLAYER_ENTERING_WORLD" then
      if C_Timer and C_Timer.After then C_Timer.After(T.DELAY + 2, T.OnEnteringWorld) else T.OnEnteringWorld() end
    elseif event == "PLAYER_REGEN_ENABLED" and T.pending then
      T.OnLevel(T.pending)
    end
  end)
  T.events = f
end)

ns.commands.alerts = function(rest)
  local s = settings()
  local cmd, arg = (rest or ""):match("^(%S*)%s*(%S*)")
  if cmd == "off" then s.enabled = false
  elseif cmd == "on" then s.enabled = true
  elseif cmd == "pct" and tonumber(arg) then s.minPct = tonumber(arg)
  elseif cmd == "reset" then charState().seen = {}
  elseif cmd == "test" then
    local level = UnitLevel and UnitLevel("player") or 1
    local alerts = T.Run(level, 0, true)
    if #alerts == 0 then ns.Log("info", "no craftable upgrade for your level right now") end
    return
  end
  ns.Log("info", ("gear alerts %s, threshold %d%% (/profs alerts on|off|pct <n>|test|reset)"):format(
    s.enabled == false and "off" or "on", s.minPct or ns.GearAlert.DEFAULTS.minPct))
end
