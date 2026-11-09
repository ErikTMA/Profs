-- The nearest vendor you can buy an item from (the item tooltip line, UI/VendorTooltip).
--
-- DATA. ds.sold[itemId] = { npcId, ... }: every located vendor selling it for gold with
-- no reputation needed; ds.npcs[npcId] = { n, zone, x, y, m = uiMapId, fa, fh }.
-- Only vendors friendly or neutral to you count (Engine/Faction "ok": never hostile, never
-- behind the other faction's capital guards).
--
-- DISTANCE. opts.world(uiMapId, x, y) -> continentId, worldX, worldY (yards; the UI
-- passes C_Map.GetWorldPosFromMapPos) and opts.here = { continent, x, y } (where you
-- stand, same units). Straight-line yards on your continent; a vendor on another
-- continent, or any vendor when your position is unknown, has no distance and only
-- wins when no vendor on your continent sells the item.
local _, ns = ...
local V = ns:NewModule("Vendors")

-- Returns { id, npc, yards | nil, elsewhere = true when on another continent } and how
-- many vendors you can use sell it; nil, 0 when none (or the item is not sold).
function V.Nearest(ds, itemId, opts)
  local list = ds and ds.sold and ds.sold[itemId]
  if not list then return nil, 0 end
  opts = opts or {}
  local here, world = opts.here, opts.world
  local best, bestYards, fallback, n = nil, nil, nil, 0
  for _, id in ipairs(list) do
    local npc = ds.npcs and ds.npcs[id]
    if npc and npc.m and npc.x and npc.y and ns.Faction.Access(npc, opts.side) == "ok" then
      n = n + 1
      local cont, wx, wy
      if here and world then cont, wx, wy = world(npc.m, npc.x, npc.y) end
      if cont and cont == here.continent and wx and wy then
        local d = math.sqrt((wx - here.x) ^ 2 + (wy - here.y) ^ 2)
        if not bestYards or d < bestYards or (d == bestYards and id < best.id) then
          best, bestYards = { id = id, npc = npc, yards = d }, d
        end
      elseif not fallback or id < fallback.id then
        fallback = { id = id, npc = npc, elsewhere = (here and cont and true) or nil }
      end
    end
  end
  return best or fallback, n
end

-- "120 yd" / "1,450 yd"
function V.FormatYards(y)
  local s = tostring(math.floor(y + 0.5))
  local k
  repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
  return s .. " yd"
end
