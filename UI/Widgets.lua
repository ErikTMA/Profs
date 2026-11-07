-- Frame helpers on stock templates. Every newer template or API is feature detected,
-- with a plain fallback, so the addon still loads if Forever changes one of them:
--   W.Window   standalone window: PortraitFrameTemplate (logo as portrait, native close
--              button), Esc closes it, clamped to the screen, position remembered.
--   W.List     WowScrollBoxList + MinimalScrollBar + DataProvider; rows with an item icon,
--              a left text, a right-aligned value and alternate-row shading. Falls back to
--              fixed rows paged by the mouse wheel.
--   W.Tab      MinimalTabTemplate (the Settings tabs), else a plain button.
local _, ns = ...
local W = ns:NewModule("Widgets")
local Theme = ns.Theme

W.COLORS = Theme.SKILL

local function hasTemplate(name)
  if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo) then return false end
  local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
  return ok and info ~= nil
end
W.HasTemplate = hasTemplate

function W.Panel(name, parent, w, h)
  local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
  f:SetSize(w, h)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
  end
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  return f
end

-- Logo left of a window title (falls back to a stock icon until the logo exists).
function W.TitleIcon(f, title, size)
  local t = f:CreateTexture(nil, "ARTWORK")
  t:SetSize(size or 20, size or 20)
  t:SetPoint("TOPLEFT", 8, -8)
  ns.Media.Apply(t, (size or 20) > 64 and "LOGO" or "ICON")
  if title then
    title:ClearAllPoints()
    title:SetPoint("LEFT", t, "RIGHT", 6, 0)
  end
  f.logo = t
  return t
end

-- Saved window positions (ns.db.settings.frames[name] = { point, relPoint, x, y }).
local function frameStore(name)
  if not (ns.db and ns.db.settings) then return nil end
  ns.db.settings.frames = ns.db.settings.frames or {}
  return name and ns.db.settings.frames[name]
end

-- Pure: is a rectangle (left, bottom, width, height) at least `margin` px inside a
-- screen of sw x sh? Used to drop saved positions that ended up off screen (resolution
-- or UI scale changed since).
function W.OnScreen(left, bottom, width, height, sw, sh, margin)
  if not (left and bottom and width and height and sw and sh) then return true end
  margin = margin or 24
  return left + width >= margin and left <= sw - margin
    and bottom + height >= margin and bottom <= sh - margin
end

function W.Movable(f, store)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    if store then store.point = { point, rel, x, y } end
    if self.storeName and ns.db and ns.db.settings then
      frameStore()
      ns.db.settings.frames[self.storeName] = { point, rel, x, y }
    end
  end)
end

-- Put a window at its saved position, else at its default; a saved position that is
-- no longer on screen is forgotten.
function W.Place(f)
  f:ClearAllPoints()
  local p = frameStore(f.storeName)
  if p then
    f:SetPoint(p[1], UIParent, p[2] or p[1], p[3], p[4])
    local sw = UIParent.GetWidth and UIParent:GetWidth()
    local sh = UIParent.GetHeight and UIParent:GetHeight()
    if not W.OnScreen(f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight(), sw, sh) then
      ns.db.settings.frames[f.storeName] = nil
      p = nil
      f:ClearAllPoints()
    end
  end
  if not p then
    local d = f.defaultPoint or { "CENTER", 0, 0 }
    f:SetPoint(d[1], UIParent, d[1], d[2], d[3])
  end
end

W.windows = {}

-- Esc closes the window (UISpecialFrames is how Blizzard's CloseSpecialWindows finds
-- frames to hide).
local function closeOnEscape(name)
  if type(UISpecialFrames) ~= "table" then return end
  for _, n in ipairs(UISpecialFrames) do if n == name then return end end
  table.insert(UISpecialFrames, name)
end

-- A standalone window. Content goes below f.top (y offset of the content area).
-- opts.point = default { point, x, y }.
function W.Window(name, title, w, h, opts)
  opts = opts or {}
  local f
  if hasTemplate("PortraitFrameTemplate") then
    f = CreateFrame("Frame", name, UIParent, "PortraitFrameTemplate")
    f:SetSize(w, h)
    if f.SetTitle then f:SetTitle(title) end
    if f.SetPortraitToAsset then
      -- the logo if its file loads, else the stock fallback icon (Core/Media.lua)
      local probe = f:CreateTexture()
      local path = ns.Media.Apply(probe, "ICON")
      probe:Hide()
      f:SetPortraitToAsset(path)
    end
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f.native = true
    f.top = -62
    f.close = f.CloseButton
  else
    f = W.Panel(name, UIParent, w, h)
    f.titleText = W.Text(f, "large"); f.titleText:SetPoint("TOPLEFT", 10, -10); f.titleText:SetText(title)
    W.TitleIcon(f, f.titleText)
    f.close = W.Button(f, "x", 22, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -6, -6)
    f.top = -36
  end
  f:Hide()
  f.storeName = name
  f.defaultPoint = opts.point
  W.Movable(f)
  closeOnEscape(name)
  W.windows[name] = f
  W.Place(f)
  return f
