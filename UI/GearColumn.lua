-- Craftable gear upgrades as a column INSIDE the native character frame.
--
-- Forever 1.60.x (Gethe/wow-ui-source, branch forever; Camelot/CharacterFrame.xml/.lua):
--   CharacterFrame holds LeftPaneHost (paper doll, 398 wide) anchored TOPLEFT and
--   RightPaneHost (stats, 233 wide) anchored to its right; both are LEFT-anchored with
--   fixed widths. CharacterFrameMixin:UpdateSize() sets the frame to 631 (398 when the
--   stats pane is collapsed) on every RefreshDisplay, i.e. every tab change. The
--   vertical mode tabs (CharacterFrameModeTabs) are anchored TOPLEFT -> the frame's
--   TOPRIGHT, outside its right edge. The UI panel width is GetWidth() + 82
--   (CharacterFrameMixin:SetUIPanelAttribute).
--
-- Layout: on the Character tab (PaperDollFrame shown) and only when there ARE craftable
-- upgrades, the frame is widened by COLUMN_WIDTH; the column fills the new space right
-- of the panes, inside the border; the close button and the mode tabs follow the
-- frame's right edge, so nothing is covered. A hook on SetSize/SetWidth re-adds the
-- column after Blizzard's UpdateSize. Other tabs, or no upgrades: native layout.
local _, ns = ...
local GC = ns:NewModule("GearColumn")

GC.COLUMN_WIDTH = 300
GC.PANEL_PADDING = 82      -- CHARACTER_FRAME_WIDTH_PADDING in Camelot/CharacterFrame.lua
GC.ROWS = 24

function GC.Frame()
  local cf = _G.CharacterFrame
  if type(cf) == "table" and cf.GetWidth then return cf end
  return nil
end

local function onCharacterTab()
  local pd = _G.PaperDollFrame
  return pd and pd.IsShown and pd:IsShown() or false
end

local function panelLayout(cf, width)
  if InCombatLockdown and InCombatLockdown() then GC.pendingPanel = true; return end
  GC.pendingPanel = nil
  if SetUIPanelAttribute and UpdateUIPanelPositions then
    pcall(SetUIPanelAttribute, cf, "width", width + GC.PANEL_PADDING)
    pcall(UpdateUIPanelPositions, cf)
  end
end

local function setWidth(cf, width)
  GC.setting = true
  cf:SetWidth(width)
  GC.setting = false
  panelLayout(cf, width)
end

local function hookSize(cf)
  if GC.sizeHooked or not hooksecurefunc then return end
  GC.sizeHooked = true
  local function after(self, w)
    if GC.setting or not GC.active or type(w) ~= "number" then return end
    GC.nativeWidth = w
    setWidth(self, w + GC.COLUMN_WIDTH)
  end
  hooksecurefunc(cf, "SetSize", after)
  hooksecurefunc(cf, "SetWidth", after)
end

GC.ART = "UI-Character-Info-Stat-BG"   -- the stats pane's own background (Camelot CharacterFrame.xml)
GC.HINT = "Click: open the recipe. Shift-click: link. Hover: where to get it."

function GC.Build(cf)
  if GC.column then return GC.column end
  local W = ns.Widgets
  local f = CreateFrame("Frame", "ProfsGearColumn", cf)
  f:Hide()
  local inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  inset:SetAllPoints(f)
  f.inset = inset
  -- drawn like the stats pane beside it; the grey inset stays where the art is missing
  if W.PaneArt(f, C_Texture and C_Texture.GetAtlasInfo and GC.ART or nil, 0.15) then inset:Hide() end
  f.title = W.Text(f, "large"); f.title:SetPoint("TOPLEFT", 10, -10); f.title:SetText("Craftable upgrades")
  W.TitleIcon(f, f.title)
  f.scored = W.Text(f, "small"); f.scored:SetPoint("TOPLEFT", 10, -36)
  f.scored:SetWidth(GC.COLUMN_WIDTH - 30); f.scored:SetWordWrap(false)
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", 10, -54)
  f.body:SetPoint("BOTTOMRIGHT", -10, 26)
  f.body:SetSize(GC.COLUMN_WIDTH - 30, GC.ROWS * ns.Theme.ROW_HEIGHT)
  f.list = W.List(f.body, GC.ROWS, ns.Theme.ROW_HEIGHT, GC.COLUMN_WIDTH - 30)
  f.hint = W.Text(f, "small"); f.hint:SetPoint("BOTTOMLEFT", 10, 8); f.hint:SetWidth(GC.COLUMN_WIDTH - 30)
  f.hint:SetText(GC.HINT)
  GC.column = f
  return f
end

