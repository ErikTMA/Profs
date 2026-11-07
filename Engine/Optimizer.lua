-- Route optimizer: the cheapest (or fastest, or balanced) way from skill `from` to
-- skill `to` in one profession.
--
-- Model. Gaining point s -> s+1 with recipe r costs, in expectation,
--   crafts(r, s) = 1 / p(r, s)                            (Engine/SkillUp.lua)
--   gold(r, s)   = crafts(r, s) * (reagents(r, s) - recovery(r))
-- and learning r costs once (trainer fee, vendor price of the recipe item, 0 when
-- already known). A route is a sequence of segments [a, b) each using one recipe.
--
-- Search. Dynamic programming over skill levels with segment transitions:
--   best[b] = min over r, a < b of best[a] + acquire(r) + sum_{s=a}^{b-1} obj(r, s)
-- Every transition moves forward, so processing levels in increasing order makes
-- best[a] final before it is used. Cost is O(sum over recipes of window^2 / 2),
-- where window = the levels a recipe can still give points (learn .. grey); a few
-- hundred thousand steps for a full 1-300 profession. Acquisition is charged per
-- segment: a recipe reused in two non-adjacent segments pays twice (rare, because
-- a recipe's useful window is contiguous; the result is then slightly pessimistic,
-- never optimistic).
--
-- Objective per mode (units: copper, with crafts priced by weight):
--   cheapest  gold + 1c per craft (tie-break toward fewer crafts); recovery =
--             guaranteed vendor value only
--   fastest   crafts, gold only as a tie-break
--   balanced  gold + craftValue per craft (default 1s per craft)
local _, ns = ...
local O = ns:NewModule("Optimizer")

local INF = math.huge

O.MODES = { cheapest = true, fastest = true, balanced = true }

O.DEFAULTS = {
  mode = "cheapest",
  craftValue = 100,            -- balanced: copper one craft is worth
  limitedVendorPenalty = 2500, -- limited-stock vendor recipes: extra copper (+1 craft)
  unknownPrice = 10000,        -- copper per unit for an unpriced reagent (flagged)
  intermediates = true,        -- craft a reagent yourself when that is cheaper
  allowSources = { trainer = true, vendor = true, starter = true },
  unknownRecipeCost = 5000,    -- copper assumed for a vendor recipe whose price is unknown
  speculativeRecovery = false, -- count AH resale in the objective (never by default)
  allowCooldowns = false,      -- cooldown crafts (Mooncloth, transmutes) cannot be spammed
  specs = nil,                 -- { [specializationId] = true } the character has
}

local function weights(mode, opts)
  if mode == "fastest" then return 1e-6, 1 end
  if mode == "balanced" then return 1, opts.craftValue end
  return 1, 1
end

local function avgQty(r)
  local c = r.creates
  if not c then return 1 end
  local mn = c[2] or 1
  local mx = c[3] or mn
  return (mn + mx) / 2
end
O.AvgQty = avgQty

-- Faction access of a source for opts.side ("A"/"H"/nil) over opts.npcs (Engine/
-- Faction.lua). NPC-bound sources (trainer, vendor, reputation) whose every NPC is
-- hostile or only in an enemy capital are unavailable; a trainer/vendor the data names
-- no NPC for, or whose NPCs' faction is unknown, stays available as "unknown".
local NPC_BOUND = { trainer = true, vendor = true, reputation = true }
local function sourceAccess(s, opts)
  local a = ns.Faction.Source(opts.npcs, s, opts.side)
  if a == "none" then return NPC_BOUND[s.t] and "unknown" or "ok" end
  if a == "hostile" or a == "territory" then return nil end
  return a
end

-- Cheapest way to obtain a recipe, or nil when no allowed source exists.
-- Returns { t=sourceType, cost=copper, crafts=time-cost, source=src,
--           access="ok"|"unknown" }. Sources with confirmed access win over unknown
-- ones; then the cheapest.
function O.Acquisition(r, opts)
  if opts.known and opts.known[r.id] then return { t = "known", cost = 0, crafts = 0, access = "ok" } end
  local best
  for _, s in ipairs(r.sources or {}) do
    local access = (opts.allowSources[s.t] or opts.forced == r.id) and sourceAccess(s, opts)
    if access then
      local cost, crafts = s.cost or 0, 0
      if s.unknownCost and s.t == "vendor" then cost = opts.unknownRecipeCost end
      if s.t == "starter" then
        cost, crafts = 0, 0
      elseif s.t == "vendor" then
        crafts = 1
        if s.limited then
          cost = cost + opts.limitedVendorPenalty
          crafts = crafts + 1
        end
      elseif s.t ~= "trainer" and s.t ~= "starter" then
        crafts = 5 -- drops, quests, reputation: real effort even when allowed
      end
      local rank = ns.Faction.RANK[access]
      if not best or rank < best.rank or (rank == best.rank and (cost < best.cost
          or (cost == best.cost and crafts < best.crafts))) then
        best = { t = s.t, cost = cost, crafts = crafts, source = s, access = access, rank = rank }
      end
    end
  end
  return best
