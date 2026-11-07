-- Profession recommendation screen (/profs recommend): primary pairs ranked by
-- total leveling cost minus synergy, then secondaries.
local _, ns = ...
local RF = ns:NewModule("RecommendFrame")
local U = ns.Util

function RF.Format(ds, res)
  local rows = { { text = ns.Theme.Wrap("gold", "Primary pairs (cost to max, after synergy)") } }
  for i, p in ipairs(res.pairs) do
    if i > 10 then break end
    local name = ns.Professions.Name(p.a) .. " + " .. ns.Professions.Name(p.b)
    rows[#rows + 1] = { pair = p, text = ("%2d. %s  %s%s%s"):format(i, name, U.money(p.cost),
      p.synergy > 0 and ("  (synergy -" .. U.money(p.synergy) .. ")") or "",
      p.complete and "" or "  " .. ns.Theme.Wrap("warn", "incomplete data")) }
    local shown = 0
    for _, w in ipairs(p.why) do
      if w.item and shown < 3 then
        shown = shown + 1
        rows[#rows + 1] = { text = ("      %s %s -> %s: %s x%.0f (%s)"):format(
          w.kind == "disenchant" and "DE" or "uses", ns.Professions.Name(w.from), ns.Professions.Name(w.to),
          ns.Sidecar.ItemName(ds, w.item), w.qty, U.money(w.value)) }
      end
    end
  end
  rows[#rows + 1] = { text = ns.Theme.Wrap("gold", "Secondary") }
  for _, s in ipairs(res.secondary) do
    rows[#rows + 1] = { text = ("    %s  %s%s"):format(ns.Professions.Name(s.prof), U.money(s.cost),
      s.complete and "" or "  " .. ns.Theme.Wrap("warn", "incomplete data")) }
  end
  rows[#rows + 1] = { text = ns.Theme.Wrap("muted", "Estimates from expected craft counts and current prices.") }
  return rows
end

function RF.Show()
  local ds = ns.ActiveDataset()
  if not ds then ns.Log("warn", "no dataset; see /profs status"); return end
  local W = ns.Widgets
  if not RF.frame then
    local f = W.Window("ProfsRecommend", ns.displayName .. " - Which professions?", 480, 470, { point = { "CENTER", 0, 0 } })
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 12, f.top)
    body:SetPoint("BOTTOMRIGHT", -12, 12)
    body:SetSize(450, 375)
    f.list = W.List(body, 24, ns.Theme.ROW_HEIGHT, 450)
    RF.frame = f
  end
  local res = ns.Recommend.Rank(ds, { pricer = ns.PriceSources.Pricer(ds),
    allowSources = ns.db.settings.allowSources, side = ns.Game.Faction() })
  RF.frame.list:Set(RF.Format(ds, res))
  RF.frame:Show()
end

ns.commands.recommend = RF.Show
