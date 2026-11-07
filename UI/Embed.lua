-- Profs! as a THIRD COLUMN inside the native profession window.
--
-- Forever 1.60.x (Gethe/wow-ui-source, branch forever; client game type "camelot"):
--   ProfessionsFrame (Camelot/Blizzard_ProfessionsFrame.xml) is ONE shared window for
--   every profession: recipe list (left) and recipe details (middle) live in
--   CraftingPage, the overview in BookPage; both are setAllPoints on the frame. The
--   vertical profession tabs (ProfessionsOverviewTab, Professions1..7Tab) are anchored
--   TOPLEFT -> the frame's TOPRIGHT, i.e. OUTSIDE its right edge. There is no TabSystem
--   in the camelot frame, so Blizzard never resizes it after load (SetTab/
--   ApplyDesiredWidth return early or are unreachable); it keeps its XML width.
--
-- Layout applied here:
--   1. the frame is widened by COLUMN_WIDTH, so its right edge (and with it the vertical
--      tabs) moves outward: the tabs stay visible and keep their own click handlers;
--   2. CraftingPage and BookPage are re-anchored to end COLUMN_WIDTH before the right
--      edge, so the recipe list, details, Create buttons and tool slots stay exactly
--      where Blizzard put them (their right-anchored children follow the page edge);
--   3. CraftingOutputLog, anchored to the page's right in Blizzard's XML, is anchored to
--      the frame's right instead (where it was before the page moved);
--   4. the Profs column is a child of the frame between the page and the right edge:
--      it shows and hides with the window, moves with it, and persists across profession
--      tabs (the frame is shared; content follows the selected profession).
--   The UI panel layout learns the new width the way Blizzard's own output log does it
--   (SetUIPanelAttribute "width" + UpdateUIPanelPositions), outside combat only.
--   If Blizzard sets the frame width itself, the hook re-adds the column on top.
-- Restore() puts every anchor and the width back (/profs show toggles the column).
local _, ns = ...
local E = ns:NewModule("Embed")

E.COLUMN_WIDTH = 330

-- Pure layout numbers for a given native frame width.
function E.Layout(nativeWidth)
  return { frameWidth = nativeWidth + E.COLUMN_WIDTH, pageRightOffset = -E.COLUMN_WIDTH }
end

-- True while the window shows a profession's recipes (CraftingPage), false on the
-- profession overview (BookPage, no profession selected). Decided by the pages Blizzard
-- shows (SelectBookPage / TRADE_SKILL_SHOW / Professions.ShowSelectedCraftingPage flip
-- them), not by the open trade skill, which can still name the last profession while
-- the overview is shown.
function E.ShowingRecipes(pf)
  if not pf or not pf.CraftingPage or not pf.CraftingPage:IsShown() then return false end
  return not (pf.BookPage and pf.BookPage:IsShown())
end

function E.Frame()
  local pf = _G.ProfessionsFrame
  if type(pf) == "table" and pf.GetWidth and pf.CraftingPage then return pf end
  return nil
end

local function pages(pf)
  local out = {}
  for _, key in ipairs({ "CraftingPage", "BookPage" }) do
    if pf[key] then out[#out + 1] = pf[key] end
  end
  return out
end

local function updatePanelLayout(pf, width)
  if InCombatLockdown and InCombatLockdown() then E.pendingPanel = true; return end
  E.pendingPanel = nil
  if SetUIPanelAttribute and UpdateUIPanelPositions then
    pcall(SetUIPanelAttribute, pf, "width", width)
    pcall(UpdateUIPanelPositions, pf)
  end
end

local function setWidth(pf, width)
  E.settingWidth = true
  pf:SetWidth(width)
  E.settingWidth = false
  updatePanelLayout(pf, width)
end

-- Hook once: Blizzard-initiated width changes become the new native width.
local function hookWidth(pf)
  if E.widthHooked or not hooksecurefunc then return end
  E.widthHooked = true
  hooksecurefunc(pf, "SetWidth", function(self, w)
    if E.settingWidth or not E.applied then return end
    E.nativeWidth = w
    setWidth(self, E.Layout(w).frameWidth)
  end)
end

E.TOP, E.BOTTOM = -60, 8

-- Pure: the column's top and bottom offsets inside the frame. The column lines up with
-- the recipe details pane (SchematicForm) when its edges are known and plausible,
-- so the two panes read as one row; otherwise the fixed defaults.
function E.Edges(frameTop, frameBottom, paneTop, paneBottom)
  if not (frameTop and frameBottom and paneTop and paneBottom) then return E.TOP, E.BOTTOM end
  local top, bottom = paneTop - frameTop, paneBottom - frameBottom
  if top > -20 or top < -140 or bottom < 0 or bottom > 90 then return E.TOP, E.BOTTOM end
  return top, bottom
end

function E.ColumnEdges(pf)
  local sf = pf.CraftingPage and pf.CraftingPage.SchematicForm
  if type(sf) ~= "table" or not (sf.GetTop and pf.GetTop) then return E.TOP, E.BOTTOM end
  return E.Edges(pf:GetTop(), pf:GetBottom(), sf:GetTop(), sf:GetBottom())
end

function E.Apply(column)
  local pf = E.Frame()
  if not pf then return false end
  hookWidth(pf)
  if not E.applied then
    E.nativeWidth = pf:GetWidth()
    E.applied = true
  end
  local layout = E.Layout(E.nativeWidth)
  for _, page in ipairs(pages(pf)) do
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", pf, "TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", layout.pageRightOffset, 0)
  end
  local log = pf.CraftingPage.CraftingOutputLog
  if log then
    log:ClearAllPoints()
    log:SetPoint("TOPLEFT", pf, "TOPRIGHT", 20, 0)
  end
  if math.abs((pf:GetWidth() or 0) - layout.frameWidth) > 0.5 then setWidth(pf, layout.frameWidth) end
  if column then
    local top, bottom = E.ColumnEdges(pf)
    column:SetParent(pf)
    column:ClearAllPoints()
    column:SetPoint("TOPLEFT", pf, "TOPRIGHT", -E.COLUMN_WIDTH + 2, top)
    column:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -8, bottom)
    column:Show()
  end
  return true
end

function E.Restore(column)
  local pf = E.Frame()
  if column then column:Hide() end
  if not pf or not E.applied then return end
  E.applied = false
  for _, page in ipairs(pages(pf)) do
    page:ClearAllPoints()
    page:SetAllPoints(pf)
  end
  local log = pf.CraftingPage.CraftingOutputLog
  if log then
    log:ClearAllPoints()
    log:SetPoint("TOPLEFT", pf.CraftingPage, "TOPRIGHT", 20, 0)
  end
  setWidth(pf, E.nativeWidth)
end

function E.OnCombatEnded()
  local pf = E.Frame()
  if E.pendingPanel and pf then updatePanelLayout(pf, pf:GetWidth()) end
end