end

-- /profs resetui: forget saved positions and put every window back at its default.
function W.ResetPositions()
  if ns.db and ns.db.settings then
    ns.db.settings.frames = {}
    ns.db.settings.sidecarStore = nil
  end
  for _, f in pairs(W.windows) do W.Place(f) end
end

function W.Text(parent, size, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", size == "large" and "GameFontNormalLarge"
    or size == "small" and "GameFontHighlightSmall" or "GameFontHighlight")
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

function W.Button(parent, text, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 80, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- One button of a choice group shown as selected: pushed in (the native pressed
-- look, which stays while selected) with the highlight locked and white text; the
-- others normal with gold text. Tabs made by W.Tab use their template's own state.
function W.SetSelected(b, on)
  b.selected = on and true or false
  if b.isTab then
    if b.tabSelect then b.tabSelect(b, b.selected) end
    return
  end
  if on then b:LockHighlight() else b:UnlockHighlight() end
  if b.SetButtonState then b:SetButtonState(on and "PUSHED" or "NORMAL", on) end
  local fs = b.GetFontString and b:GetFontString()
  if fs and fs.SetTextColor then
    if on then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(1, 0.82, 0) end
  end
end

-- A tab: MinimalTabTemplate (Options_Tab atlases), else a plain button.
function W.Tab(parent, text, onClick)
  if hasTemplate("MinimalTabTemplate") then
    local b = CreateFrame("Button", nil, parent, "MinimalTabTemplate")
    b.tabText = text
    if b.Text then b.Text:SetText(text); b:SetWidth(b.Text:GetStringWidth() + 40) end
    b:SetScript("OnClick", function() onClick() end)
    b.isTab = true
    b.tabSelect = function(self, on)
      if self.SetSelectedState and self.OnSelected then
        self:SetSelectedState(on); self:OnSelected(on)
      end
    end
    return b, 37
  end
  return W.Button(parent, text, 90, onClick), 22
end

function W.Input(parent, w, onEnter)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w or 40, 20)
  e:SetAutoFocus(false)
  e:SetNumeric(true)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus(); onEnter(self:GetNumber()) end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return e
end

-- A loading spinner (SpinnerTemplate), or nil where the template is missing.
function W.Spinner(parent, size)
  if not hasTemplate("SpinnerTemplate") then return nil end
  local s = CreateFrame("Frame", nil, parent, "SpinnerTemplate")
  s:SetSize(size or 24, size or 24)
  s:Hide()
  return s
end

-- Pane art -------------------------------------------------------------------

-- Pure: texture coordinates that fill a w x h region from an atlas region (l, r, t, b
-- in file coordinates, aw x ah pixels) without stretching: scale to cover, then crop
-- the overflow equally from both sides (like CSS background-size: cover).
function W.CoverCoords(l, r, t, b, aw, ah, w, h)
  if not (aw and ah and w and h) or aw <= 0 or ah <= 0 or w <= 0 or h <= 0 then return l, r, t, b end
  local s = math.max(w / aw, h / ah)
  local cropX = (1 - (w / s) / aw) / 2 * (r - l)
  local cropY = (1 - (h / s) / ah) / 2 * (b - t)
  return l + cropX, r - cropX, t + cropY, b - cropY
end

local function atlasInfo(atlas)
  if not (atlas and C_Texture and C_Texture.GetAtlasInfo) then return nil end
  local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
  if not ok or type(info) ~= "table" then return nil end
  if not (info.file or info.filename) or not info.width then return nil end
  return info
end

local function fitArt(f)
  local art, info = f.art, f.artInfo
  if not (art and info) then return end
  art:SetTexCoord(W.CoverCoords(info.leftTexCoord, info.rightTexCoord, info.topTexCoord,
    info.bottomTexCoord, info.width, info.height, f:GetWidth(), f:GetHeight()))
end

-- Give a pane the look of Blizzard's own panes: `atlas` as its background (cropped to
-- fit, never stretched) inside the common-insideframe border the recipe details and
-- character stat panes use. nil atlas removes the art (the caller shows its fallback).
function W.PaneArt(f, atlas, shade)
  if not f.art then
    f.art = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    f.art:SetAllPoints()
    f.artShade = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.artShade:SetAllPoints()
    f.artShade:SetColorTexture(0, 0, 0, shade or 0.25)
    f.border = f:CreateTexture(nil, "BORDER")
    f.border:SetPoint("TOPLEFT", 0, 0)
    f.border:SetPoint("BOTTOMRIGHT", 0, 0)
    f:HookScript("OnSizeChanged", fitArt)
  end
  if not atlas then
    f.art:Hide(); f.artShade:Hide(); f.border:Hide()
    f.artAtlas = nil
    return false
  end
  if f.artAtlas ~= atlas then
    f.artAtlas = atlas
    local info = atlasInfo(atlas)
    f.artInfo = info
    if info then
      f.art:SetTexture(info.file or info.filename)
      fitArt(f)
    else
      f.art:SetAtlas(atlas)
    end
    f.border:SetAtlas("common-insideframe")
  end
  f.art:Show(); f.artShade:Show(); f.border:Show()
  return true
