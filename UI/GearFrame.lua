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
  -- usingPawn: the scoring label (PW.Scoring().label), or true/false from older callers
  local label = type(usingPawn) == "table" and usingPawn.label or type(usingPawn) == "string" and usingPawn
    or (usingPawn and "Scored by Pawn" or "Scored by built-in automatic weights")
  local rows = { { summary = true, text = T.Wrap("gold", label) } }
  -- the same slot-grouped rows as the character-frame column
  for _, row in ipairs(ns.GearColumn.Rows(ds, upgrades)) do rows[#rows + 1] = row end
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

-- What scores gear for this character: { me, scoring, weights, equipped, known, side }.
function GF.Context()
  local me = ns.Game.PlayerInfo()
  local scoring = ns.Pawn.Scoring()
  local equipped
  local _, totals = equippedScores(nil)
  local weights = ns.Gear.AutoWeights(me.class, totals, scoring.spec)
  if not scoring.scorer then
    local byInv = equippedScores(weights)
    equipped = {}
    for slot, inv in pairs(SLOT_TO_INV) do equipped[slot] = byInv[inv] end
  end
  local known = {}
  for _, set in pairs(ns.cdb.known or {}) do for id in pairs(set) do known[id] = true end end
  return { me = me, scoring = scoring, weights = weights, equipped = equipped, known = known,
    side = ns.Game.Faction() }
end

-- Craftable upgrades. profs = { [skillLine] = skill } (default: this character's and the
-- alts' professions); opts.lookahead, opts.drops (default true), opts.ctx (GF.Context()).
function GF.Compute(ds, profs, opts)
  opts = opts or {}
  local ctx = opts.ctx or GF.Context()
  if not profs then
    profs = {}
    for line, p in pairs(ns.Game.Professions()) do profs[line] = p.rank end
    for _, c in pairs(ns.db.chars or {}) do
      for line, rank in pairs(c.profs or {}) do
        if not profs[line] or rank > profs[line] then profs[line] = rank end
      end
    end
  end
  local ups = ns.Gear.Candidates(ds, { profs = profs, level = ctx.me.level, class = ctx.me.class,
    known = ctx.known, weights = ctx.weights, scorer = ctx.scoring.scorer, stats = ns.Game.ItemStats,
    equipped = ctx.equipped, side = ctx.side, drops = opts.drops ~= false, lookahead = opts.lookahead })
  return ups, ctx.scoring
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

