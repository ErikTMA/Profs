-- Gathering guide (Herbalism, Mining, Skinning): where to gather for each skill bracket.
--
-- DATA. ds.nodes[objectId] = { n, prof, skill, yields, spawns = { [uiMapId] = {xxxyyy} } }
-- (every spawn Wowhead lists, in tenths of a percent), ds.zones[uiMapId] = { n, lv, na, nh,
-- nb }. Skinnable mobs are Skinning's nodes, keyed -npcId, with lv = {lo, hi} and the
-- skill their level needs (1.x: 1 to level 10, (level - 10) * 10 to 20, then level * 5). Extra points (the player's own GatherMate2 nodes, Adapters/GatherMate.lua) are
-- merged in; a point within GA.SAME of a known spawn of the same node is the same spawn.
--
-- AREAS. Spawns are grouped per zone: for every node type, the densest circles of radius
-- GA.RADIUS_YARDS (GA.RADIUS_PCT of the map when the zone's size is unknown) are found
-- greedily on a grid; circles closer than one radius to a better one are dropped. An area
-- then counts EVERY spawn of the profession inside its circle, so one area can serve
-- several skill brackets (copper and tin side by side).
--
-- SKILL-UPS. A node of required skill k is orange until k+25, yellow until k+50, green
-- until k+100, grey from k+100 (the 1.x rule), with SkillUp's chance model. An area's
-- value at skill s is the expected skill-ups of one pass over it: sum(count * chance).
-- Gathers per point = 1 / (mean chance over the spawns you can gather there).
--
-- PLAN. For every point from the current skill to the target the best area wins, scaled
-- by GA.Factor (mobs above your level: the area's own mobs for Skinning, else the
-- zone's; the other faction's zone). The current area is
-- kept while it scores at least GA.KEEP of the best, so the guide does not hop between
-- two zones of near-equal value. Rank training steps are the Optimizer's.
local _, ns = ...
local GA = ns:NewModule("Gathering")

GA.PROFS = { [182] = true, [186] = true, [393] = true }
GA.NOUN = { [182] = "herbs", [186] = "nodes", [393] = "mobs" }
GA.RADIUS_YARDS = 250
GA.RADIUS_PCT = 8
GA.MIN_NODES = 6       -- an area holds at least this many spawns of its node type
GA.MAX_AREAS = 3       -- per node type and zone
GA.SAME = 1.0          -- percent: an extra point this close to a spawn of the node is it
GA.KEEP = 0.8
GA.ENEMY = 0.1         -- the other faction's zone: only when nothing friendly or neutral serves
GA.AWAY = 0.6
-- Skinning: you kill each mob first, so past this many mobs in reach an area is no
-- faster; denser areas compete on how many of their mobs give skill-ups, then on travel
GA.SATURATE = { [393] = 50 }          -- an area on another continent than you (first step) or the last step
GA.MIN_STEP = 10       -- skill points: a shorter step is folded into a neighbour
GA.BANDS = { 25, 50, 100 } -- orange, yellow, green widths above the required skill

-- { learn, colors } of a node: the SkillUp model's recipe shape.
function GA.Colors(node)
  local k = node.skill or 1
  return { learn = k, colors = { k, k + GA.BANDS[1], k + GA.BANDS[2], k + GA.BANDS[3] } }
end

function GA.Chance(node, s) return ns.SkillUp.Chance(GA.Colors(node), s) end
function GA.Color(node, s) return ns.SkillUp.Color(GA.Colors(node), s) end

function GA.Unpack(v) return math.floor(v / 1000) / 10, (v % 1000) / 10 end

-- Node ids of a profession, sorted by required skill then id.
function GA.NodesOf(ds, prof)
  local out = {}
  for id, n in pairs(ds.nodes or {}) do
    if n.prof == prof then out[#out + 1] = id end
  end
  table.sort(out, function(a, b)
    local x, y = ds.nodes[a], ds.nodes[b]
    if x.skill ~= y.skill then return x.skill < y.skill end
    return a < b
  end)
  return out
end

-- Points per zone: { [uiMapId] = { {x, y, node, own}, ... } }, and how many extra points
-- were new. extra = { {zone, x, y, node}, ... } (percent coordinates, a node id of ds).
function GA.Points(ds, prof, extra)
  local byZone = {}
  local index = {} -- zone -> "cx:cy" -> list (1% cells) for the dedupe of extra points
  local function add(zone, x, y, node, own)
    local list = byZone[zone]
    if not list then list = {}; byZone[zone] = list; index[zone] = {} end
    local p = { x = x, y = y, node = node, own = own or nil }
    list[#list + 1] = p
    local key = math.floor(x) .. ":" .. math.floor(y)
    local cell = index[zone][key]
    if not cell then cell = {}; index[zone][key] = cell end
    cell[#cell + 1] = p
  end
  for _, id in ipairs(GA.NodesOf(ds, prof)) do
    for zone, list in pairs(ds.nodes[id].spawns or {}) do
      for _, v in ipairs(list) do
        local x, y = GA.Unpack(v)
        add(zone, x, y, id)
      end
    end
  end
  local new = 0
  for _, e in ipairs(extra or {}) do
    local nd = ds.nodes[e.node]
    if nd and nd.prof == prof and e.zone and e.x and e.y then
      local known = false
      local cells = index[e.zone]
      if cells then
        local cx, cy = math.floor(e.x), math.floor(e.y)
        for dx = -1, 1 do
          for dy = -1, 1 do
            for _, p in ipairs(cells[(cx + dx) .. ":" .. (cy + dy)] or {}) do
              if not known and ds.nodes[p.node].n == nd.n
                  and (p.x - e.x) ^ 2 + (p.y - e.y) ^ 2 <= GA.SAME * GA.SAME then
                known = true
                p.seen = true
              end
            end
          end
        end
      end
      if not known then add(e.zone, e.x, e.y, e.node, true); new = new + 1 end
    end
  end
  return byZone, new
end

-- Dense circles of one zone. pts: the zone's points; sx, sy: units per map percent
-- (yards when the zone size is known, else 1); r: radius in those units.
local function zoneAreas(ds, zone, pts, sx, sy, r)
  local half = r / 2
  -- points in cells of size r/2, so a circle of radius r spans 5x5 cells
  local cells, byNode = {}, {}
  for i, p in ipairs(pts) do
    p.ux, p.uy = p.x * sx, p.y * sy
    local cx, cy = math.floor(p.ux / half), math.floor(p.uy / half)
    p.cx, p.cy = cx, cy
    local key = cx * 4096 + cy
    local c = cells[key]
    if not c then c = {}; cells[key] = c end
    c[#c + 1] = i
    local nd = byNode[p.node]
    if not nd then nd = {}; byNode[p.node] = nd end
    nd[#nd + 1] = i
  end
  local r2 = r * r
  local function inside(ux, uy, fn)
    local cx, cy = math.floor(ux / half), math.floor(uy / half)
    for dx = -2, 2 do
      for dy = -2, 2 do
        for _, i in ipairs(cells[(cx + dx) * 4096 + cy + dy] or {}) do
          local p = pts[i]
          if (p.ux - ux) ^ 2 + (p.uy - uy) ^ 2 <= r2 then fn(i, p) end
        end
      end
    end
  end
  local found = {}
  -- per node type (variants of one name share it): densest circles first
  local names = {}
  for id, list in pairs(byNode) do
    local name = ds.nodes[id].n
    names[name] = names[name] or {}
    for _, i in ipairs(list) do table.insert(names[name], i) end
  end
  for _, name in ipairs(ns.Util.sortedKeys(names)) do
    local mine = names[name]
    local isMine = {}
    for _, i in ipairs(mine) do isMine[i] = true end
    local claimed = {}
    for _ = 1, GA.MAX_AREAS do
      -- candidates: centres of the cells holding this node's unclaimed points
      local best, bestN, seen = nil, 0, {}
      for _, i in ipairs(mine) do
        local p = pts[i]
        local key = p.cx * 4096 + p.cy
        if not claimed[i] and not seen[key] then
          seen[key] = true
          local ux, uy = (p.cx + 0.5) * half, (p.cy + 0.5) * half
          local n = 0
          inside(ux, uy, function(j) if isMine[j] and not claimed[j] then n = n + 1 end end)
          if n > bestN or (n == bestN and best and (ux < best[1] or ux == best[1] and uy < best[2])) then
            best, bestN = { ux, uy }, n
          end
        end
      end
      if not best or bestN < GA.MIN_NODES then break end
      -- re-centre on the node's points inside, then claim them
      local mx, my, k = 0, 0, 0
      inside(best[1], best[2], function(j, p)
        if isMine[j] and not claimed[j] then mx, my, k = mx + p.ux, my + p.uy, k + 1 end
      end)
      local ux, uy = mx / k, my / k
      inside(best[1], best[2], function(j) if isMine[j] then claimed[j] = true end end)
      found[#found + 1] = { ux = ux, uy = uy, n = bestN }
    end
  end
  -- drop circles closer than r to a denser one
  table.sort(found, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    if a.ux ~= b.ux then return a.ux < b.ux end
    return a.uy < b.uy
  end)
  local kept = {}
  for _, c in ipairs(found) do
    local near = false
    for _, k in ipairs(kept) do
      if (k.ux - c.ux) ^ 2 + (k.uy - c.uy) ^ 2 < r2 then near = true; break end
    end
    if not near then kept[#kept + 1] = c end
  end
  local areas = {}
  for _, c in ipairs(kept) do
    local a = { zone = zone, x = c.ux / sx, y = c.uy / sy, counts = {}, total = 0, own = 0, points = {} }
    inside(c.ux, c.uy, function(_, p)
      a.counts[p.node] = (a.counts[p.node] or 0) + 1
      a.total = a.total + 1
      if p.own then a.own = a.own + 1 end
      a.points[#a.points + 1] = { p.x, p.y, p.node }
    end)
    -- per distinct required skill, for the planner's inner loop
    local bySkill = {}
    for id, n in pairs(a.counts) do
      local k = ds.nodes[id].skill or 1
      bySkill[k] = (bySkill[k] or 0) + n
    end
    a.skills = {}
    for _, k in ipairs(ns.Util.sortedKeys(bySkill)) do a.skills[#a.skills + 1] = { k, bySkill[k] } end
    -- mobs (Skinning): their typical level, the spawn-weighted mean of the lowest levels
    local lsum, ln = 0, 0
    for id, n in pairs(a.counts) do
      local lv = ds.nodes[id].lv
      if lv then lsum, ln = lsum + lv[1] * n, ln + n end
    end
    if ln > 0 then a.mobLevel = math.floor(lsum / ln + 0.5) end
    areas[#areas + 1] = a
  end
  return areas
end

-- Areas of a profession. opts.extra (see GA.Points), opts.size(uiMapId) -> width,
-- height in yards (nil = unknown: percent radius), opts.skipZone(uiMapId) -> true to
-- leave a zone out (instances). Returns the list (zone, then west to east) and the
-- number of extra points that were new.
function GA.Areas(ds, prof, opts)
  opts = opts or {}
  local byZone, new = GA.Points(ds, prof, opts.extra)
  local out = {}
  for _, zone in ipairs(ns.Util.sortedKeys(byZone)) do
    if not (opts.skipZone and opts.skipZone(zone)) then
      local w, h
      if opts.size then w, h = opts.size(zone) end
      local sx, sy, r = 1, 1, GA.RADIUS_PCT
      if w and h and w > 0 and h > 0 then sx, sy, r = w / 100, h / 100, GA.RADIUS_YARDS end
      for _, a in ipairs(zoneAreas(ds, zone, byZone[zone], sx, sy, r)) do
        a.yards = r ~= GA.RADIUS_PCT and r or nil
        out[#out + 1] = a
      end
    end
  end
  return out, new
end

-- Expected skill-ups of one pass over the area at skill s, and how many of its spawns
-- you can gather at all.
function GA.Score(a, s)
  local sum, usable = 0, 0
  for _, e in ipairs(a.skills) do
    local k, n = e[1], e[2]
    if s >= k then
      usable = usable + n
      local yellow, grey = k + GA.BANDS[1], k + GA.BANDS[3]
      if s < yellow then sum = sum + n
      elseif s < grey then sum = sum + n * (grey - s) / (grey - yellow) end
    end
  end
  return sum, usable
end

-- "A" | "H" | nil (contested or unknown) from the zone's friendly npcs: one faction's
-- npcs outnumber the other's GA.SIDE_RATIO to 1. Measured on the forever data
-- (Alliance-only / Horde-only friendly npcs): Silverpine Forest 23 / 39 (Horde), the
-- Barrens 16 / 99 (Horde), Hillsbrad Foothills 63 / 42 and Ashenvale 84 / 58
-- (contested: both have a town there), Elwynn Forest 141 / 0 (Alliance).
GA.SIDE_RATIO = 1.6
function GA.ZoneSide(z)
  if not z then return nil end
  local a, h = z.na or 0, z.nh or 0
  if a >= 5 and a >= GA.SIDE_RATIO * h then return "A" end
  if h >= 5 and h >= GA.SIDE_RATIO * a then return "H" end
  return nil
end

-- Multiplier on an area's value for this character, and why it was lowered:
-- "level" (mobs above you: mobLevel, the area's own mobs, else the zone's lowest),
-- "enemy" (the other faction's zone).
function GA.Factor(z, level, side, mobLevel)
  local f, why = 1, {}
  local lv = mobLevel or (z and z.lv and z.lv[1])
  if lv and level then
    if level < lv - 3 then f = f * 0.25; why[#why + 1] = "level"
    elseif level < lv then f = f * 0.7; why[#why + 1] = "level" end
  end
  local zs = GA.ZoneSide(z)
  if side and zs and zs ~= side then f = f * GA.ENEMY; why[#why + 1] = "enemy" end
  return f, why
end

-- The continent of a uiMap: 1414 Kalimdor, 1415 Eastern Kingdoms (the 1.x zone maps;
-- the UI passes opts.continentOf for maps not listed, from C_Map's parents).
GA.CONTINENT = {}
for _, z in ipairs({ 1411, 1412, 1413, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446,
  1447, 1448, 1449, 1450, 1451, 1452, 1454, 1456, 1457 }) do GA.CONTINENT[z] = 1414 end
for z = 1416, 1437 do GA.CONTINENT[z] = 1415 end
GA.CONTINENT[1430] = nil -- not a zone map

-- The guide from skill `from` to `to`. opts.areas (GA.Areas), opts.level, opts.side,
-- opts.continent (where you are: the first step prefers it), opts.continentOf(uiMapId).
-- Returns { prof, from, to, steps = { {from, to, area, gathers, why} }, ranks,
-- warnings, unreachable }.
function GA.Plan(ds, prof, from, to, opts)
  opts = opts or {}
  local areas = opts.areas or GA.Areas(ds, prof, opts)
  local zones = ds.zones or {}
  local factor, why = {}, {}
  for i, a in ipairs(areas) do factor[i], why[i] = GA.Factor(zones[a.zone], opts.level, opts.side, a.mobLevel) end
  local cont = {}
  for i, a in ipairs(areas) do
    cont[i] = GA.CONTINENT[a.zone] or (opts.continentOf and opts.continentOf(a.zone)) or false
  end
  local plan = { prof = prof, from = from, to = to, steps = {} }
  local cur, step
  local here = opts.continent
  -- near: staying on the continent you are on (then: of the last step) is worth more
  local cap = GA.SATURATE[prof]
  local function value(i, s)
    local v, usable = GA.Score(areas[i], s)
    if cap and usable > cap then v = v * cap / usable end
    v = v * factor[i]
    if here and cont[i] and cont[i] ~= here then v = v * GA.AWAY end
    return v
  end
  for s = from, to - 1 do
    local best, bestV = nil, 0
    for i in ipairs(areas) do
      local v = value(i, s)
      if v > bestV then best, bestV = i, v end
    end
    if not best then plan.unreachable = s; break end
    if cur and cur ~= best and value(cur, s) >= GA.KEEP * bestV then best = cur end
    here = cont[best] or here
    local sum, usable = GA.Score(areas[best], s)
    if best ~= cur then
      cur = best
      step = { from = s, to = s, area = areas[best], gathers = 0, why = why[best] }
      plan.steps[#plan.steps + 1] = step
    end
    step.to = s + 1
    step.gathers = step.gathers + usable / sum
  end
  GA.FoldShort(plan.steps)
  local ranks, warnings = ns.Optimizer.TrainingSteps(ds, prof, from, plan.unreachable or to, opts.level)
  plan.ranks, plan.warnings = ranks, warnings
  return plan
end

-- Expected gathers in area `a` from s0 to s1, or nil when it gives no skill-up on the way.
function GA.Gathers(a, s0, s1)
  local g = 0
  for s = s0, s1 - 1 do
    local sum, usable = GA.Score(a, s)
    if sum <= 0 then return nil end
    g = g + usable / sum
  end
  return g
end

-- A step shorter than GA.MIN_STEP points is a detour: its range goes to the neighbour
-- that covers it with fewer gathers (a neighbour must give skill-ups all the way), then
-- neighbours in one area become one step.
function GA.FoldShort(steps)
  local i = 1
  while i <= #steps do
    local st, prev, nxt = steps[i], steps[i - 1], steps[i + 1]
    local folded = false
    if #steps > 1 and st.to - st.from < GA.MIN_STEP then
      local gp = prev and GA.Gathers(prev.area, st.from, st.to)
      local gn = nxt and GA.Gathers(nxt.area, st.from, st.to)
      if gp and (not gn or gp <= gn) then
        prev.to, prev.gathers = st.to, prev.gathers + gp
        folded = true
      elseif gn then
        nxt.from, nxt.gathers = st.from, nxt.gathers + gn
        folded = true
      end
    end
    if folded then table.remove(steps, i) else i = i + 1 end
  end
  i = 2
  while i <= #steps do
    local a, b = steps[i - 1], steps[i]
    if a.area == b.area then
      a.to, a.gathers = b.to, a.gathers + b.gathers
      table.remove(steps, i)
    else
      i = i + 1
    end
  end
  return steps
end

-- The plan's step for skill s (nil when s is outside it).
function GA.StepAt(plan, s)
  for i, st in ipairs(plan.steps) do
    if s >= st.from and s < st.to then return st, i end
  end
  return nil
end

-- Node lines of an area at skill s: { {name, skill, count, color, ids} } by required
-- skill; variants of one name are merged.
function GA.Composition(ds, a, s)
  local byName, order = {}, {}
  for id, n in pairs(a.counts) do
    local nd = ds.nodes[id]
    local e = byName[nd.n]
    if not e then
      e = { name = nd.n, skill = nd.skill, count = 0, color = s and GA.Color(nd, s), ids = {}, node = id,
        lv = nd.lv and { nd.lv[1], nd.lv[2] } }
      byName[nd.n] = e
      order[#order + 1] = e
    end
    e.count = e.count + n
    e.ids[#e.ids + 1] = id
    if nd.lv and e.lv then e.lv[1], e.lv[2] = math.min(e.lv[1], nd.lv[1]), math.max(e.lv[2], nd.lv[2]) end
    if id < e.node then e.node = id end
  end
  table.sort(order, function(x, y)
    if x.skill ~= y.skill then return x.skill < y.skill end
    return x.name < y.name
  end)
  return order
end

-- Trainers of a gathering profession usable by `side`, best access first.
function GA.Trainers(ds, prof, side)
  local p = ds.professions and ds.professions[prof]
  local _, shown = ns.Faction.Source(ds.npcs, { npcs = p and p.trainers or {} }, side)
  return shown
end
