-- Professions window (/profs recommend, right-click a launcher): what each profession
-- would do for this character (Engine/Advisor.lua).
--   top      a verdict: which primary profession fits you best and why, against the
--            runner-up (e.g. Leatherworking or Blacksmithing)
--   yours    your professions and your alts': skill, next rank to train, cost to max,
--            which gathering profession feeds which
--   cards    every other profession, ranked by Best for you / Cheapest / Fewest crafts
-- Each card is one route plan; they are computed one per frame, so opening the window
-- never freezes the game for all of them at once.
local _, ns = ...
local RF = ns:NewModule("RecommendFrame")
local U = ns.Util

RF.SORTS = { { "you", "Best for you" }, { "cost", "Cheapest" }, { "crafts", "Fewest crafts" } }
RF.sort = "you"

local function gold(t) return ns.Theme.Wrap("gold", t) end
local function muted(t) return ns.Theme.Wrap("muted", t) end

local function sourceName(src)
  if src == "cloth" then return "Cloth drops" end
  return ns.Professions.Name(src)
end

-- Who on this account has gathering profession `src`: "you", an alt's name, or nil.
function RF.WhoGathers(src, mine, alts)
  if src == "cloth" then return nil end
  if mine[src] then return "you" end
  for _, a in ipairs(alts or {}) do
    if a.profs[src] then return a.name end
  end
  return nil
end

local function pctText(c) return ns.Gear.GainText(c.gain) end

