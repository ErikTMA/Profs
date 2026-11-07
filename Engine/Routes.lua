-- Persistent targets, saved routes, overrides and the guided-crafting state.
-- Pure: operates on the SavedVariables tables handed in (ProfsDB / ProfsCharDB).
local _, ns = ...
local RT = ns:NewModule("Routes")

RT.DB_VERSION = 1

function RT.InitDB(db)
  db = db or {}
  db.version = db.version or RT.DB_VERSION
  db.saved = db.saved or {}          -- [name] = { prof, from, to, mode, overrides, created }
  db.chars = db.chars or {}          -- [charKey] = { name, class, profs={[id]=skill}, items={[id]=n} }
  db.settings = db.settings or {}
  db.ah = db.ah or {}              -- [realm|faction] = native AH scan prices (Engine/AHPrices)
  return db
end

function RT.InitChar(cdb)
  cdb = cdb or {}
  cdb.targets = cdb.targets or {}    -- [profId] = { to, mode }
  cdb.overrides = cdb.overrides or {} -- [profId] = { exclude={[id]=true}, locks={...} }
  return cdb
end

function RT.SetTarget(cdb, profId, to, mode)
  assert(ns.Optimizer.MODES[mode or "cheapest"], "bad mode")
  cdb.targets[profId] = { to = to, mode = mode or "cheapest" }
end

function RT.Overrides(cdb, profId)
  local o = cdb.overrides[profId]
  if not o then o = { exclude = {}, locks = {} }; cdb.overrides[profId] = o end
  return o
end

function RT.Exclude(cdb, profId, recipeId, on)
  RT.Overrides(cdb, profId).exclude[recipeId] = on and true or nil
end

-- Lock [from, to) to one recipe; overlapping locks are replaced.
function RT.Lock(cdb, profId, from, to, recipeId)
  assert(to > from, "empty lock range")
  local o = RT.Overrides(cdb, profId)
  local keep = {}
  for _, l in ipairs(o.locks) do
    if l.to <= from or l.from >= to then keep[#keep + 1] = l end
  end
  keep[#keep + 1] = { from = from, to = to, recipe = recipeId }
  table.sort(keep, function(a, b) return a.from < b.from end)
  o.locks = keep
end

function RT.Unlock(cdb, profId, at)
  local o = RT.Overrides(cdb, profId)
  for i = #o.locks, 1, -1 do
    if at >= o.locks[i].from and at < o.locks[i].to then table.remove(o.locks, i) end
  end
end

function RT.Save(db, name, spec)
  assert(type(name) == "string" and name ~= "", "route name required")
  db.saved[name] = ns.Util.copy(spec)
end

function RT.Load(db, name) return db.saved[name] and ns.Util.copy(db.saved[name]) or nil end

function RT.Delete(db, name) db.saved[name] = nil end

function RT.List(db) return ns.Util.sortedKeys(db.saved) end

-- The part of a planned route still ahead at `skill` (from <= skill <= reach): what a
-- fresh plan from `skill` would show when you follow the route, without re-running the
-- optimizer. Finished segments are dropped; the current one starts at `skill` with its
-- expected crafts and gold recomputed for the rest of its range (its learn cost is
-- dropped once you are past its start: you have the recipe). Training steps still
-- ahead are recomputed. The input route is not modified.
function RT.Remaining(ds, route, skill, charLevel)
  if skill <= route.from then return route end
  local out = {}
  for k, v in pairs(route) do out[k] = v end
  out.from, out.segments = skill, {}
  out.totalCrafts, out.totalCost, out.acquireCost = 0, 0, 0
  for _, seg in ipairs(route.segments) do
    if seg.to > skill then
      local s = seg
      if seg.from < skill then
        local r = ds.recipes[seg.recipe]
        s = {}
        for k, v in pairs(seg) do s[k] = v end
        local crafts = ns.SkillUp.ExpectedCraftsRange(r, skill, seg.to)
        local craftGold = seg.gold - (seg.acquire and seg.acquire.cost or 0)
        s.from, s.crafts, s.acquire = skill, crafts, nil
        s.gold = seg.crafts > 0 and craftGold * crafts / seg.crafts or 0
        s.craftsCeil = math.ceil(crafts - 1e-9)
        s.colorAtStart = ns.SkillUp.Color(r, skill)
      end
      out.segments[#out.segments + 1] = s
      out.totalCrafts = out.totalCrafts + s.crafts
      out.totalCost = out.totalCost + s.gold
      if s.acquire then out.acquireCost = out.acquireCost + s.acquire.cost end
    end
  end
  local reach = route.unreachable or route.to
  out.training = ns.Optimizer.TrainingSteps(ds, route.prof, skill, reach, charLevel)
  for _, st in ipairs(out.training) do out.totalCost = out.totalCost + st.cost end
  return out
end

-- Guided crafting: where the player is on a route right now.
-- counts(itemId) -> how many the player has in bags (craftable reagents).
-- Returns nil when done, else { segment, index, remainingCrafts, craftable,
-- missing = {{itemId, n}}, color }.
function RT.Next(ds, route, skill, counts)
  for i, seg in ipairs(route.segments) do
    if skill < seg.to then
      if skill < seg.from then skill = seg.from end
      local r = ds.recipes[seg.recipe]
      local remaining = ns.SkillUp.ExpectedCraftsRange(r, skill, seg.to)
      local craftable = math.huge
      local missing = {}
      for _, rg in ipairs(r.reagents) do
        local have = counts and counts(rg[1]) or 0
        craftable = math.min(craftable, math.floor(have / rg[2]))
        local want = math.ceil(remaining - 1e-9) * rg[2]
        if have < want then missing[#missing + 1] = { rg[1], want - have } end
      end
      if craftable == math.huge then craftable = 0 end
      return { segment = seg, index = i, remainingCrafts = remaining,
        craftable = craftable, missing = missing, color = ns.SkillUp.Color(r, skill),
        batch = math.max(0, math.min(craftable, math.ceil(remaining - 1e-9))) }
    end
  end
  return nil
end
