-- Level-up gear alerts (pure). When the character reaches a new level, find crafted
-- gear that just became equippable, that this character can make now (skill, and a
-- recipe that is known or obtainable from a trainer/vendor/starter source), that it
-- can wear (armor and weapon proficiency) and that is a MEANINGFUL upgrade over what
-- is equipped. Scoring: Pawn's upgrade percent when available, else Engine/Gear.lua's
-- automatic weights. Each item is announced once per character.
local _, ns = ...
local GA = ns:NewModule("GearAlert")

GA.DEFAULTS = {
  enabled = true,
  minPct = 5,        -- percent better than the equipped item (Pawn: its upgrade %)
  minGain = 1,       -- absolute score points (built-in weights)
  maxPerLevel = 3,   -- rows in one notification
}

-- item inventory type -> the inventory slot(s) it competes with
GA.INV_SLOTS = { [1] = { 1 }, [2] = { 2 }, [3] = { 3 }, [5] = { 5 }, [20] = { 5 }, [6] = { 6 },
  [7] = { 7 }, [8] = { 8 }, [9] = { 9 }, [10] = { 10 }, [11] = { 11, 12 }, [12] = { 13, 14 },
  [16] = { 15 }, [13] = { 16 }, [17] = { 16 }, [21] = { 16 }, [14] = { 17 }, [22] = { 17 },
  [23] = { 17 }, [15] = { 18 }, [25] = { 18 }, [26] = { 18 } }

GA.STAT_NAMES = {
  ITEM_MOD_STRENGTH_SHORT = "Strength", ITEM_MOD_AGILITY_SHORT = "Agility",
  ITEM_MOD_STAMINA_SHORT = "Stamina", ITEM_MOD_INTELLECT_SHORT = "Intellect",
  ITEM_MOD_SPIRIT_SHORT = "Spirit", RESISTANCE0_NAME = "Armor",
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
}

local function statName(k)
  local g = _G and rawget(_G, k)
  if type(g) == "string" and g ~= "" then return g end
  return GA.STAT_NAMES[k] or k
end

-- The equipped item this one would replace: the weakest of the slots it competes
-- with (a ring replaces the worse ring). Empty slot -> score 0.
local function replaces(equipped, invType, weights)
  local best, bestScore
  for _, inv in ipairs(GA.INV_SLOTS[invType] or {}) do
    local e = equipped and equipped[inv] or { score = 0 }
    if e.unknown then return e end -- one unreadable candidate slot: do not guess
    local sc = e.score or (e.stats and ns.Gear.Score(e.stats, weights)) or 0
    if not best or sc < bestScore then best, bestScore = e, sc end
  end
  return best
end
GA.Replaces = replaces

-- "+3 Stamina, +2 Intellect" (top 3 weighted improvements over the replaced item)
function GA.Reason(newStats, oldStats, weights)
  local diffs = {}
  for k, v in pairs(newStats or {}) do
    local d = v - ((oldStats or {})[k] or 0)
    if d > 0 and (weights[k] or 0) > 0 then diffs[#diffs + 1] = { k = k, d = d, w = d * weights[k] } end
  end
  table.sort(diffs, function(a, b) if a.w ~= b.w then return a.w > b.w end return a.k < b.k end)
  local parts = {}
  for i = 1, math.min(3, #diffs) do
    local d = diffs[i]
    parts[#parts + 1] = ("+%s %s"):format(d.d == math.floor(d.d) and tostring(d.d) or ("%.1f"):format(d.d), statName(d.k))
  end
  return table.concat(parts, ", ")
end

local function obtainable(r, known, ds, side)
  return ns.Gear.Obtainable(r, known, { side = side, npcs = ds.npcs })
end

-- ctx: level, prevLevel, class, profs={[prof]=skill}, known={[recipe]=true},
--      equipped={[invSlot]={score?, stats?, name?}}, stats(itemId)->table|nil,
--      scorer(itemId)->pawn percent|nil, pricer, have(itemId)->n, seen={[itemId]=true},
--      settings (GA.DEFAULTS overrides), side ("A"/"H"/nil: faction for trainer access)
function GA.Evaluate(ds, ctx)
  local cfg = ns.Util.merge(GA.DEFAULTS, ctx.settings or {})
  if not cfg.enabled then return {} end
  local weights = ctx.weights or ns.Gear.AutoWeights(ctx.class, ctx.equippedTotals, ctx.spec)
  local pricer = ctx.pricer or ns.Pricing.New(ds)
  local out, best = {}, {}
  for prof, skill in pairs(ctx.profs or {}) do
    for _, r in ipairs(ds.recipesByProf[prof] or {}) do
      local itemId = r.creates and r.creates[1]
      local it = itemId and ds.items[itemId]
      local rl = it and (it.rl or 0)
      if it and it.slot and GA.INV_SLOTS[it.slot] and r.learn <= skill
        and rl > (ctx.prevLevel or 0) and rl <= ctx.level
        and not (ctx.seen and ctx.seen[itemId])
        and ns.Gear.CanWear(ctx.class, ctx.level, it) then
        local acq = obtainable(r, ctx.known, ds, ctx.side)
        if acq then
          local old = replaces(ctx.equipped, it.slot, weights)
          local alert
          if old.unknown then old = nil end -- cannot compare: never risk a downgrade
          local pawn = old and ctx.scorer and ctx.scorer(itemId)
          if not old then
            -- skip
          elseif pawn ~= nil then
            if pawn >= cfg.minPct then alert = { gain = pawn, pct = pawn, scoredBy = "Pawn" } end
          else
            local st = it.stats or (ctx.stats and ctx.stats(itemId))
            if st then
              local s = ns.Gear.Score(st, weights)
              local cur = old.score or (old.stats and ns.Gear.Score(old.stats, weights)) or 0
              local gain = s - cur
              local pct = cur > 0 and gain / cur * 100 or math.huge
              if gain >= cfg.minGain and pct >= cfg.minPct then
                alert = { gain = gain, pct = pct, scoredBy = "Profs! weights",
                  reason = GA.Reason(st, old.stats, weights) }
              end
            end
          end
          if alert then
            alert.itemId, alert.recipe, alert.prof, alert.slot = itemId, r.id, prof, it.slot
            alert.reqLevel, alert.replaces = rl, old.name
            alert.acquire = acq
            local mats, cost, unpriced = {}, acq.cost or 0, false
            for _, rg in ipairs(r.reagents) do
              local have = ctx.have and ctx.have(rg[1]) or 0
              local buy = math.max(0, rg[2] - have)
              local unit = pricer:Buy(rg[1])
              if buy > 0 then
                if unit then cost = cost + unit * buy else unpriced = true end
              end
              mats[#mats + 1] = { itemId = rg[1], need = rg[2], have = have, unit = unit }
            end
            alert.materials, alert.cost, alert.unpriced = mats, cost, unpriced
            -- one alert per item (best recipe), keep the best per competing slot
            local key = it.slot
            if not best[key] or alert.gain > best[key].gain then best[key] = alert end
          end
        end
      end
    end
  end
  for _, a in pairs(best) do out[#out + 1] = a end
  table.sort(out, function(a, b)
    if a.gain ~= b.gain then return a.gain > b.gain end
    return a.itemId < b.itemId
  end)
  while #out > cfg.maxPerLevel do table.remove(out) end
  return out
end
