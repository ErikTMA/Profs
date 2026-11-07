-- Disenchant yield FALLBACK table, used only when the dataset has no measured yield
-- (items[id].de, exported from the item pages' disenchanting relation).
--
-- SOURCE: the community-documented Classic Era table (uncommon armor; weapons swap
-- the dust/essence odds). Confidence LOW for WoW Forever: unverified. Results that
-- come from this table are tagged `estimated=true` so the UI can say so.
local _, ns = ...
local D = ns:NewModule("DisenchantTable")

-- dust, lesser/greater essence, shard (item ids)
local BANDS = {
  -- maxIlvl, reqEnchanting, dust{id,min,max}, essence{id,min,max}, shard id (or nil)
  { 15, 1,   { 10940, 1, 2 }, { 10938, 1, 2 }, nil },
  { 20, 1,   { 10940, 2, 3 }, { 10939, 1, 2 }, 10978 },
  { 25, 25,  { 10940, 4, 6 }, { 10998, 1, 2 }, 10978 },
  { 30, 50,  { 11083, 1, 2 }, { 11082, 1, 2 }, 11084 },
  { 35, 75,  { 11083, 2, 5 }, { 11134, 1, 2 }, 11138 },
  { 40, 100, { 11137, 1, 2 }, { 11135, 1, 2 }, 11139 },
  { 45, 125, { 11137, 2, 5 }, { 11174, 1, 2 }, 11177 },
  { 50, 150, { 11176, 1, 2 }, { 11175, 1, 2 }, 11178 },
  { 55, 175, { 11176, 2, 5 }, { 16202, 1, 2 }, 14343 },
  { 60, 200, { 16204, 1, 2 }, { 16203, 1, 2 }, 14344 },
  { 65, 225, { 16204, 2, 5 }, { 16203, 2, 3 }, 14344 },
}

local WEAPON_CLASS = 2
local ARMOR_CLASS = 4
local UNCOMMON = 2

-- Returns yields { {itemId, chance, min, max}, ... }, requiredSkill, or nil when the
-- item cannot be disenchanted per this table (non-green, non-gear, out of range).
function D.Estimate(item)
  if not item or item.q ~= UNCOMMON then return nil end
  if item.c ~= WEAPON_CLASS and item.c ~= ARMOR_CLASS then return nil end
  local il = item.il or 0
  for _, b in ipairs(BANDS) do
    if il <= b[1] then
      local dust, ess, shard = b[3], b[4], b[5]
      local pd, pe = 0.75, 0.20
      if item.c == WEAPON_CLASS then pd, pe = 0.20, 0.75 end
      local pShard = shard and 0.05 or 0
      if not shard then pd, pe = pd / (pd + pe), pe / (pd + pe) end
      local out = {
        { dust[1], pd, dust[2], dust[3] },
        { ess[1], pe, ess[2], ess[3] },
      }
      if shard then out[3] = { shard, pShard, 1, 1 } end
      return out, b[2]
    end
  end
  return nil
end
