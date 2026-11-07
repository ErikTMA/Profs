-- Profession metadata keyed on skill-line id (stable across clients).
--
-- VERIFICATION STATUS: the skill-line ids are the long-standing ones shared by every
-- 1.x-derived client. The rank caps / training costs / character-level requirements
-- below are the Classic Era values and are NOT verified for WoW Forever; a dataset's
-- own `professions` table overrides them when it carries rank data.
-- `crafting=false` professions are listed so the UI can name them, but V1 builds no
-- gathering routes.
local _, ns = ...
local P = ns:NewModule("Professions")

local CLASSIC_RANKS = {
  { name = "Apprentice", max = 75,  cost = 10,    charLevel = 5,  learnAt = 0 },
  { name = "Journeyman", max = 150, cost = 500,   charLevel = 10, learnAt = 50 },
  { name = "Expert",     max = 225, cost = 5000,  charLevel = 20, learnAt = 125 },
  { name = "Artisan",    max = 300, cost = 50000, charLevel = 35, learnAt = 200 },
}

P.list = {
  [171] = { name = "Alchemy",        kind = "primary",   crafting = true },
  [164] = { name = "Blacksmithing",  kind = "primary",   crafting = true },
  [333] = { name = "Enchanting",     kind = "primary",   crafting = true, enchanting = true },
  [202] = { name = "Engineering",    kind = "primary",   crafting = true },
  [165] = { name = "Leatherworking", kind = "primary",   crafting = true },
  [197] = { name = "Tailoring",      kind = "primary",   crafting = true },
  [185] = { name = "Cooking",        kind = "secondary", crafting = true },
  [129] = { name = "First Aid",      kind = "secondary", crafting = true },
  [356] = { name = "Fishing",        kind = "secondary", crafting = false },
  [186] = { name = "Mining",         kind = "primary",   crafting = false },
  [182] = { name = "Herbalism",      kind = "primary",   crafting = false },
  [393] = { name = "Skinning",       kind = "primary",   crafting = false },
}

P.ENCHANTING = 333

function P.Ranks(profId, ds)
  local over = ds and ds.professions and ds.professions[profId]
  if over and over.ranks then return over.ranks end
  return CLASSIC_RANKS
end

-- The rank whose cap is the first >= skill+1 (the rank you need to gain `skill+1`).
function P.RankFor(profId, skill, ds)
  for i, r in ipairs(P.Ranks(profId, ds)) do
    if skill < r.max then return i, r end
  end
  return nil
end

function P.MaxSkill(profId, ds)
  local ranks = P.Ranks(profId, ds)
  return ranks[#ranks].max
end

function P.Name(profId)
  local p = P.list[profId]
  return p and p.name or ("Profession " .. tostring(profId))
end

function P.IsCrafting(profId)
  local p = P.list[profId]
  return p ~= nil and p.crafting
end
