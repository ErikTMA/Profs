-- Leveling gear helper: craftable upgrades from your professions (and your alts'
-- professions on this account). Pawn when installed, else automatic built-in weights.
-- GF.Compute/GF.Format feed the character-frame column (UI/GearColumn.lua, which owns
-- /profs gear); GF.Show is the stand-alone list, used only without a character frame.
local _, ns = ...
local GF = ns:NewModule("GearFrame")

local SLOT_TO_INV = { [1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 5, [20] = 5, [6] = 6, [7] = 7, [8] = 8,
  [9] = 9, [10] = 10, [11] = 11, [12] = 13, [16] = 15, [13] = 16, [17] = 16, [21] = 16, [14] = 17,
  [22] = 17, [23] = 17, [15] = 18, [25] = 18, [26] = 18 }
GF.SLOT_TO_INV = SLOT_TO_INV

function GF.Format(ds, upgrades, usingPawn)
  local T = ns.Theme
  local rows = { { summary = true, text = T.Wrap("gold", usingPawn and "Scored by Pawn"
    or "Scored by built-in automatic weights") } }
  for i, c in ipairs(upgrades) do
    if i > 20 then break end
    local r = ds.recipes[c.recipe]
    rows[#rows + 1] = { item = c.itemId, upgrade = c, recipe = c.recipe, linkRecipe = true,
      recipeProf = ns.Professions.Name(c.prof), recipeName = r and r.name,
      text = ("%s  %s%s%s"):format(ns.Sidecar.ItemName(ds, c.itemId),
        T.Wrap("muted", ("%s, req %d"):format(ns.Professions.Name(c.prof), c.reqLevel)),
        c.usableNow and "" or ("  " .. T.Wrap("muted", "soon")),
        c.how and c.how.t == "drop" and ("  " .. T.Wrap("drop", "pattern drops")) or ""),
      right = ("+%.1f"):format(c.gain),
      onClick = function() ns.GearToast.OpenRecipe(c) end }
  end
  if #upgrades == 0 then rows[#rows + 1] = { text = "No craftable upgrades right now." } end
  return rows
end

local function equippedScores(weights)
  local scores, totals = {}, {}
  if not GetInventoryItemLink then return scores, totals end
  for _, inv in pairs(SLOT_TO_INV) do
    local link = GetInventoryItemLink("player", inv)
    local fn = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
    if link and fn then
      local ok, st = pcall(fn, link)
      if ok and st then
        for k, v in pairs(st) do totals[k] = (totals[k] or 0) + v end
        if weights then scores[inv] = ns.Gear.Score(st, weights) end
      end
    end
  end
  return scores, totals
end

function GF.Compute(ds)
  local me = ns.Game.PlayerInfo()
  local profs = {}
  for line, p in pairs(ns.Game.Professions()) do profs[line] = p.rank end
  for _, c in pairs(ns.db.chars or {}) do
    for line, rank in pairs(c.profs or {}) do
      if not profs[line] or rank > profs[line] then profs[line] = rank end
    end
  end
  local scorer = ns.Pawn.Scorer()
  local equipped
  local _, totals = equippedScores(nil)
  local weights = ns.Gear.AutoWeights(me.class, totals)
  if not scorer then
    local byInv = equippedScores(weights)
    equipped = {}
    for slot, inv in pairs(SLOT_TO_INV) do equipped[slot] = byInv[inv] end
  end
  local known = {}
  for _, set in pairs(ns.cdb.known or {}) do for id in pairs(set) do known[id] = true end end
  local ups = ns.Gear.Candidates(ds, { profs = profs, level = me.level, class = me.class, known = known,
    weights = weights, scorer = scorer, stats = ns.Game.ItemStats, equipped = equipped,
    side = ns.Game.Faction(), drops = true })
  return ups, scorer ~= nil
end

function GF.Show()
  local ds = ns.ActiveDataset()
  if not ds then ns.Log("warn", "no dataset; see /profs status"); return end
  local W = ns.Widgets
  if not GF.frame then
    local f = W.Window("ProfsGear", ns.displayName .. " - Craftable upgrades", 440, 420, { point = { "CENTER", -200, 0 } })
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 12, f.top)
    body:SetPoint("BOTTOMRIGHT", -12, 12)
    body:SetSize(410, 330)
    f.list = W.List(body, 20, ns.Theme.ROW_HEIGHT, 410)
    f.list:SetEmptyText("No craftable upgrades right now.")
    GF.frame = f
  end
  local ups, pawn = GF.Compute(ds)
  GF.frame.list:Set(GF.Format(ds, ups, pawn))
  GF.frame:Show()
end

