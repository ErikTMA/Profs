-- Skill-up probability model.
--
-- A recipe carries four thresholds {orange, yellow, green, grey}. At skill s
-- (gaining s -> s+1):
--   s <  learn             cannot craft
--   s <  yellow            orange: a point is guaranteed (p = 1)
--   yellow <= s < grey     p = (grey - s) / (grey - yellow)   (yellow and green alike)
--   s >= grey              grey: p = 0
-- This is the commonly used model for 1.x-derived clients; it is an estimate, so the
-- optimizer works with EXPECTED crafts (1/p per point) and the UI labels them so.
local _, ns = ...
local SU = ns:NewModule("SkillUp")

SU.ORANGE, SU.YELLOW, SU.GREEN, SU.GREY = 1, 2, 3, 4

function SU.Color(recipe, s)
  local c = recipe.colors
  if s < (recipe.learn or c[1]) then return nil end
  if s < c[2] then return SU.ORANGE end
  if s < c[3] then return SU.YELLOW end
  if s < c[4] then return SU.GREEN end
  return SU.GREY
end

function SU.Chance(recipe, s)
  local c = recipe.colors
  if s < (recipe.learn or c[1]) then return 0 end
  if s < c[2] then return 1 end
  if s >= c[4] then return 0 end
  local span = c[4] - c[2]
  if span <= 0 then return 0 end
  return (c[4] - s) / span
end

-- Expected crafts to gain the single point s -> s+1 (math.huge when impossible).
-- A recipe granting k points per success still needs 1/p tries for that success;
-- we spread the tries across the k points it covers.
function SU.ExpectedCrafts(recipe, s)
  local p = SU.Chance(recipe, s)
  if p <= 0 then return math.huge end
  return 1 / (p * (recipe.skillups or 1))
end

-- Expected crafts from skill a up to b (exclusive) using one recipe.
function SU.ExpectedCraftsRange(recipe, a, b)
  local n = 0
  for s = a, b - 1 do
    n = n + SU.ExpectedCrafts(recipe, s)
  end
  return n
end