-- Rows for the list, grouped by slot (Gear.BySlot: a heading per slot, biggest
-- upgrade first, the slot with the biggest upgrade on top). One row per upgrade: item
-- icon, name, required level, gain on the right; the recipe's tooltip plus where to get
-- it; click opens the recipe.
function GC.Rows(ds, upgrades)
  local T = ns.Theme
  local rows = {}
  for _, g in ipairs(ns.Gear.BySlot(upgrades)) do
   rows[#rows + 1] = { header = true, summary = true, text = T.Wrap("gold", g.name),
     right = T.Wrap("muted", #g.items == 1 and "1 upgrade" or (#g.items .. " upgrades")) }
   for _, c in ipairs(g.items) do
    local r = ds.recipes[c.recipe]
    rows[#rows + 1] = {
      indent = 8,
      item = c.itemId,
      -- tooltip and Shift-click: the recipe itself, as a linked recipe shows it
      recipe = c.recipe, recipeProf = ns.Professions.Name(c.prof), recipeName = r and r.name,
      linkRecipe = true,
      text = ("%s %s%s%s"):format(ns.Sidecar.ItemName(ds, c.itemId), T.Wrap("muted", "req " .. c.reqLevel),
        c.usableNow and "" or ("  " .. T.Wrap("muted", "soon")),
        c.how and c.how.t == "drop" and ("  " .. T.Wrap("drop", "drop")) or ""),
      right = c.pct and ("+%.0f%%"):format(c.gain) or ("+%.1f"):format(c.gain),
      upgrade = c,
      onClick = function() ns.GearToast.OpenRecipe(c) end,
      tooltip = function()
        local t = { ns.Sidecar.ItemName(ds, c.itemId), ("Crafted with %s; requires level %d"):format(
          ns.Professions.Name(c.prof), c.reqLevel), c.pct and ("Pawn: %.0f%% better than what you wear"):format(c.gain)
          or ("Upgrade score +%.1f"):format(c.gain) }
        if not c.usableNow then t[#t + 1] = "Not equippable yet." end
        -- how to get the recipe: trainer/vendor/currency, or which mobs drop the pattern
        if c.how and c.how.t ~= "known" then
          local how = ns.Sidecar.FormatAcquire(ds, c.recipe, c.how, ns.Game.Faction and ns.Game.Faction())
          for j = 2, #how do t[#t + 1] = how[j] end
        end
        t[#t + 1] = T.Wrap("muted", "Click: open the recipe.")
        return t
      end,
    }
   end
  end
  return rows
end

-- Recompute the upgrades. Returns the list (possibly empty) and whether Pawn scored it.
function GC.Compute()
  local ds = ns.ActiveDataset()
  if not ds then return {}, false, nil end
  local ups, pawn = ns.GearFrame.Compute(ds)
  return ups or {}, pawn, ds
end

local function apply(cf, f)
  hookSize(cf)
  if not GC.active then
    GC.nativeWidth = cf:GetWidth()
    GC.active = true
  end
  if math.abs((cf:GetWidth() or 0) - (GC.nativeWidth + GC.COLUMN_WIDTH)) > 0.5 then
    setWidth(cf, GC.nativeWidth + GC.COLUMN_WIDTH)
  end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", cf, "TOPRIGHT", -GC.COLUMN_WIDTH + 2, -24)
  f:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -8, 8)
  f:Show()
end

function GC.Restore()
  local cf = GC.Frame()
  if GC.column then GC.column:Hide() end
  if not cf or not GC.active then return end
  GC.active = false
  setWidth(cf, GC.nativeWidth)
end

-- Turned off in the options (ProfsDB.settings.gearColumn = false).
function GC.Disabled()
  return ns.db and ns.db.settings and ns.db.settings.gearColumn == false
end

-- Show the column when the Character tab is up and there are upgrades; otherwise the
-- native layout. Returns the number of upgrades shown.
function GC.Update()
  local cf = GC.Frame()
  if not cf or not cf:IsShown() or not onCharacterTab() or GC.Disabled() then GC.Restore(); return 0 end
  local ups, pawn, ds = GC.Compute()
  GC.last = ups
  if #ups == 0 then GC.Restore(); return 0 end
  local f = GC.Build(cf)
  f.scored:SetText(ns.Theme.Wrap("gold", type(pawn) == "table" and pawn.label
    or (pawn and "Scored by Pawn" or "Built-in automatic weights")))
  f.list:Set(GC.Rows(ds, ups))
  apply(cf, f)
  return #ups
end

function GC.RequestUpdate()
  if not (C_Timer and C_Timer.After) then return GC.Update() end
  if GC.pending then return end
  GC.pending = true
  C_Timer.After(0, function() GC.pending = false; GC.Update() end)
end

-- /profs gear, the Gear upgrades button and the compartment: open the character frame
-- on the Character tab; say so in chat when there is nothing to show.
function GC.Open()
  local cf = GC.Frame()
  if cf and ToggleCharacter then
    if not (cf:IsShown() and onCharacterTab()) then ToggleCharacter("PaperDollFrame", true) end
    local n = GC.Update()
    if n == 0 then ns.Log("info", "No craftable upgrades right now.") end
    return n
  end
  ns.GearFrame.Show()        -- no native character frame: the stand-alone list
  return nil
end

local function hookNative()
  local cf = GC.Frame()
  if not cf or GC.nativeHooked then return end
  GC.nativeHooked = true
  cf:HookScript("OnShow", GC.RequestUpdate)
  local pd = _G.PaperDollFrame
  if pd and pd.HookScript then
    -- tab changes: Blizzard's ShowSubFrame hides/shows the subframes
    pd:HookScript("OnShow", GC.RequestUpdate)
    pd:HookScript("OnHide", function() GC.Restore() end)
  end
end

ns.Events.On("PROFS_LOADED", function()
  if not CreateFrame then return end
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
    "SKILL_LINES_CHANGED", "PLAYER_REGEN_ENABLED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE" }) do
    ev:RegisterEvent(e)
  end
  ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_LOGIN" or e == "ADDON_LOADED" then
      hookNative()
    elseif e == "PLAYER_REGEN_ENABLED" then
      local cf = GC.Frame()
      if GC.pendingPanel and cf then panelLayout(cf, cf:GetWidth()) end
    else
      local cf = GC.Frame()
      if cf and cf:IsShown() then GC.RequestUpdate() end
    end
  end)
  GC.events = ev
  hookNative()
end)

ns.commands.gear = GC.Open
