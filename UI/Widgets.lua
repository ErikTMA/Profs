-- Small frame helpers on stock templates (BackdropTemplate, UIPanelButtonTemplate,
-- InputBoxTemplate). Lists page with the mouse wheel instead of scroll templates.
local _, ns = ...
local W = ns:NewModule("Widgets")

W.COLORS = { "ff8040", "ffff00", "40bf40", "808080" } -- orange, yellow, green, grey

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

function W.Movable(f, store)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if store then
      local point, _, rel, x, y = self:GetPoint()
      store.point = { point, rel, x, y }
    end
  end)
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

-- One button of a choice group shown as selected: highlight locked on (the native
-- pushed-in look) and bright text; the others normal gold text.
function W.SetSelected(b, on)
  b.selected = on and true or false
  if on then b:LockHighlight() else b:UnlockHighlight() end
  local fs = b.GetFontString and b:GetFontString()
  if fs and fs.SetTextColor then
    if on then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(1, 0.82, 0) end
  end
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

-- A paged list of clickable rows. rows = { {text, tooltip=fn|string, onClick=fn(button)} }
function W.List(parent, nRows, rowHeight, width)
  local list = { rows = {}, data = {}, offset = 0 }
  for i = 1, nRows do
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, rowHeight)
    b:RegisterForClicks("AnyUp")
    b.text = W.Text(b, "small")
    b.text:SetAllPoints()
    b:SetScript("OnClick", function(self, button)
      local d = list.data[self.index]
      if d and d.onClick then d.onClick(button) end
    end)
    b:SetScript("OnEnter", function(self)
      local d = list.data[self.index]
      if not d or not d.tooltip or not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local lines = type(d.tooltip) == "function" and d.tooltip() or { d.tooltip }
      for j, l in ipairs(lines) do
        if j == 1 then GameTooltip:SetText(l) else GameTooltip:AddLine(l, 1, 1, 1, true) end
      end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    list.rows[i] = b
  end
  parent:EnableMouseWheel(true)
  parent:SetScript("OnMouseWheel", function(_, delta)
    list.offset = math.max(0, math.min(list.offset - delta * 3, math.max(0, #list.data - nRows)))
    list:Render()
  end)
  function list:Set(data) self.data = data or {}; self.offset = 0; self:Render() end
  function list:Render()
    for i, b in ipairs(self.rows) do
      local idx = i + self.offset
      local d = self.data[idx]
      b.index = idx
      if d then b.text:SetText(d.text); b:Show() else b:Hide() end
    end
  end
  return list
end
