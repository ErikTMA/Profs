-- Who can use which NPC (trainers and recipe vendors), per player faction.
--
-- DATA (audited 2026-11-07, forever dataset): each NPC carries its reaction to each
-- faction, fa (Alliance) and fh (Horde): 1 friendly, 0 neutral (yellow; can be
-- talked to, e.g. Steamwheedle and Thorium Brotherhood NPCs), -1 hostile, ABSENT when
-- the data does not say; friendly to one faction with the other ABSENT means hostile
-- to the other (see F.Reaction). Older datasets only have side = "A" | "H" | "B" (friendly to
-- Alliance / Horde / both), which cannot tell neutral or unknown from hostile, so for
-- them only "friendly" is ever concluded and everything else stays unknown.
--
-- ACCESS for the player's side ("A" or "H"):
--   ok         friendly or neutral to you, and not inside the other faction's capital
--   unknown    the data does not say, or your faction could not be read; shown, but
--              labelled and never claimed accessible
--   territory  not known to be friendly, inside the other faction's capital (its guards
--              make it unreachable whatever the NPC's own reaction)
--   hostile    hostile to your faction (an Alliance-only trainer for a Horde player)
-- Suggestions use ok first, then unknown; territory and hostile NPCs are never offered.
local _, ns = ...
local F = ns:NewModule("Faction")

F.CAPITALS = {
  A = { ["Stormwind City"] = true, ["Ironforge"] = true, ["Darnassus"] = true, ["The Exodar"] = true },
  H = { ["Orgrimmar"] = true, ["Thunder Bluff"] = true, ["Undercity"] = true, ["Silvermoon City"] = true },
}
F.RANK = { ok = 1, unknown = 2, territory = 3, hostile = 4 }
F.NAME = { A = "Alliance", H = "Horde" }

-- "Alliance"/"Horde" (UnitFactionGroup) -> "A"/"H"; anything else -> nil (unknown).
function F.Side(group)
  if group == "Alliance" then return "A" end
  if group == "Horde" then return "H" end
  return nil
end

local function enemy(side) return side == "A" and "H" or "A" end

-- Reaction of an NPC to a side: 1, 0, -1 or nil (unknown).
function F.Reaction(npc, side)
  if not npc or not side then return nil end
  local v = npc[side == "A" and "fa" or "fh"]
  if v ~= nil then return v end
  local other = npc[side == "A" and "fh" or "fa"]
  -- friendly to the other faction and silent about yours: that faction's own NPC.
  -- Wowhead omits the second reaction for faction NPCs (808 of 1,308 trainers and
  -- vendors in the forever data: all of Stormwind, Orgrimmar, Mulgore...), while
  -- NPCs friendly to both list both (Booty Bay, Gadgetzan, Moonglade).
  if other == 1 then return -1 end
  if npc.fa ~= nil or npc.fh ~= nil then return nil end   -- new data, this side unknown
  -- legacy side letter: only "friendly" can be concluded from it
  if npc.side == "B" or npc.side == side then return 1 end
  return nil
end

-- ok | unknown | territory | hostile for one NPC record.
function F.Access(npc, side)
  if not side or not npc then return "unknown" end
  local r = F.Reaction(npc, side)
  if r == -1 then return "hostile" end
  local inEnemyCapital = npc.zone and F.CAPITALS[enemy(side)][npc.zone]
  if r == 1 then return "ok" end     -- friendly NPCs exist only where you can reach them
  if inEnemyCapital then return "territory" end
  if r == 0 then return "ok" end
  return "unknown"
end

-- Best access over a source's NPCs, and those NPCs sorted for display (accessible
-- first, never territory/hostile). A source without NPCs (starter, drop, quest, or a
-- trainer the data names no NPC for) has no NPC to check: "none".
function F.Source(npcs, src, side)
  local list = src and src.npcs
  if not list or #list == 0 then return "none", {} end
  local best, shown = nil, {}
  for _, id in ipairs(list) do
    local a = F.Access(npcs and npcs[id], side)
    if not best or F.RANK[a] < F.RANK[best] then best = a end
    if a == "ok" or a == "unknown" then shown[#shown + 1] = { id = id, access = a } end
  end
  table.sort(shown, function(x, y)
    if x.access ~= y.access then return F.RANK[x.access] < F.RANK[y.access] end
    return x.id < y.id
  end)
  return best, shown
end
