-- Optional Pawn integration for the gear helper. Uses Pawn's global functions only
-- when present (PawnGetItemData + PawnIsItemAnUpgrade); otherwise the built-in
-- automatic weights in Engine/Gear.lua apply. Every call is pcall-guarded: a Pawn
-- build with a different signature degrades to the fallback, never to an error.
local _, ns = ...
local PW = ns:NewModule("Pawn")

function PW.Available()
  return type(PawnGetItemData) == "function" and type(PawnIsItemAnUpgrade) == "function"
end

-- scorer(itemId) -> upgrade percent (0 when not an upgrade), nil when Pawn cannot say.
function PW.Scorer()
  if not PW.Available() then return nil end
  return function(itemId)
    local _, link = ns.Game.ItemName(itemId)
    if not link then return nil end
    local ok, data = pcall(PawnGetItemData, link)
    if not ok or not data then return nil end
    local ok2, upgrades = pcall(PawnIsItemAnUpgrade, data)
    if not ok2 then return nil end
    local best = 0
    if type(upgrades) == "table" then
      for _, u in pairs(upgrades) do
        if type(u) == "table" and type(u.PercentUpgrade) == "number" and u.PercentUpgrade > best then
          best = u.PercentUpgrade
        end
      end
    end
    return best * 100
  end
end
