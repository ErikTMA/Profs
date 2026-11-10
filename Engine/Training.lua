-- Trainer offers: what the planned routes still need from a trainer (recipes whose
-- cheapest source is a trainer, and rank training), matched against the services the
-- open trainer lists. Pure: the UI (UI/TrainerPrompt.lua) reads the trainer.
local _, ns = ...
local TR = ns:NewModule("Training")

-- What a route still wants from a trainer: { recipes = {[name] = recipeId},
-- ranks = {[rankName] = true}, name = profession name }. Saved per profession
-- (ProfsCharDB.trainList) whenever a route is planned, so a trainer visit without the
-- profession window open still knows what you need.
function TR.Wanted(ds, route, prof)
  local out = { recipes = {}, ranks = {}, name = ns.Professions.Name(prof) }
  for _, seg in ipairs(route and route.segments or {}) do
    local a = seg.acquire
    local r = ds.recipes[seg.recipe]
    if a and a.t == "trainer" and r and r.name then out.recipes[r.name] = seg.recipe end
  end
  for _, t in ipairs(route and route.training or {}) do out.ranks[t.rank] = true end
  return out
end

local function lower(s) return type(s) == "string" and s:lower() or "" end

-- services = { {index, name, subText, type, cost}, ... } as the trainer lists them;
-- wanted = { [prof] = TR.Wanted(...) }. Returns the services you can learn now
-- (type "available") that a route needs, in trainer order:
-- { index, name, cost, prof, recipe | rank }.
function TR.Match(services, wanted)
  local out = {}
  for _, s in ipairs(services or {}) do
    if s.type == "available" and s.name then
      for prof, w in pairs(wanted or {}) do
        local recipe = w.recipes and w.recipes[s.name]
        local rank
        if not recipe and w.name then
          -- rank rows read "Leatherworking (Journeyman)" or "Journeyman Leatherworking"
          local text = lower(s.name) .. " " .. lower(s.subText)
          if text:find(lower(w.name), 1, true) then
            for r in pairs(w.ranks or {}) do
              if text:find(lower(r), 1, true) then rank = r; break end
            end
          end
        end
        if recipe or rank then
          out[#out + 1] = { index = s.index, name = s.name, cost = s.cost or 0, prof = prof,
            recipe = recipe, rank = rank }
          break
        end
      end
    end
  end
  return out
end

-- The offers you can pay for, cheapest first until the money runs out.
-- Returns picked (in trainer order), total cost, skipped (too expensive).
function TR.Affordable(offers, money)
  local byCost = {}
  for i, o in ipairs(offers) do byCost[i] = o end
  table.sort(byCost, function(a, b)
    if a.cost ~= b.cost then return a.cost < b.cost end
    return a.index < b.index
  end)
  local take, total, skipped = {}, 0, {}
  for _, o in ipairs(byCost) do
    if total + o.cost <= (money or math.huge) then
      take[o] = true; total = total + o.cost
    else
      skipped[#skipped + 1] = o
    end
  end
  local picked = {}
  for _, o in ipairs(offers) do if take[o] then picked[#picked + 1] = o end end
  return picked, total, skipped
end
