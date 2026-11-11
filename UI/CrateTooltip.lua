-- Waylaid Crates in item tooltips (Engine/Crates, Data/Crates.lua). On a crate: every
-- bundle that fills it against your bags, the cost of the missing part, the Merchant's
-- Favor it pays and where to turn it in. On a sealed crate: the Favor and the turn-in.
-- On a bundle item while you carry a crate it fills: which crate, how many.
-- Options: "Waylaid Crates in item tooltips" (settings.crateTooltip). /profs crates
-- lists the crates you carry and points the arrow at your faction's turn-in.
-- Hooked like UI/VendorTooltip.lua (TooltipDataProcessor, else OnTooltipSetItem).
local _, ns = ...
local CT = ns:NewModule("CrateTooltip")
local C = ns.Crates

function CT.Enabled()
  return not (ns.db and ns.db.settings and ns.db.settings.crateTooltip == false)
end

local function itemName(ds, id)
  local n = ns.Game.ItemName and ns.Game.ItemName(id)
  local it = ds and ds.items and ds.items[id]
  return n or (it and it.n) or ("item " .. id)
end

local function favorText(n)
  return n and ("%d Merchant's Favor"):format(n) or ns.Theme.Wrap("muted", "Merchant's Favor (amount not known)")
end

local function turnInLine(side)
  local t = C.TurnIn(side)[1]
  if not t then return nil end
  return "Turn in", ("%s, %s %.1f, %.1f"):format(t.n, t.zone or "?", t.x, t.y)
end

local function bags(id) return ns.Game.ItemCount(id, false) end

-- The tooltip's lines for itemId: { {left, right|nil}, ... } or nil. Pure over
-- have(id) -> n, pricer, side.
function CT.Lines(itemId, ds, have, pricer, side)
  local W = ns.Theme.Wrap
  local crate = C.Crate(itemId)
  if crate then
    local out = { { W("gold", "Profs!") .. " fill with one bundle:" } }
    for i, row in ipairs(C.Fill(crate, have, pricer)) do
      local left = ("%s%d %s"):format(i == 1 and "> " or "  ", row.count, itemName(ds, row.item))
      local right
      if row.ready then right = W("done", "ready")
      elseif row.cost then right = ("%d/%d, buy %d: %s"):format(row.have, row.count, row.missing, ns.Util.money(row.cost))
      else right = ("%d/%d"):format(row.have, row.count) .. W("muted", ", no price") end
      out[#out + 1] = { left, right }
    end
    out[#out + 1] = { "Pays", favorText(crate.favor) }
    local l, r = turnInLine(side)
    if l then out[#out + 1] = { l, r } end
    return out
  end
  local sealed = C.Sealed(itemId)
  if sealed then
    local out = { { W("gold", "Profs!") .. " pays", favorText(sealed.favor) } }
    local l, r = turnInLine(side)
    if l then out[#out + 1] = { l, r } end
    return out
  end
  if C.IsUnread(itemId) then
    return { { W("gold", "Profs!") .. " use it to read the label: it asks for one bundle" },
      { "  of herbs, ore, cloth, bars or parts and pays Merchant's Favor." } }
  end
  local out
  for _, use in ipairs(C.ForItem(itemId)) do
    if have(use.crate) > 0 then
      out = out or {}
      out[#out + 1] = { W("gold", "Profs!") .. (" %d fill %s"):format(use.count, itemName(ds, use.crate)),
        ("have %d"):format(have(itemId)) }
    end
  end
  return out
end

local SKIP = { ShoppingTooltip1 = true, ShoppingTooltip2 = true }
local pricer, pricerKey

local function currentPricer(ds)
  local key = tostring(ds) .. ":" .. ns.AHPrices.epoch .. ":" .. ns.PriceSources.epoch
  if key ~= pricerKey then pricer, pricerKey = ns.PriceSources.Pricer(ds), key end
  return pricer
end

function CT.OnItem(tooltip, itemId)
  if not (CT.Enabled() and tooltip and itemId and tooltip.AddDoubleLine) then return end
  local name = tooltip.GetName and tooltip:GetName()
  if name and SKIP[name] then return end
  local ds = ns.ActiveDataset()
  if not ds then return end
  local ok, lines = pcall(CT.Lines, itemId, ds, bags, currentPricer(ds), ns.Game.Faction())
  if not (ok and lines) then return end
  for _, l in ipairs(lines) do
    if l[2] then tooltip:AddDoubleLine(l[1], l[2], 1, 1, 1, 1, 1, 1)
    else tooltip:AddLine(l[1], 1, 1, 1) end
  end
  if tooltip.Show then tooltip:Show() end
end

function CT.Install()
  if CT.installed then return end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
      and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      CT.OnItem(tooltip, data and data.id)
    end)
    CT.installed = true
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
      local _, link = tooltip:GetItem()
      CT.OnItem(tooltip, link and tonumber(link:match("item:(%d+)")))
    end)
    CT.installed = true
  end
end

-- /profs crates: the crates you carry, the best bundle for each, your Favor, and the
-- arrow to your faction's turn-in NPC.
function CT.Report(ds, have, pricer, side, favor)
  local out = {}
  local ids = {}
  for id in pairs(ns.CrateData and ns.CrateData.crates or {}) do if have(id) > 0 then ids[#ids + 1] = id end end
  for id in pairs(ns.CrateData and ns.CrateData.sealed or {}) do if have(id) > 0 then ids[#ids + 1] = id end end
  if ns.CrateData and have(ns.CrateData.unread) > 0 then ids[#ids + 1] = ns.CrateData.unread end
  table.sort(ids)
  out[#out + 1] = ("Merchant's Favor: %d. Waylaid crates in your bags: %d kinds."):format(favor or 0, #ids)
  for _, id in ipairs(ids) do
    local crate = C.Crate(id)
    local line = ("  %dx %s"):format(have(id), itemName(ds, id))
    if crate then
      local best = C.Fill(crate, have, pricer)[1]
      if best then
        line = line .. (best.ready and (": ready with %d %s"):format(best.count, itemName(ds, best.item))
          or (": best %d %s (have %d%s)"):format(best.count, itemName(ds, best.item), best.have,
            best.cost and (", buy rest " .. ns.Util.money(best.cost)) or ""))
      end
    elseif C.Sealed(id) then
      line = line .. ": turn in for " .. favorText(C.Favor(id))
    else
      line = line .. ": use it to read the label"
    end
    out[#out + 1] = line
  end
  local price, cid = C.FavorPrice(pricer, { charLevel = UnitLevel and UnitLevel("player") or nil })
  if price then
    out[#out + 1] = ("  One Favor costs about %s (cheapest: %s)."):format(ns.Util.money(price), itemName(ds, cid))
  end
  return out
end

ns.commands.crates = function()
  local ds = ns.ActiveDataset()
  if not ds then return ns.Log("info", "no dataset for this client") end
  local side = ns.Game.Faction()
  for _, l in ipairs(CT.Report(ds, bags, currentPricer(ds), side,
      ns.Game.CurrencyQuantity(C.CURRENCY))) do ns.Log("info", l) end
  local t = C.TurnIn(side)[1]
  if t and t.m then
    ns.Map.SetWaypoint(t.m, t.x, t.y, ("%s (Waylaid Crates)"):format(t.n))
    ns.Log("info", ("Turn in at %s, %s %.1f, %.1f."):format(t.n, t.zone or "?", t.x, t.y))
  end
end

ns.Events.On("PROFS_LOADED", CT.Install)
