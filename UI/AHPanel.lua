-- Panel beside the native Auction House window: scan buttons, progress, freshness.
-- Scans start ONLY from these buttons (see Adapters/AHScan.lua).
local _, ns = ...
local P = ns:NewModule("AHPanel")
local AH = ns.AHPrices

-- Items + quantities of every planned route (all professions with a target).
function P.ScanList()
  local items, want, seen = {}, {}, {}
  for _, lst in pairs((ns.cdb and ns.cdb.scanList) or {}) do
    for id, n in pairs(lst) do
      want[id] = math.max(want[id] or 0, n)
      if not seen[id] then seen[id] = true; items[#items + 1] = id end
    end
  end
  table.sort(items)
  return items, want
end

-- Pure: the panel's text lines.
function P.Format(status, st, now, scope, listCount)
  local lines = { ("Prices for %s"):format(scope) }
  if status.scanned == 0 then
    lines[#lines + 1] = "No scan yet on this realm/faction."
  else
    lines[#lines + 1] = ("%d items scanned (%d priced), newest %s, oldest %s"):format(status.scanned,
      status.priced, AH.FormatAge(status.newest and now - status.newest),
      AH.FormatAge(status.oldest and now - status.oldest))
  end
  if st and st.running then
    local what = st.kind == "full" and "Full scan" or "Shopping-list scan"
    if st.kind == "full" and st.phase == "requesting" then
      lines[#lines + 1] = what .. ": waiting for the server..."
    else
      lines[#lines + 1] = ("%s: %d / %d%s"):format(what, st.done, st.total,
        st.waiting == "throttle" and " (waiting for the AH throttle)" or "")
    end
  elseif status.last then
    local l = status.last
    lines[#lines + 1] = ("Last %s scan: %s, %d/%d done, %d priced, %d not listed%s%s"):format(
      l.kind == "full" and "full" or "list", l.status, l.done or 0, l.total or 0, l.priced or 0, l.none or 0,
      (l.errors or 0) > 0 and (", " .. l.errors .. " failed") or "", l.error and (" - " .. l.error) or "")
  end
  if status.fullCooldown and status.fullCooldown > 0 then
    lines[#lines + 1] = ("Full scan available in %d min."):format(math.ceil(status.fullCooldown / 60))
  end
  lines[#lines + 1] = ("Shopping list: %d items to scan."):format(listCount or 0)
  return lines
end

function P.Render()
  local f = P.frame
  if not f then return end
  local now = ns.AHScan.Now()
  local status = AH.Status(ns.db.ah, ns.AHScan.Scope(), now)
  local items = P.ScanList()
  local lines = P.Format(status, ns.AHScan.state, now, ns.AHScan.Scope(), #items)
  f.text:SetText(table.concat(lines, "\n"))
  local running = ns.AHScan.state.running
  if f.spinner then if running then f.spinner:Show() else f.spinner:Hide() end end
  if running then f.list:Disable(); f.full:Disable(); f.stop:Enable()
  else
    f.stop:Disable()
    if #items > 0 and ns.AHScan.Supported() then f.list:Enable() else f.list:Disable() end
    if ns.AHScan.FullSupported() and ns.AHScan.FullCooldown() == 0 then f.full:Enable() else f.full:Disable() end
  end
end

function P.ScanListClicked()
  local items, want = P.ScanList()
  local ok, err = ns.AHScan.StartList(items, want)
  if not ok then ns.Log("warn", err) end
  P.Render()
end

function P.FullClicked()
  local ds = ns.ActiveDataset()
  local track = {}
  for id in pairs(ds and ds.items or {}) do track[id] = true end
  for _, id in ipairs((P.ScanList())) do track[id] = true end
  local ok, err = ns.AHScan.StartFull(track)
  if not ok then ns.Log("warn", err) end
  P.Render()
end

function P.Build()
  if P.frame then return P.frame end
  local W = ns.Widgets
  local f = W.Window("ProfsAHPanel", ns.displayName .. " prices", 320, 240, { point = { "CENTER", 0, 200 } })
  f.text = W.Text(f, "small"); f.text:SetPoint("TOPLEFT", 12, f.top); f.text:SetWidth(296)
  f.spinner = W.Spinner(f, 22)
  if f.spinner then f.spinner:SetPoint("TOPRIGHT", -12, f.top + 4) end
  f.list = W.Button(f, "Scan shopping list", 130, P.ScanListClicked); f.list:SetPoint("BOTTOMLEFT", 10, 10)
  f.full = W.Button(f, "Full scan", 80, P.FullClicked); f.full:SetPoint("LEFT", f.list, "RIGHT", 4, 0)
  f.stop = W.Button(f, "Stop", 60, function() ns.AHScan.Stop("stopped by you"); P.Render() end)
  f.stop:SetPoint("LEFT", f.full, "RIGHT", 4, 0)
  P.frame = f
  return f
end

function P.Show()
  local f = P.Build()
  f:ClearAllPoints()
  local ah = _G.AuctionHouseFrame
  if ah and ah.IsShown and ah:IsShown() then f:SetPoint("TOPLEFT", ah, "TOPRIGHT", 2, 0)
  else f:SetPoint("CENTER", 0, 200) end
  f:Show()
  P.Render()
end

function P.Hide() if P.frame then P.frame:Hide() end end

ns.Events.On("PROFS_AH_SCAN", function() P.Render() end)

ns.commands.ah = function()
  if not ns.AHScan.open then ns.Log("warn", "open the Auction House to scan prices"); return end
  P.Show()
end
