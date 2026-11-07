-- Design tokens: every colour, marker and spacing the UI uses, by name. Consumers name
-- tokens, never |cff literals, so one table restyles the addon.
local _, ns = ...
local T = ns:NewModule("Theme")

T.color = {
  gold = "ffd100",      -- headings, the selected tab, recommended actions
  muted = "a0a0a0",     -- secondary text: sources, sample sizes, hints
  learn = "c0c0c0",     -- "[learn]" tag on route steps
  train = "80c0ff",     -- trainer steps
  warn = "ff4040",      -- route warnings, missing prices, incomplete data
  locked = "ff6060",    -- "[locked]" tag
  done = "40ff40",      -- shopping lines already covered
  drop = "ff9933",      -- "drop" tag on gear rows
  title = "d4a017",     -- the addon name in chat
}

-- Skill-up difficulty colours, indexed like the optimizer's colorAtStart:
-- 1 orange, 2 yellow, 3 green, 4 grey.
T.SKILL = { "ff8040", "ffff00", "40bf40", "808080" }
-- Colour-blind markers for the same four (Skillet's convention).
T.SKILL_MARKER = { "+++", "++", "+", "" }

T.space = { s = 4, m = 8, l = 12 }
T.ROW_HEIGHT = 16
T.ICON_SIZE = 14

-- "|cffRRGGBBtext|r" for a token name (or a raw RRGGBB).
function T.Wrap(key, text)
  return "|cff" .. (T.color[key] or key) .. tostring(text) .. "|r"
end

-- True when difficulty must not be told by colour alone: the Profs! setting wins;
-- unset follows the game's own colour-blind mode.
function T.Colorblind()
  local s = ns.db and ns.db.settings and ns.db.settings.colorblind
  if s ~= nil then return s == true end
  if GetCVarBool then
    local ok, on = pcall(GetCVarBool, "colorblindMode")
    return ok and on == true
  end
  return false
end
