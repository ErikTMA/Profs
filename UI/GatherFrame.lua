-- Gathering guide window (Herbalism, Mining, Skinning): Engine/Gathering.lua's plan from your
-- skill to the target, one row per area with a waypoint on click, rank training rows,
-- and the GatherMate2 link (your recorded nodes join the areas; "Add to GatherMate2"
-- copies Profs!' spawns into it). The same rows fill the profession-window column when
-- a gathering profession is open there (Mining's smelting window).
--
-- GF.Format is pure and unit tested; the frame code only renders it.
local _, ns = ...
local GF = ns:NewModule("GatherFrame")
local U = ns.Util

GF.PROFS = { 182, 186, 393 }
-- the column's line under the skill (Sidecar)
GF.HINT = { [393] = "Where to skin. Click an area for a waypoint (/profs gather for the window)." }
GF.HINT.default = "Where to gather. Click an area for a waypoint (/profs gather for the window)."
GF.cache = {}   -- prof -> { areas, gm = { points, new, unknown } }

local function color(c, text) return "|cff" .. c .. text .. "|r" end

local function zoneName(ds, zone)
  local z = ds.zones and ds.zones[zone]
  local name = ns.Map and ns.Map.ZoneName(zone, z and z.n) or (z and z.n)
  return name or ("map " .. zone)
end

-- The node to show for an area at skill s: the most common one still giving skill-ups,
-- else the most common.
local function leadNode(comp, s)
  local best
  for _, e in ipairs(comp) do
    local useful = e.color and e.color ~= ns.SkillUp.GREY
    if not best or (useful and not best.useful) or (useful == best.useful and e.count > best.e.count) then
      best = { e = e, useful = useful }
    end
  end
  return best and best.e
end

function GF.AreaTooltip(ds, a, s, ctx)
  ctx = ctx or {}
  local T = ns.Theme
  local z = ds.zones and ds.zones[a.zone] or {}
  local t = { ("%s (%.1f, %.1f)"):format(zoneName(ds, a.zone), a.x, a.y) }
  t[#t + 1] = color(T.color.muted, ("%d spawns within %s of this point"):format(a.total,
    a.yards and (a.yards .. " yards") or (ns.Gathering.RADIUS_PCT .. "% of the map")))
  local cb = T.Colorblind()
  for _, e in ipairs(ns.Gathering.Composition(ds, a, s)) do
    local c = e.color and T.SKILL[e.color] or T.color.muted
    local marker = cb and e.color and T.SKILL_MARKER[e.color] or ""
    local lv = e.lv and (e.lv[1] == e.lv[2] and ("level %d, "):format(e.lv[1])
      or ("level %d-%d, "):format(e.lv[1], e.lv[2])) or ""
    t[#t + 1] = ("%s (%sskill %d) x%d%s"):format(color(c, e.name), lv, e.skill, e.count,
      marker ~= "" and (" " .. marker) or "")
  end
  if a.mobLevel then
    local low = ctx.level and ctx.level < a.mobLevel
    t[#t + 1] = color(low and T.color.warn or T.color.muted, ("Mobs here: typically level %d"):format(a.mobLevel))
  elseif z.lv then
    local low = ctx.level and ctx.level < z.lv[1]
    t[#t + 1] = color(low and T.color.warn or T.color.muted, ("Zone mobs: level %d-%d"):format(z.lv[1], z.lv[2]))
  end
  local zs = ns.Gathering.ZoneSide(z)
  if zs and ctx.side and zs ~= ctx.side then
    t[#t + 1] = color(T.color.warn, ns.Faction.NAME[zs] .. " zone: few friendly towns for you")
  end
  if (a.own or 0) > 0 then
    t[#t + 1] = color(T.color.muted, ("%d of these spawns come from your GatherMate2 data"):format(a.own))
  end
  t[#t + 1] = color(T.color.muted, "Click: waypoint to this area")
  return t
end

local function rankRow(ds, prof, r, side)
  local T = ns.Theme
  local text = color(T.color.train, ("Train %s by %d"):format(r.rank, r.by))
  local tip = { ("%s %s"):format(r.rank, ns.Professions.Name(prof)),
    ("From skill %d, character level %d"):format(r.earliest or 0, r.charLevel or 1) }
  local shown = ns.Gathering.Trainers(ds, prof, side)
  for i = 1, math.min(4, #shown) do
    local n = ds.npcs[shown[i].id] or {}
    local where = n.zone or "?"
    if n.x and n.y then where = ("%s (%.1f, %.1f)"):format(where, n.x, n.y) end
    tip[#tip + 1] = ("%s - %s%s"):format(n.n or ("npc " .. shown[i].id), where,
      shown[i].access == "unknown" and color(T.color.muted, " (faction access unknown)") or "")
  end
  if #shown == 0 then tip[#tip + 1] = color(T.color.warn, "No trainer for your faction in the data") end
  return { kind = "train", text = text, right = U.money(r.cost), icon = "Interface\\Icons\\INV_Misc_Book_09",
    tooltip = tip, rank = r }
end

-- Rows of a plan. ctx = { skill, level, side, here (uiMapId you are on), gm = { new,
-- unknown, available } , onArea = fn(area, step) }.
function GF.Format(ds, plan, ctx)
  ctx = ctx or {}
  local T = ns.Theme
  local rows = {}
  local noun = ns.Gathering.NOUN[plan.prof] or "nodes"
  local spawns, zones = 0, {}
  for _, id in ipairs(ns.Gathering.NodesOf(ds, plan.prof)) do
    for zone, list in pairs(ds.nodes[id].spawns) do spawns = spawns + #list; zones[zone] = true end
  end
  local src = ("%d spawns in %d zones"):format(spawns, U.count(zones))
  local gm = ctx.gm
  if gm and gm.available then
    src = src .. (" + %d of yours from GatherMate2"):format(gm.new or 0)
  end
  rows[#rows + 1] = { summary = true, text = color(T.color.muted, src),
    tooltip = gm and gm.available and (gm.unknown or 0) > 0
      and { "GatherMate2", ("%d of your recorded nodes are not in Profs!' data (new or other nodes)"):format(gm.unknown) }
      or nil }
  local ranks, ri = plan.ranks or {}, 1
  local cur = ctx.skill and ns.Gathering.StepAt(plan, ctx.skill)
  for _, st in ipairs(plan.steps) do
    -- train before setting out on the step that crosses the rank's cap
    while ranks[ri] and ranks[ri].by < st.to do
      rows[#rows + 1] = rankRow(ds, plan.prof, ranks[ri], ctx.side); ri = ri + 1
    end
    local a = st.area
    local comp = ns.Gathering.Composition(ds, a, st.from)
    local lead = leadNode(comp, st.from)
    local name = zoneName(ds, a.zone)
    local flags = ""
    for _, w in ipairs(st.why or {}) do
      flags = flags .. color(T.color.warn, w == "level" and " [level]" or w == "enemy" and " [enemy zone]" or "")
    end
    local here = ctx.here == a.zone and color(T.color.done, " (here)") or ""
    local text = ("%3d-%3d %s (%.0f, %.0f)%s%s"):format(st.from, st.to,
      st == cur and color(T.color.gold, name) or name, a.x, a.y, here, flags)
    local nd = lead and ds.nodes[lead.node]
    rows[#rows + 1] = { kind = "area", text = text,
      right = ("~%d %s"):format(math.ceil(st.gathers), noun), step = st, area = a,
      iconItem = nd and nd.yields[1] and nd.yields[1][1],
      tooltip = function() return GF.AreaTooltip(ds, a, math.max(st.from, ctx.skill or st.from), ctx) end,
      onClick = ctx.onArea and function() ctx.onArea(a, st) end or nil }
  end
  while ranks[ri] do rows[#rows + 1] = rankRow(ds, plan.prof, ranks[ri], ctx.side); ri = ri + 1 end
  if plan.unreachable then
    rows[#rows + 1] = { kind = "warning", text = color(T.color.warn,
      ("No known spawns give skill-ups from %d."):format(plan.unreachable)) }
  end
  for _, w in ipairs(plan.warnings or {}) do
    rows[#rows + 1] = { kind = "warning", text = color(T.color.warn, w) }
  end
  return rows
end

-- runtime ------------------------------------------------------------------------

-- Areas of a profession for this session (rebuilt by /profs gather refresh, an
-- import, or new GatherMate2 data on the next open).
function GF.Areas(ds, prof)
  local c = GF.cache[prof]
  if c then return c end
  local points, unknown
  if ns.GatherMate.Available() then points, unknown = ns.GatherMate.Points(ds, prof) end
  local areas, new = ns.Gathering.Areas(ds, prof, { extra = points, size = ns.Map.ZoneSize,
    skipZone = function(z) return ns.Map.IsInstance(z) == true end })
  c = { areas = areas, gm = { available = points ~= nil, new = new, unknown = unknown or 0 } }
  GF.cache[prof] = c
  return c
end

-- Plan for a gathering profession of this character: plan, ctx.
function GF.Compute(prof, skill)
  local ds = ns.ActiveDataset()
  if not ds or not next(ds.nodes or {}) then return nil end
  local mine = ns.Game.Professions()[prof]
  skill = skill or (mine and mine.rank) or 1
  local target = (ns.cdb.targets and ns.cdb.targets[prof] and ns.cdb.targets[prof].to)
    or ns.Professions.MaxSkill(prof, ds)
  local c = GF.Areas(ds, prof)
  local me = ns.Game.PlayerInfo()
  local side = ns.Game.Faction()
  local here = ns.Map.PlayerMap()
  local plan = ns.Gathering.Plan(ds, prof, math.max(skill, 1), math.max(target, skill + 1),
    { areas = c.areas, level = me.level, side = side, continent = here and ns.Map.Continent(here),
      continentOf = ns.Map.Continent })
  local ctx = { skill = skill, level = me.level, side = side, here = here, gm = c.gm,
    learned = mine ~= nil, target = target,
    onArea = function(a, st)
      local title = ("%s %d-%d"):format(ns.Professions.Name(prof), st.from, st.to)
      local how = ns.Map.SetWaypoint(a.zone, a.x, a.y, title)
      ns.Log("info", how and ("waypoint: %s (%.1f, %.1f)"):format(zoneName(ds, a.zone), a.x, a.y)
        or ("go to %s (%.1f, %.1f); this client cannot set a waypoint there"):format(zoneName(ds, a.zone), a.x, a.y))
    end }
  return plan, ctx, ds
end

function GF.Header(prof, ctx)
  local name = ns.Professions.Name(prof)
  if not ctx.learned then return ("%s (not learned): guide from 1 to %d"):format(name, ctx.target) end
  return ("%s %d -> %d"):format(name, ctx.skill, ctx.target)
end

function GF.Import(prof)
  local ds = ns.ActiveDataset()
  if not ds then return end
  local res, why = ns.GatherMate.Import(ds, prof)
  if not res then
    ns.Log("warn", why == "locked" and "GatherMate2's database for this profession is locked (GatherMate2 options)"
      or "GatherMate2 is not loaded")
    return
  end
  GF.cache[prof] = nil
  ns.Log("info", ("GatherMate2: added %d %s spawns, %d already there%s"):format(res.added,
    ns.Professions.Name(prof), res.present,
    #res.unknown > 0 and ("; GatherMate2 does not know " .. table.concat(res.unknown, ", ")) or ""))
  GF.Render()
end

function GF.Build()
  if GF.frame then return GF.frame end
  local W = ns.Widgets
  local f = W.Window("ProfsGather", ns.displayName .. " - Gathering", 440, 440, { point = { "CENTER", 250, 0 } })
  f.profs = {}
  for i, prof in ipairs(GF.PROFS) do
    local b = W.Button(f, ns.Professions.Name(prof), 86, function() GF.prof = prof; GF.Render() end)
    b:SetPoint("TOPLEFT", 12 + (i - 1) * 90, f.top)
    f.profs[prof] = b
  end
  f.import = W.Button(f, "Add to GatherMate2", 140, function()
    local prof = GF.prof
    if StaticPopupDialogs and StaticPopup_Show then
      StaticPopupDialogs.PROFS_GATHERMATE_IMPORT = StaticPopupDialogs.PROFS_GATHERMATE_IMPORT or {
        text = "Add Profs!' %s spawns to GatherMate2's database? GatherMate2's own options can clear it again.",
        button1 = YES or "Yes", button2 = NO or "No", timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, data) GF.Import(data) end,
      }
      local d = StaticPopup_Show("PROFS_GATHERMATE_IMPORT", ns.Professions.Name(prof))
      if d then d.data = prof end
    else
      GF.Import(prof)
    end
  end)
  f.import:SetPoint("TOPRIGHT", -12, f.top)
  f.header = W.Text(f); f.header:SetPoint("TOPLEFT", 12, f.top - 28); f.header:SetWidth(410)
  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", 12, f.top - 48)
  body:SetPoint("BOTTOMRIGHT", -12, 12)
  body:SetSize(410, 330)
  f.list = W.List(body, 20, ns.Theme.ROW_HEIGHT, 410)
  f.list:SetEmptyText("No gathering data in this dataset.")
  GF.frame = f
  return f
end

function GF.Render()
  local f = GF.frame
  if not (f and f:IsShown()) then return end
  local prof = GF.prof or 182
  for p, b in pairs(f.profs) do ns.Widgets.SetSelected(b, p == prof) end
  -- GatherMate2 records herbs and ore, not skinning
  if ns.GatherMate.Available() and ns.GatherMate.TYPE[prof] then f.import:Show() else f.import:Hide() end
  local plan, ctx, ds = GF.Compute(prof)
  if not plan then f.header:SetText("No gathering data for this client."); f.list:Set({}); return end
  f.header:SetText(GF.Header(prof, ctx))
  f.list:Set(GF.Format(ds, plan, ctx), true)
end

-- The gathering profession to show first: one you have, else Herbalism.
function GF.DefaultProf()
  local mine = ns.Game.Professions()
  for _, p in ipairs(GF.PROFS) do if mine[p] then return p end end
  return 182
end

function GF.Show(prof)
  GF.prof = prof or GF.prof or GF.DefaultProf()
  local f = GF.Build()
  f:Show()
  GF.Render()
end

local ALIASES = { herb = 182, herbalism = 182, herbs = 182, mine = 186, mining = 186, ore = 186,
  skin = 393, skinning = 393 }

-- /profs gather [herbalism|mining|skinning] | import [herbalism|mining] | refresh
ns.commands.gather = function(rest)
  local cmd, arg = (rest or ""):lower():match("^(%S*)%s*(.-)$")
  if cmd == "refresh" then
    GF.cache = {}
    ns.Log("info", "gathering areas rebuilt")
    return GF.Show()
  end
  if cmd == "import" then
    local prof = ALIASES[arg] or GF.prof or GF.DefaultProf()
    return GF.Import(prof)
  end
  if ALIASES[cmd] then return GF.Show(ALIASES[cmd]) end
  if GF.frame and GF.frame:IsShown() and cmd == "" then return GF.frame:Hide() end
  GF.Show()
end

ns.Events.On("PROFS_LOADED", function()
  if not CreateFrame then return end
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "SKILL_LINES_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP" }) do ev:RegisterEvent(e) end
  ev:SetScript("OnEvent", function()
    if GF.frame and GF.frame:IsShown() and C_Timer and C_Timer.After then
      if GF.pending then return end
      GF.pending = true
      C_Timer.After(0, function() GF.pending = false; GF.Render() end)
    elseif GF.frame and GF.frame:IsShown() then
      GF.Render()
    end
  end)
  GF.events = ev
end)
