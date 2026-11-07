-- Minimap button, hand-rolled (no LibDBIcon dependency) with LibDBIcon's geometry, so
-- it sits on the minimap's edge for every minimap shape and button-collector addons
-- recognise it by name (LibDBIcon10_<name>).
--   click        route for the open profession
--   shift-click  craftable gear upgrades
--   right-click  which professions to pick
--   ctrl-click   options
--   drag         move around the minimap (position saved per character)
-- /profs minimap shows or hides it (per character; also in the options).
local _, ns = ...
local MB = ns:NewModule("MinimapButton")

MB.NAME = "LibDBIcon10_Profs"
MB.DEFAULT_ANGLE = 200
MB.RADIUS_PAD = 5      -- LibDBIcon lib.radius

-- Which quadrants of each minimap shape are round (LibDBIcon's table). Quadrant q, as
-- LibDBIcon counts them: 1 bottom-right, 2 bottom-left, 3 top-right, 4 top-left.
MB.SHAPES = {
  ["ROUND"] = { true, true, true, true },
  ["SQUARE"] = { false, false, false, false },
  ["CORNER-TOPLEFT"] = { false, false, false, true },
  ["CORNER-TOPRIGHT"] = { false, false, true, false },
  ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
  ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
  ["SIDE-LEFT"] = { false, true, false, true },
  ["SIDE-RIGHT"] = { true, false, true, false },
  ["SIDE-TOP"] = { false, false, true, true },
  ["SIDE-BOTTOM"] = { true, true, false, false },
  ["TRICORNER-TOPLEFT"] = { false, true, true, true },
  ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
  ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
  ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

-- Pure: the button's offset from the minimap centre for an angle (degrees) on a
-- minimap of width w and height h with the given shape.
function MB.Offset(angle, w, h, shape)
  local a = math.rad(angle or MB.DEFAULT_ANGLE)
  local x, y, q = math.cos(a), math.sin(a), 1
  if x < 0 then q = q + 1 end
  if y > 0 then q = q + 2 end
  local round = (MB.SHAPES[shape or "ROUND"] or MB.SHAPES.ROUND)[q]
  local rw, rh = w / 2 + MB.RADIUS_PAD, h / 2 + MB.RADIUS_PAD
  if round then return x * rw, y * rh end
  local dw, dh = math.sqrt(2 * rw ^ 2) - 10, math.sqrt(2 * rh ^ 2) - 10
  return math.max(-rw, math.min(x * dw, rw)), math.max(-rh, math.min(y * dh, rh))
end

-- Pure: angle (degrees, 0-360) of the cursor around the minimap centre.
function MB.Angle(cx, cy, px, py)
  return math.deg(math.atan2(py - cy, px - cx)) % 360
end

local function store()
  ns.cdb.minimap = ns.cdb.minimap or {}
  return ns.cdb.minimap
end

function MB.Place()
  local b, mm = MB.button, _G.Minimap
  if not (b and mm) then return end
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  local x, y = MB.Offset(store().angle or MB.DEFAULT_ANGLE, mm:GetWidth() or 140, mm:GetHeight() or 140, shape)
  b:ClearAllPoints()
  b:SetPoint("CENTER", mm, "CENTER", x, y)
end

local function dragUpdate()
  local mm = _G.Minimap
  if not (mm and GetCursorPosition) then return end
  local mx, my = mm:GetCenter()
  local px, py = GetCursorPosition()
  local scale = mm:GetEffectiveScale()
  if not (mx and px and scale) then return end
  store().angle = MB.Angle(mx, my, px / scale, py / scale)
  MB.Place()
end

function MB.Tooltip(tip)
  tip:SetText(ns.displayName)
  for _, l in ipairs(ns.LAUNCHER_LINES) do tip:AddLine(l, 1, 1, 1) end
  tip:AddLine("Drag: move around the minimap. /profs minimap: hide.", 0.63, 0.63, 0.63)
end

function MB.Build()
  if MB.button or not _G.Minimap then return MB.button end
  local b = CreateFrame("Button", MB.NAME, _G.Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("AnyUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local overlay = b:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(50, 50)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(24, 24)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("CENTER")
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetPoint("CENTER")
  ns.Media.Apply(icon, "ICON")
  b.icon = icon
  b:SetScript("OnClick", function(_, button) ns.LauncherClick(button) end)
  b:SetScript("OnDragStart", function(self)
    self.dragging = true
    self:LockHighlight()
    self:SetScript("OnUpdate", dragUpdate)
    if GameTooltip then GameTooltip:Hide() end
  end)
  b:SetScript("OnDragStop", function(self)
    self.dragging = false
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil)
  end)
  b:SetScript("OnEnter", function(self)
    if self.dragging or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    MB.Tooltip(GameTooltip)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- minimap addons resize the minimap: follow its edge
  if _G.Minimap.HookScript then _G.Minimap:HookScript("OnSizeChanged", MB.Place) end
  MB.button = b
  MB.Place()
  return b
end

function MB.Shown() return store().hide ~= true end

function MB.SetShown(on)
  store().hide = (not on) or nil
  if on then
    MB.Build()
    if MB.button then MB.button:Show() end
  elseif MB.button then
    MB.button:Hide()
  end
end

ns.Events.On("PROFS_LOADED", function()
  if not CreateFrame then return end
  if MB.Shown() then MB.SetShown(true) end
end)

ns.commands.minimap = function()
  MB.SetShown(not MB.Shown())
  ns.Log("info", MB.Shown() and "minimap button shown" or "minimap button hidden (/profs minimap to bring it back)")
end
