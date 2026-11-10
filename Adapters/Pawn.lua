-- Gear scoring: which weights rate an upgrade.
--
-- Pawn (optional) is used through its global functions only (PawnGetItemData,
-- PawnIsItemAnUpgrade, PawnFindScaleForSpec, PawnGetAllScalesEx), every call
-- pcall-guarded: a Pawn build with a different signature degrades to the built-in
-- weights, never to an error.
--
-- ONE scale scores, never the best of all of them. Pawn's upgrade table holds a percent
-- per visible scale (Difference / current value), so a healing scale rates any +healing
-- item as thousands of percent better than gear with no healing on it; taking the
-- maximum made an Enhancement shaman's list a healer's list. The scale is:
--   the character's choice (ProfsCharDB.gearSpec: "spec:<n>" or "pawn:<scale>"), else
--   Pawn's scale for the active specialization (PawnFindScaleForSpec(class, tree)).
-- A chosen scale Pawn does not show (hidden in Pawn) has no values: Pawn's weights
-- built into Profs! (Data/PawnWeights.lua) for that specialization score instead, and
-- the label says so. Without Pawn the same built-in weights score, in percent too.
local _, ns = ...
local PW = ns:NewModule("Pawn")

function PW.Available()
  return type(PawnGetItemData) == "function" and type(PawnIsItemAnUpgrade) == "function"
end

-- Pawn scales: { {name, label, visible} } (empty without Pawn).
function PW.Scales()
  if type(PawnGetAllScalesEx) ~= "function" then return {} end
  local ok, list = pcall(PawnGetAllScalesEx)
  if not ok or type(list) ~= "table" then return {} end
  local out = {}
  for _, s in ipairs(list) do
    if type(s) == "table" and s.Name then
      out[#out + 1] = { name = s.Name, label = s.LocalizedName or s.Name, visible = s.IsVisible == true }
    end
  end
  return out
end

function PW.ScaleForSpec(classId, spec)
  if type(PawnFindScaleForSpec) ~= "function" or not classId or not spec then return nil end
  local ok, name = pcall(PawnFindScaleForSpec, classId, spec)
  return ok and type(name) == "string" and name or nil
end

local function scaleInfo(name)
  for _, s in ipairs(PW.Scales()) do if s.name == name then return s end end
  return nil
end

-- scorer(itemId) -> upgrade percent on `scale` (0 when not an upgrade there), nil when
-- Pawn cannot say. Without a scale (no spec known, nothing chosen): the visible scale
-- with the highest upgrade, Pawn's own tooltip behaviour.
function PW.Scorer(scale)
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
        if type(u) == "table" and type(u.PercentUpgrade) == "number"
            and (not scale or u.ScaleName == scale) and u.PercentUpgrade > best then
          best = u.PercentUpgrade
        end
      end
    end
    return best * 100
  end
end

-- What scores gear for this character now:
-- { scorer = fn|nil, spec = tree index|nil, label = "..." }
function PW.Scoring()
  local me = ns.Game.PlayerInfo()
  local active = ns.Game.Spec()
  local pref = ns.cdb and ns.cdb.gearSpec or "auto"
  local specIdx = tonumber(type(pref) == "string" and pref:match("^spec:(%d+)$") or nil)
    or (active and active.index)
  local names = ns.Game.SpecNames()
  local specLabel = specIdx and (names[specIdx] or ("specialization " .. specIdx)) or nil
  local scale = type(pref) == "string" and pref:match("^pawn:(.+)$") or nil
  if PW.Available() then
    scale = scale or PW.ScaleForSpec(me.classId, specIdx)
    local info = scale and scaleInfo(scale)
    if scale and info and not info.visible then
      return { spec = specIdx, specName = specLabel, label = ("Pawn's weights for %s, built in (Pawn scale \"%s\" is hidden in Pawn)"):format(
        specLabel or "your class", info.label) }
    end
    local label = info and info.label or scale
    return { scorer = PW.Scorer(scale), spec = specIdx, pawn = true, scale = scale,
      label = label and ("Scored by Pawn: " .. label) or "Scored by Pawn (best of your visible scales)" }
  end
  return { spec = specIdx, specName = specLabel, label = specLabel and ("Pawn's weights for " .. specLabel .. ", built in")
    or "Pawn's weights for your class, built in" }
end

-- Choices for "Score gear for": auto, each specialization, each Pawn scale.
function PW.Choices()
  local out = { { "auto", "Active specialization" } }
  for i, n in pairs(ns.Game.SpecNames()) do out[#out + 1] = { "spec:" .. i, n } end
  for _, s in ipairs(PW.Scales()) do
    out[#out + 1] = { "pawn:" .. s.name, "Pawn: " .. s.label .. (s.visible and "" or " (hidden in Pawn)") }
  end
  return out
end

-- /profs gearspec [auto|<n>|pawn <scale name>]
ns.commands.gearspec = function(rest)
  rest = rest or ""
  if rest == "auto" then ns.cdb.gearSpec = nil
  elseif tonumber(rest) then ns.cdb.gearSpec = "spec:" .. tonumber(rest)
  elseif rest:match("^pawn%s+.+") then ns.cdb.gearSpec = "pawn:" .. rest:match("^pawn%s+(.+)$")
  elseif rest ~= "" then ns.Log("warn", "/profs gearspec auto | <specialization number> | pawn <scale name>"); return end
  ns.Log("info", PW.Scoring().label)
  ns.Log("info", ns.Game.SpecDebug())
  if ns.GearColumn and ns.GearColumn.RequestUpdate then ns.GearColumn.RequestUpdate() end
end
