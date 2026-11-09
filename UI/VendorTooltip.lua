-- Item tooltips: the nearest friendly or neutral vendor selling the item, with its
-- coordinates and how far it is (Engine/Vendors). Options: "Nearest vendor in item
-- tooltips" (settings.vendorTooltip).
--
-- HOOK. TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn(tooltip,
-- data)) with data.id the item id (Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua,
-- branch `forever`); clients without it get GameTooltip's OnTooltipSetItem. Comparison
-- tooltips (ShoppingTooltip1/2) are left alone.
local _, ns = ...
local VT = ns:NewModule("VendorTooltip")

function VT.Enabled()
  return not (ns.db and ns.db.settings and ns.db.settings.vendorTooltip == false)
end

-- The two halves of the line for an item, or nil when no vendor you can use sells it.
function VT.Line(itemId)
  local ds = ns.ActiveDataset()
  if not (ds and ds.sold and ds.sold[itemId]) then return nil end
  local best, n = ns.Vendors.Nearest(ds, itemId, {
    side = ns.Game.Faction(), here = ns.Map.PlayerWorldPos(), world = ns.Map.WorldPos })
  if not best then return nil end
  local npc = best.npc
  local left = ("Vendor: %s"):format(npc.n or ("npc " .. best.id))
  if n > 1 then left = left .. ns.Theme.Wrap("muted", (" (+%d more)"):format(n - 1)) end
  local where = ("%s %.1f, %.1f"):format(ns.Map.ZoneName(npc.m, npc.zone) or "?", npc.x, npc.y)
  if best.yards then
    where = where .. " - " .. ns.Vendors.FormatYards(best.yards)
  elseif best.elsewhere then
    where = where .. ns.Theme.Wrap("muted", " (other continent)")
  end
  return left, where
end

local SKIP = { ShoppingTooltip1 = true, ShoppingTooltip2 = true }

function VT.OnItem(tooltip, itemId)
  if not (VT.Enabled() and tooltip and itemId and tooltip.AddDoubleLine) then return end
  local name = tooltip.GetName and tooltip:GetName()
  if name and SKIP[name] then return end
  local ok, left, right = pcall(VT.Line, itemId)
  if not (ok and left) then return end
  tooltip:AddDoubleLine(left, right, 1, 0.82, 0, 1, 1, 1)
  if tooltip.Show then tooltip:Show() end   -- resize to the new line
end

function VT.Install()
  if VT.installed then return end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
      and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      VT.OnItem(tooltip, data and data.id)
    end)
    VT.installed = true
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
      local _, link = tooltip:GetItem()
      VT.OnItem(tooltip, link and tonumber(link:match("item:(%d+)")))
    end)
    VT.installed = true
  end
end

ns.Events.On("PROFS_LOADED", VT.Install)