end

local Planner = {}
Planner.__index = Planner

function O.NewPlanner(ds, profId, opts)
  opts = ns.Util.merge(O.DEFAULTS, opts or {})
  opts.npcs = opts.npcs or ds.npcs
  assert(O.MODES[opts.mode], "unknown mode " .. tostring(opts.mode))
  local self = setmetatable({
    ds = ds,
    prof = profId,
    opts = opts,
    pricer = opts.pricer or ns.Pricing.New(ds),
    unit = {},       -- [itemId][level] = { cost, via, unpriced }
    acq = {},        -- [recipeId] = acquisition or false
    unpriced = {},   -- [itemId] = true
  }, Planner)
  self.wg, self.wc = weights(opts.mode, opts)
  return self
end

function Planner:Acquire(r)
  local a = self.acq[r.id]
  if a == nil then
    a = O.Acquisition(r, self.opts) or false
    self.acq[r.id] = a
  end
  return a or nil
end

-- Unit cost of an item at skill level k: buy it, or craft it from its own reagents
-- with a recipe of this profession that is known or trainer-taught and learnable at
-- k. Returns cost, viaRecipeId|nil.
function Planner:UnitCost(itemId, k, visiting)
  local byLevel = self.unit[itemId]
  if not byLevel then byLevel = {}; self.unit[itemId] = byLevel end
  local hit = byLevel[k]
  if hit then return hit[1], hit[2] end

  local buy = self.pricer:Buy(itemId)
  local best, via = buy, nil
  if self.opts.intermediates then
    visiting = visiting or {}
    if not visiting[itemId] then
      visiting[itemId] = true
      for _, p in ipairs(self.ds.producers[itemId] or {}) do
        if p.prof == self.prof and p.learn <= k and not (self.opts.exclude and self.opts.exclude[p.id]) then
          local a = self:Acquire(p)
          if a and (a.t == "known" or a.t == "trainer") then
            local total, ok = 0, true
            for _, rg in ipairs(p.reagents) do
              local c = self:UnitCost(rg[1], k, visiting)
              if not c then ok = false; break end
              total = total + c * rg[2]
            end
            if ok then
              local per = total / avgQty(p)
              if not best or per < best then best, via = per, p.id end
            end
          end
        end
      end
      visiting[itemId] = nil
    end
  end
  if not best then
    self.unpriced[itemId] = true
    best = self.opts.unknownPrice
  end
  byLevel[k] = { best, via }
  return best, via
end

-- Reagent cost minus recovery for ONE craft of r at level k.
function Planner:NetCraftCost(r, k)
  local total = 0
  for _, rg in ipairs(r.reagents) do
    total = total + self:UnitCost(rg[1], k) * rg[2]
  end
  local rec = 0
  if r.creates then
    local out = r.creates[1]
    local per = self.pricer:VendorSell(out)
    if self.opts.speculativeRecovery then
      local v = ns.Recovery.Evaluate(self.ds, self.pricer, out, self.opts.recoveryCtx)
      per = math.max(per, v.best or 0)
    end
    rec = per * avgQty(r)
  end
  return total - rec, total, rec
end

local function lockedRecipeAt(locks, k)
  if not locks then return nil end
  for _, l in ipairs(locks) do
    if k >= l.from and k < l.to then return l.recipe end
  end
  return nil
end

-- Objective of gaining point k -> k+1 with r (INF when r cannot give it).
function Planner:Objective(r, k)
  local lock = lockedRecipeAt(self.opts.locks, k)
  if lock and lock ~= r.id then return INF end
  local e = ns.SkillUp.ExpectedCrafts(r, k)
  if e == INF then return INF end
  local net = self:NetCraftCost(r, k)
  return e * (net * self.wg + self.wc), e, net
end

