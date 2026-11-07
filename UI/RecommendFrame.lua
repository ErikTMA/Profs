-- Profession recommendation screen (/profs recommend): primary pairs ranked by
-- total leveling cost minus synergy, then secondaries.
local _, ns = ...
local RF = ns:NewModule("RecommendFrame")
local U = ns.Util

function RF.Format(ds, res)
  local rows = { { text = "|cffffd100Primary pairs (cost to max, after synergy)|r" } }
  for i, p in ipairs(res.pairs) do
    if i > 10 then break end
    local name = ns.Professions.Name(p.a) .. " + " .. ns.Professions.Name(p.b)
    rows[#rows + 1] = { pair = p, text = ("%2d. %s  %s%s%s"):format(i, name, U.money(p.cost),
      p.synergy > 0 and ("  (synergy -" .. U.money(p.synergy) .. ")") or "",
      p.complete and "" or "  |cffff4040incomplete data|r") }
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
  rows[#rows + 1] = { text = "|cffffd100Secondary|r" }
  for _, s in ipairs(res.secondary) do
    rows[#rows + 1] = { text = ("    %s  %s%s"):format(ns.Professions.Name(s.prof), U.money(s.cost),
      s.complete and "" or "  |cffff4040incomplete data|r") }
  end
  rows[#rows + 1] = { text = "|cffa0a0a0Estimates from expected craft counts and current prices.|r" }
  return rows
end

function RF.Show()
  local ds = ns.ActiveDataset()
  if not ds then ns.Log("warn", "no dataset; see /profs status"); return end
  local W = ns.Widgets
  if not RF.frame then
    local f = W.Panel("ProfsRecommend", UIParent, 460, 420)
    f:SetPoint("CENTER")
    W.Movable(f)
    local t = W.Text(f, "large"); t:SetPoint("TOPLEFT", 10, -10); t:SetText("Profs! - Which professions?")
    W.TitleIcon(f, t)
    local c = W.Button(f, "x", 22, function() f:Hide() end); c:SetPoint("TOPRIGHT", -6, -6)
    local body = CreateFrame("Frame", nil, f); body:SetPoint("TOPLEFT", 10, -36); body:SetSize(440, 375)
    f.list = W.List(body, 25, 15, 440)
    for i, row in ipairs(f.list.rows) do row:SetPoint("TOPLEFT", 0, -(i - 1) * 15) end
    RF.frame = f
  end
  local res = ns.Recommend.Rank(ds, { pricer = ns.PriceSources.Pricer(ds),
    allowSources = ns.db.settings.allowSources, side = ns.Game.Faction() })
  RF.frame.list:Set(RF.Format(ds, res))
  RF.frame:Show()
end

ns.commands.recommend = RF.Show