end

-- Items ----------------------------------------------------------------------

function W.ItemIcon(itemId)
  if not (itemId and C_Item and C_Item.GetItemIconByID) then return nil end
  local ok, icon = pcall(C_Item.GetItemIconByID, itemId)
  return ok and icon or nil
end

function W.ItemLink(itemId)
  local _, link = ns.Game.ItemName(itemId)
  return link
end

local function modified(kind, fallback)
  if IsModifiedClick then
    local ok, on = pcall(IsModifiedClick, kind)
    if ok then return on end
  end
  return fallback and fallback() or false
end

-- The game's modified clicks on an item row: link it into the chat edit box (Shift
-- by default) or preview it on the dressing room (Ctrl). Returns true if handled.
-- recipe = { id, prof, name }: Shift links the recipe instead of the item (what the
-- crafted-gear rows want: how to make it).
function W.ItemModifiedClick(itemId, recipe)
  local link
  if modified("CHATLINK", IsShiftKeyDown) then
    link = recipe and ns.Game.RecipeLink(recipe[1], recipe[2], recipe[3]) or W.ItemLink(itemId)
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or _G.ChatEdit_InsertLink
    if link and insert then insert(link) end
    return true
  end
  if modified("DRESSUP", IsControlKeyDown) then
    link = W.ItemLink(itemId)
    if link and DressUpLink then DressUpLink(link) end
    return true
  end
  return false
end

-- Lists ----------------------------------------------------------------------
--
-- A row is a table: { text, right?, item?, icon?, indent?, tooltip = fn|string,
-- onClick = fn(button, frame), menu = fn(rootDescription) }.

local ROW_H = Theme.ROW_HEIGHT

local function tooltipLines(d)
  if not d.tooltip then return nil end
  return type(d.tooltip) == "function" and d.tooltip() or { d.tooltip }
end

-- The recipe's own tooltip (what a linked recipe shows: profession and name, the
-- reagents with the ones you lack in red, then the crafted item). False if the client
-- cannot show it.
function W.RecipeTooltip(tip, d)
  local link = ns.Game.RecipeLink(d.recipe, d.recipeProf, d.recipeName)
  if not (link and tip.SetHyperlink) then return false end
  local ok = pcall(tip.SetHyperlink, tip, (link:match("|H(.-)|h") or link))
  return ok and (not tip.NumLines or (tip:NumLines() or 0) > 0)
end

local function showTooltip(row)
  local d = row.data
  if not d or not GameTooltip then return end
  local lines = tooltipLines(d)
  if not lines and not d.item and not d.recipe then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  local first = 1
  if d.recipe and W.RecipeTooltip(GameTooltip, d) then
    first = 2           -- the recipe tooltip already names it
  elseif d.item and GameTooltip.SetItemByID then
    GameTooltip:SetItemByID(d.item)
    first = 2           -- the item tooltip already names the item
  elseif lines then
    GameTooltip:SetText(lines[1])
    first = 2
  end
  for j = first, #(lines or {}) do GameTooltip:AddLine(lines[j], 1, 1, 1, true) end
  if d.menu and MenuUtil then GameTooltip:AddLine(Theme.Wrap("muted", "Right-click: options"), 1, 1, 1) end
  GameTooltip:Show()
end

-- Right-click menu for a row (MenuUtil.CreateContextMenu). False when unavailable.
function W.ContextMenu(owner, title, build)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    if title and root.CreateTitle then root:CreateTitle(title) end
    build(root)
  end)
  return true
end

local function onRowClick(row, button)
  local d = row.data
  if not d then return end
  if d.item and W.ItemModifiedClick(d.item, d.linkRecipe and { d.recipe, d.recipeProf, d.recipeName }) then
    return
  end
  if button == "RightButton" and d.menu
      and W.ContextMenu(row, d.menuTitle, d.menu) then
    return
  end
  if d.onClick then d.onClick(button, row) end
end