function Planner:Candidates()
  local out = {}
  local excl = self.opts.exclude or {}
  local lockSet = {}
  for _, l in ipairs(self.opts.locks or {}) do lockSet[l.recipe] = true end
  local specs = self.opts.specs or {}
  for _, r in ipairs(self.ds.recipesByProf[self.prof] or {}) do
    local blocked = excl[r.id]
      or (r.spec and not specs[r.spec] and not lockSet[r.id])
      or (ns.Cooldowns and ns.Cooldowns.Has(r.id) and not self.opts.allowCooldowns and not lockSet[r.id])
    if not blocked then
      self.opts.forced = lockSet[r.id] and r.id or nil
      local a = self:Acquire(r)
      self.opts.forced = nil
      if not a and lockSet[r.id] then
        a = { t = "locked", cost = 0, crafts = 0 }
        self.acq[r.id] = a
      end
      if a then out[#out + 1] = r end
    end
  end
  table.sort(out, function(x, y) return x.id < y.id end)
  return out
end

-- Rank training steps the route crosses: rank i is needed when the route gains a
-- point at or above the previous rank's cap. A player whose skill is already past
-- that cap must hold the rank, so only caps in [from, to) produce a step.
function O.TrainingSteps(ds, profId, from, to, charLevel)
  local steps, warnings = {}, {}
  local ranks = ns.Professions.Ranks(profId, ds)
  for i = 2, #ranks do
    local cap = ranks[i - 1].max
    local rank = ranks[i]
    if cap >= from and cap < to then
      steps[#steps + 1] = { rank = rank.name, by = cap, earliest = rank.learnAt or 0,
        cost = rank.cost or 0, charLevel = rank.charLevel }
      if charLevel and rank.charLevel and charLevel < rank.charLevel then
        warnings[#warnings + 1] = ("%s requires character level %d"):format(rank.name, rank.charLevel)
      end
    end
  end
  return steps, warnings
end

function Planner:Plan(from, to)
  local cands = self:Candidates()
  local best, prev = {}, {}
  for s = from, to do best[s] = INF end
  best[from] = 0

  -- recipes active at each start level
  local active = {}
  for s = from, to - 1 do active[s] = {} end
  for _, r in ipairs(cands) do
    local a = math.max(from, r.learn)
    local b = math.min(to, r.colors[4])
    for s = a, b - 1 do table.insert(active[s], r) end
  end

  for a = from, to - 1 do
    local base = best[a]
    if base < INF then
      for _, r in ipairs(active[a]) do
        local acq = self:Acquire(r)
        local start = base + acq.cost * self.wg + acq.crafts * self.wc
        local sum = 0
        local stop = math.min(to, r.colors[4])
        for b = a + 1, stop do
          local o = self:Objective(r, b - 1)
          if o == INF then break end
          sum = sum + o
          local cand = start + sum
          if cand < best[b] then
            best[b] = cand
            prev[b] = { a, r }
          end
        end
      end
    end
  end

  local route = {
    prof = self.prof, from = from, to = to, mode = self.opts.mode,
    segments = {}, warnings = {}, totalCrafts = 0, totalCost = 0, acquireCost = 0,
  }
  local reach = to
  if best[to] == INF then
    reach = from
    for s = to, from, -1 do
      if best[s] < INF then reach = s; break end
    end
    route.unreachable = reach
    route.warnings[#route.warnings + 1] =
      ("No allowed recipe gives points at skill %d; route stops there."):format(reach)
  end

  local segs = {}
  local b = reach
  while b > from do
    local p = prev[b]
    table.insert(segs, 1, { from = p[1], to = b, recipe = p[2] })
    b = p[1]
  end
  -- merge adjacent segments of the same recipe
  local merged = {}
  for _, s in ipairs(segs) do
    local last = merged[#merged]
    if last and last.recipe == s.recipe then last.to = s.to else merged[#merged + 1] = s end
  end

  local learned = {}
  for _, s in ipairs(merged) do
    local r = s.recipe
    local seg = { recipe = r.id, name = r.name, from = s.from, to = s.to, crafts = 0, gold = 0,
      colorAtStart = ns.SkillUp.Color(r, s.from), reagents = {}, via = {} }
    for k = s.from, s.to - 1 do
      local e = ns.SkillUp.ExpectedCrafts(r, k)
      local net = self:NetCraftCost(r, k)
      seg.crafts = seg.crafts + e
      seg.gold = seg.gold + e * net
    end
    for _, rg in ipairs(r.reagents) do
      local _, via = self:UnitCost(rg[1], s.from)
      seg.reagents[#seg.reagents + 1] = { rg[1], rg[2] }
      if via then seg.via[rg[1]] = via end
    end
    local a = self:Acquire(r)
    if a.t ~= "known" and not learned[r.id] then
      seg.acquire = a
      seg.gold = seg.gold + a.cost
      route.acquireCost = route.acquireCost + a.cost
      learned[r.id] = true
    end
    seg.craftsCeil = math.ceil(seg.crafts - 1e-9)
    route.totalCrafts = route.totalCrafts + seg.crafts
    route.totalCost = route.totalCost + seg.gold
    route.segments[#route.segments + 1] = seg
  end

  local steps, warns = O.TrainingSteps(self.ds, self.prof, from, reach, self.opts.charLevel)
  route.training = steps
  for _, st in ipairs(steps) do route.totalCost = route.totalCost + st.cost end
  for _, w in ipairs(warns) do route.warnings[#route.warnings + 1] = w end

  local unp = ns.Util.sortedKeys(self.unpriced)
  if #unp > 0 then
    route.unpriced = unp
    route.warnings[#route.warnings + 1] =
      ("%d reagent(s) have no price; assumed %s each."):format(#unp, ns.Util.money(self.opts.unknownPrice))
  end
  return route
end

-- Convenience: one call.
function O.Plan(ds, profId, from, to, opts)
  return O.NewPlanner(ds, profId, opts):Plan(from, to)
end