local function gearTooltip(ds, card)
  local t = { card.name .. ": upgrades for you" }
  for _, s in ipairs(card.gear.slots) do
    local c = s.best
    t[#t + 1] = ("%s: %s %s (skill %d, level %d)%s"):format(s.name, ns.Sidecar.ItemName(ds, c.itemId),
      pctText(c), s.skill, c.reqLevel or 0, #s.items > 1 and (", +" .. (#s.items - 1) .. " more") or "")
  end
  return t
end

-- Rows for one card. opts: rank (number), mine = {[prof]=rank}, alts, window
function RF.CardRows(ds, card, opts)
  opts = opts or {}
  local rows, cost = {}, card.cost
  local head = (opts.rank and (opts.rank .. ". ") or "") .. gold(card.name)
  if card.have then head = head .. muted((" (you: %d)"):format(card.skill)) end
  rows[#rows + 1] = { header = true, text = head,
    right = cost.done and "maxed" or U.money(cost.cost),
    tooltip = { card.name, card.note or "", cost.done and "Already at max skill."
      or ("Cost to %d from %d: recipes, training and the reagents you do not own."):format(cost.max, math.max(1, card.skill)) } }
  local g = card.gear
  if g.value > 0 then
    local names = {}
    for i, s in ipairs(g.slots) do if i <= 4 then names[#names + 1] = s.name end end
    rows[#rows + 1] = { indent = 8, iconItem = g.slots[1].best.itemId,
      text = ("Gear: %s"):format(table.concat(names, ", ") .. (#g.slots > 4 and ", ..." or "")),
      right = pctText(g.slots[1].best), tooltip = gearTooltip(ds, card) }
  else
    rows[#rows + 1] = { indent = 8,
      text = muted(("Gear: nothing for you in the next %d levels"):format(opts.window or ns.Advisor.WINDOW)) }
  end
  if not cost.done then
    local parts = { ("~%d crafts"):format(math.floor(cost.crafts + 0.5)) }
    if cost.find > 0 then parts[#parts + 1] = ("%d recipe%s to find"):format(cost.find, cost.find == 1 and "" or "s") end
    if not cost.complete then parts[#parts + 1] = ns.Theme.Wrap("warn", "data stops at " .. cost.reach) end
    rows[#rows + 1] = { indent = 8, text = table.concat(parts, ", ") }
  end
  if card.partner then
    local p = card.partnerInfo
    local who = RF.WhoGathers(card.partner, opts.mine or {}, opts.alts)
    local text
    if card.partner == "cloth" then
      text = ("Cloth drops while you quest: %d%% of materials"):format(math.floor(p.share * 100 + 0.5))
    else
      text = ("With %s: %d%% of materials free"):format(sourceName(card.partner), math.floor(p.share * 100 + 0.5))
    end
    if who == "you" then text = text .. ns.Theme.Wrap("done", " (you have it)")
    elseif who then text = text .. ns.Theme.Wrap("done", (" (%s has it)"):format(who)) end
    rows[#rows + 1] = { indent = 8, text = text, right = U.money(p.value),
      tooltip = { ("Materials %s supplies on this route, at today's prices."):format(sourceName(card.partner)) } }
  end
  if card.note then rows[#rows + 1] = { indent = 8, text = muted(card.note) } end
  return rows
end

-- The next rank to train for a profession you have, or nil.
function RF.NextRank(ds, profId, skill, cap)
  for _, r in ipairs(ns.Professions.Ranks(profId, ds)) do
    if r.max > (cap or 0) then
      return ("Train %s at skill %d%s"):format(r.name, r.learnAt or 0,
        r.charLevel and (", level " .. r.charLevel) or "")
    end
  end
  return nil
end

-- All rows. state: cards (computed so far), pending (count), mine = {[prof]={rank,max}},
-- alts = { {name, profs = {[prof]=rank}} }
function RF.Format(ds, state)
  local rows = {}
  local mineRank = {}
  for p, info in pairs(state.mine or {}) do mineRank[p] = info.rank end
  local byProf = {}
  for _, c in ipairs(state.cards or {}) do byProf[c.prof] = c end

  -- your professions
  local yours = {}
  for p in pairs(state.mine or {}) do yours[#yours + 1] = p end
  table.sort(yours)
  if #yours > 0 then
    rows[#rows + 1] = { summary = true, text = gold("Your professions") }
    for _, p in ipairs(yours) do
      local info = state.mine[p]
      local meta = ns.Professions.list[p]
      if meta and meta.crafting and byProf[p] then
        for _, r in ipairs(RF.CardRows(ds, byProf[p], { mine = mineRank, alts = state.alts })) do rows[#rows + 1] = r end
      else
        rows[#rows + 1] = { header = true, text = gold(ns.Professions.Name(p)) .. muted((" %d/%d"):format(info.rank, info.max or 0)) }
      end
      if info.max and info.max < ns.Professions.MaxSkill(p, ds) then
        local nr = RF.NextRank(ds, p, info.rank, info.max)
        if nr then rows[#rows + 1] = { indent = 8, text = ns.Theme.Wrap("train", nr) } end
      end
    end
  end
  if state.alts and #state.alts > 0 then
    for _, a in ipairs(state.alts) do
      local t = {}
      for p, rank in pairs(a.profs) do t[#t + 1] = ("%s %d"):format(ns.Professions.Name(p), rank) end
      table.sort(t)
      if #t > 0 then rows[#rows + 1] = { indent = 8, text = muted(("%s: %s"):format(a.name, table.concat(t, ", "))) } end
    end
  end

  -- other primary professions, ranked
  local others, secondary = {}, {}
  for _, c in ipairs(state.cards or {}) do
    if not mineRank[c.prof] then
      if c.kind == "primary" then others[#others + 1] = c else secondary[#secondary + 1] = c end
    end
  end
  if #others > 0 then
    local label = ({ you = "Best for you", cost = "Cheapest to level", crafts = "Fewest crafts" })[RF.sort]
    rows[#rows + 1] = { summary = true, text = gold("Primary professions: " .. label) }
    for i, c in ipairs(ns.Advisor.Rank(others, RF.sort)) do
      for _, r in ipairs(RF.CardRows(ds, c, { rank = i, mine = mineRank, alts = state.alts })) do rows[#rows + 1] = r end
    end
  end
  if #secondary > 0 then
    rows[#rows + 1] = { summary = true, text = gold("Secondary (you can have all of them)") }
    for _, c in ipairs(ns.Advisor.Rank(secondary, "cost")) do
      for _, r in ipairs(RF.CardRows(ds, c, { mine = mineRank, alts = state.alts })) do rows[#rows + 1] = r end
    end
  end
  if (state.pending or 0) > 0 then
    rows[#rows + 1] = { summary = true, text = muted(("Working out %d more..."):format(state.pending)) }
  end
  rows[#rows + 1] = { summary = true, text = muted("Estimates: expected craft counts, current prices, gear the data knows.") }
  return rows
end

-- The verdict line over the list.
function RF.VerdictText(state)
  if (state.pending or 0) > 0 then return "Comparing professions for you..." end
  local mine, cands, primaries = {}, {}, 0
  for p in pairs(state.mine or {}) do
    mine[p] = true
    local meta = ns.Professions.list[p]
    if meta and meta.kind == "primary" then primaries = primaries + 1 end
  end
  for _, c in ipairs(state.cards or {}) do
    if c.kind == "primary" and not mine[c.prof] then cands[#cands + 1] = c end
  end
  if #cands == 0 then return "You have every crafting profession the data knows." end
  local v = ns.Advisor.Verdict(cands)
  if primaries >= 2 then v = v .. " (You have two primary professions: picking one means dropping one.)" end
  return v
end

-- Context for the advisor from the live game.
function RF.Context(ds)
  local gctx = ns.GearFrame.Context()
  local known = {}
  for _, set in pairs(ns.cdb.known or {}) do for id in pairs(set) do known[id] = true end end
  local skills, mine = {}, {}
  for line, p in pairs(ns.Game.Professions()) do skills[line] = p.rank; mine[line] = { rank = p.rank, max = p.max } end
  local alts = {}
  local me = ns.Game.PlayerKey()
  for key, c in pairs(ns.db.chars or {}) do
    if key ~= me and c.profs and next(c.profs) then alts[#alts + 1] = { name = c.name or key, profs = c.profs } end
  end
  table.sort(alts, function(a, b) return a.name < b.name end)
  return {
    pricer = ns.PriceSources.Pricer(ds), have = ns.Inventory.Have, known = known,
    side = ns.Game.Faction(), charLevel = gctx.me.level, allowSources = ns.db.settings.allowSources,
    skills = skills, mine = mine, alts = alts,
    gear = function(profId)
      return (ns.GearFrame.Compute(ds, { [profId] = ns.Professions.MaxSkill(profId, ds) },
        { ctx = gctx, lookahead = ns.Advisor.WINDOW, drops = false }))
    end,
  }
end

function RF.Render()
  local f, st = RF.frame, RF.state
  if not (f and st) then return end
  f.verdict:SetText(RF.VerdictText(st))
  for _, b in ipairs(f.tabs) do ns.Widgets.SetSelected(b, b.sortKey == RF.sort) end
  f.list:Set(RF.Format(st.ds, st), true)
  if f.spinner then f.spinner:SetShown(st.pending > 0) end
end

-- Compute the cards one per frame.
function RF.Start(ds)
  local ctx = RF.Context(ds)
  local queue = {}
  for profId, meta in pairs(ns.Professions.list) do
    if meta.crafting and ds.recipesByProf[profId] then queue[#queue + 1] = profId end
  end
  table.sort(queue)
  local st = { ds = ds, cards = {}, pending = #queue, mine = ctx.mine, alts = ctx.alts }
  RF.state = st
  local function step()
    if RF.state ~= st then return end -- reopened meanwhile: that run takes over
    local profId = table.remove(queue, 1)
    if not profId then return end
    local ok, card = pcall(ns.Advisor.Card, ds, profId, ctx)
    if ok then st.cards[#st.cards + 1] = card
    else ns.Log("debug", "advisor " .. tostring(profId) .. ": " .. tostring(card)) end
    st.pending = #queue
    RF.Render()
    if #queue > 0 then C_Timer.After(0, step) end
  end
  RF.Render()
  if C_Timer and C_Timer.After then C_Timer.After(0, step) else while #queue > 0 do step() end end
end

function RF.Show()
  local ds = ns.ActiveDataset()
  if not ds then ns.Log("warn", "no dataset; see /profs status"); return end
  local W = ns.Widgets
  if not RF.frame then
    local f = W.Window("ProfsRecommend", ns.displayName .. " - Professions", 540, 560, { point = { "CENTER", 0, 0 } })
    f.verdict = W.Text(f)
    f.verdict:SetPoint("TOPLEFT", 14, f.top - 4)
    f.verdict:SetWidth(510)
    if f.verdict.SetWordWrap then f.verdict:SetWordWrap(true) end
    f.spinner = W.Spinner(f, 20)
    if f.spinner then f.spinner:SetPoint("TOPRIGHT", -14, f.top - 4) end
    f.tabs = {}
    local x, tabH = 12, 22
    for _, s in ipairs(RF.SORTS) do
      local b, h = W.Tab(f, s[2], function() RF.sort = s[1]; RF.Render() end)
      b.sortKey = s[1]
      tabH = h or tabH
      b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", x, f.top - 58 - tabH)
      x = x + (b:GetWidth() or 100) + 2
      f.tabs[#f.tabs + 1] = b
    end
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 12, f.top - 62 - tabH)
    body:SetPoint("BOTTOMRIGHT", -12, 12)
    body:SetSize(516, 420)
    f.list = W.List(body, 26, ns.Theme.ROW_HEIGHT, 516)
    RF.frame = f
  end
  RF.frame:Show()
  RF.Start(ds)
end

ns.commands.recommend = RF.Show