-- One-time setup of a row frame (pooled by the ScrollBox, or fixed in the fallback).
function W.InitRow(row)
  if row.profsRow then return row end
  row.profsRow = true
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.zebra = row:CreateTexture(nil, "BACKGROUND")
  row.zebra:SetAllPoints()
  row.zebra:SetColorTexture(1, 1, 1, 0.04)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(Theme.ICON_SIZE, Theme.ICON_SIZE)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.right = W.Text(row, "small", "RIGHT")
  row.right:SetPoint("RIGHT", -2, 0)
  row.text = W.Text(row, "small")
  row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
  row.text:SetWordWrap(false)
  row:SetScript("OnClick", onRowClick)
  row:SetScript("OnEnter", showTooltip)
  row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return row
end

function W.FillRow(row, d)
  row.data = d
  local icon = d.icon or W.ItemIcon(d.item or d.iconItem)
  local x = 2 + (d.indent or 0)
  row.icon:ClearAllPoints()
  if icon then
    row.icon:SetTexture(icon)
    row.icon:SetPoint("LEFT", x, 0)
    row.icon:Show()
    x = x + Theme.ICON_SIZE + 4
  else
    row.icon:Hide()
  end
  row.text:SetPoint("LEFT", x, 0)
  row.text:SetText(d.text or "")
  row.right:SetText(d.right or "")
end

local function scrollBoxAvailable()
  return CreateScrollBoxListLinearView and ScrollUtil and ScrollUtil.InitScrollBoxListWithScrollBar
    and CreateDataProvider and hasTemplate("WowScrollBoxList") and hasTemplate("MinimalScrollBar")
end

local function emptyText(parent)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  fs:SetPoint("TOPLEFT", 8, -24)
  fs:SetPoint("TOPRIGHT", -8, -24)
  fs:SetJustifyH("CENTER")
  fs:Hide()
  return fs
end

-- A list filling `parent`. nRows/rowHeight/width size the fallback paged list; the
-- ScrollBox list fills the parent and shows a scrollbar only when needed.
function W.List(parent, nRows, rowHeight, width)
  local list = { data = {}, offset = 0, empty = emptyText(parent) }
  rowHeight = rowHeight or ROW_H
  function list:SetEmptyText(t) self.emptyMessage = t; self:UpdateEmpty() end
  function list:UpdateEmpty()
    local msg = #self.data == 0 and self.emptyMessage
    self.empty:SetText(msg or "")
    if msg then self.empty:Show() else self.empty:Hide() end
  end

  if scrollBoxAvailable() then
    local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    box:SetPoint("TOPLEFT", 0, 0)
    box:SetPoint("BOTTOMRIGHT", -14, 0)
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(rowHeight)
    view:SetElementInitializer("Button", function(row, d)
      W.InitRow(row)
      W.FillRow(row, d)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    if ScrollUtil.AddManagedScrollBarVisibilityBehavior and CreateAnchor then
      ScrollUtil.AddManagedScrollBarVisibilityBehavior(box, bar,
        { CreateAnchor("TOPLEFT", parent, "TOPLEFT", 0, 0), CreateAnchor("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -16, 0) },
        { CreateAnchor("TOPLEFT", parent, "TOPLEFT", 0, 0), CreateAnchor("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0) })
    end
    if ScrollUtil.RegisterAlternateRowBehavior then
      ScrollUtil.RegisterAlternateRowBehavior(box, function(row, alternate)
        if row.zebra then row.zebra:SetShown(alternate) end
      end)
    end
    list.box, list.bar, list.view = box, bar, view
    function list:Set(data, keepScroll)
      self.data = data or {}
      local retain = keepScroll and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil
      box:SetDataProvider(CreateDataProvider(self.data), retain)
      self:UpdateEmpty()
    end
    function list:ScrollTo(index)
      if box.ScrollToElementDataIndex then box:ScrollToElementDataIndex(index) end
    end
    return list
  end

  -- fallback: fixed rows paged by the mouse wheel
  list.rows = {}
  for i = 1, nRows do
    local b = W.InitRow(CreateFrame("Button", nil, parent))
    b:SetSize(width, rowHeight)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
    list.rows[i] = b
  end
  parent:EnableMouseWheel(true)
  parent:SetScript("OnMouseWheel", function(_, delta)
    list.offset = math.max(0, math.min(list.offset - delta * 3, math.max(0, #list.data - nRows)))
    list:Render()
  end)
  function list:Set(data, keepScroll)
    self.data = data or {}
    if not keepScroll then self.offset = 0 end
    self.offset = math.max(0, math.min(self.offset, #self.data - nRows))
    self:Render()
    self:UpdateEmpty()
  end
  function list:ScrollTo(index)
    self.offset = math.max(0, math.min(index - 1, #self.data - nRows))
    self:Render()
  end
  function list:Render()
    for i, b in ipairs(self.rows) do
      local idx = i + self.offset
      local d = self.data[idx]
      b.index = idx
      if d then
        W.FillRow(b, d)
        b.zebra:SetShown(idx % 2 == 0)
        b:Show()
      else
        b.data = nil
        b:Hide()
      end
    end
  end
  return list
end
