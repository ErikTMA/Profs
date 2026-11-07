-- WoW client adapter. Every call is feature-detected; nothing here assumes an API
-- the target client was not shown to have. Verified against Blizzard's UI source for
-- the forever client (Gethe/wow-ui-source branch `forever`, 1.60.1 build 70790):
--   GetBuildInfo, GetProfessions + GetProfessionInfo (Camelot ProfessionsFrame),
--   C_TradeSkillUI.GetBaseProfessionInfo / GetFilteredRecipeIDs / GetRecipeInfo /
--   GetRecipeSchematic / CraftRecipe / IsTradeSkillLinked / IsTradeSkillGuild /
--   IsNPCCrafting, C_Item.GetItemCount / GetItemInfo, ProfessionsFrame.
local _, ns = ...
local G = ns:NewModule("Game")

local function has(t, k) return type(t) == "table" and type(t[k]) == "function" end
G.has = has

-- WoW Forever reports version 1.60.x (classic era is 1.15.x). Keyed on the version
-- string, never the toc number (unverified for Forever).
function G.Flavor()
  if not GetBuildInfo then return "forever" end
  local ver = GetBuildInfo()
  local major, minor = tostring(ver or ""):match("^(%d+)%.(%d+)")
  if tonumber(major) == 1 and tonumber(minor) and tonumber(minor) >= 60 then return "forever" end
  return "unsupported"
end

function G.Describe()
  local ver, build, _, toc = "?", "?", nil, "?"
  if GetBuildInfo then ver, build, _, toc = GetBuildInfo() end
  local api = {}
  for _, name in ipairs({ "GetBaseProfessionInfo", "GetFilteredRecipeIDs", "GetRecipeInfo",
    "GetRecipeSchematic", "CraftRecipe" }) do
    api[#api + 1] = name .. (has(C_TradeSkillUI, name) and "+" or "-")
  end
  return ("client %s (%s) toc %s; %s"):format(tostring(ver), tostring(build), tostring(toc),
    table.concat(api, " "))
end

-- The player's professions: { [skillLine] = { name, rank, max, icon } }
function G.Professions()
  local out = {}
  if not GetProfessions or not GetProfessionInfo then return out end
  local slots = { GetProfessions() }
  for i = 1, 7 do
    local idx = slots[i]
    if idx then
      local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx)
      if skillLine then out[skillLine] = { name = name, icon = icon, rank = rank, max = maxRank } end
    end
  end
  return out
end

-- The profession window that is open right now, or nil. Returns
-- { prof = skillLine, skill, max, own = true when it is the player's own (not a
-- link, guild view or NPC crafting) }.
function G.OpenProfession()
  if not has(C_TradeSkillUI, "GetBaseProfessionInfo") then return nil end
  local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
  if not ok or type(info) ~= "table" or not info.professionID or info.professionID == 0 then return nil end
  local prof = info.professionID
  if not ns.Professions.list[prof] and info.parentProfessionID then prof = info.parentProfessionID end
  local own = true
  for _, fn in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
    if has(C_TradeSkillUI, fn) and C_TradeSkillUI[fn]() then own = false end
  end
  return { prof = prof, skill = info.skillLevel or 0, max = info.maxSkillLevel or 0, own = own,
    name = info.professionName }
end

-- Recipes the open window lists: { [recipeId] = { learned, difficulty, craftable } }
function G.ScanRecipes()
  local out = {}
  if not has(C_TradeSkillUI, "GetFilteredRecipeIDs") or not has(C_TradeSkillUI, "GetRecipeInfo") then
    return out
  end
  local ok, ids = pcall(C_TradeSkillUI.GetFilteredRecipeIDs)
  if not ok or type(ids) ~= "table" then return out end
  for _, id in ipairs(ids) do
    local ok2, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
    if ok2 and type(info) == "table" then
      out[id] = { learned = info.learned, difficulty = info.relativeDifficulty,
        craftable = info.craftable, numSkillUps = info.numSkillUps }
    end
  end
  return out
end

-- Live reagents of a recipe from the client (cross-check against the dataset).
function G.Schematic(recipeId)
  if not has(C_TradeSkillUI, "GetRecipeSchematic") then return nil end
  local ok, s = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeId, false)
  if not ok or type(s) ~= "table" then return nil end
  local reagents = {}
  for _, slot in ipairs(s.reagentSlotSchematics or {}) do
    local r = slot.reagents and slot.reagents[1]
    if r and r.itemID then reagents[#reagents + 1] = { r.itemID, slot.quantityRequired } end
  end
  return { reagents = reagents, output = s.outputItemID, min = s.quantityMin, max = s.quantityMax }
end

-- Must run from a hardware event (a button click): the client protects crafting.
function G.Craft(recipeId, count)
  if not has(C_TradeSkillUI, "CraftRecipe") then return false, "CraftRecipe unavailable" end
  local ok, err = pcall(C_TradeSkillUI.CraftRecipe, recipeId, count or 1)
  return ok, err
end

function G.ItemCount(itemId, includeBank)
  if C_Item and C_Item.GetItemCount then
    local ok, n = pcall(C_Item.GetItemCount, itemId, includeBank and true or false)
    if ok and type(n) == "number" then return n end
  end
  return 0
end

-- Chat link of a recipe, like Shift-click in Blizzard's recipe list. The client's own
-- link when it gives one (C_TradeSkillUI.GetRecipeLink, needs the profession data);
-- else the trade-skill spell link built from the dataset: |Henchant:<spellId>|h
-- [<Profession>: <Recipe>]|h, the same link the client makes for these recipes.
function G.RecipeLink(recipeId, profName, recipeName)
  if has(C_TradeSkillUI, "GetRecipeLink") then
    local ok, link = pcall(C_TradeSkillUI.GetRecipeLink, recipeId)
    if ok and type(link) == "string" and link ~= "" then return link end
  end
  if not recipeName then return nil end
  return ("|cffffd000|Henchant:%d|h[%s%s]|h|r"):format(recipeId,
    profName and (profName .. ": ") or "", recipeName)
end

function G.ItemName(itemId)
  if C_Item and C_Item.GetItemInfo then
    local ok, name, link = pcall(C_Item.GetItemInfo, itemId)
    if ok and name then return name, link end
    if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemId) end
  end
  return nil
end

function G.ItemStats(itemId)
  local _, link = G.ItemName(itemId)
  if not link then return nil end
  local fn = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
  if not fn then return nil end
  local ok, stats = pcall(fn, link)
  return ok and stats or nil
end

function G.PlayerKey()
  local guid = UnitGUID and UnitGUID("player")
  if type(guid) == "string" then return guid end
  return (UnitName and UnitName("player")) or "player"
end

-- Currency name from the client (C_CurrencyInfo.GetCurrencyInfo, forever API docs);
-- nil when unknown, never guessed.
function G.CurrencyName(id)
  if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
  local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
  return ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" and info.name or nil
end

-- "A" | "H" | nil (faction not readable, e.g. a neutral character): Engine/Faction.lua
function G.Faction()
  if not UnitFactionGroup then return nil end
  local ok, group = pcall(UnitFactionGroup, "player")
  return ok and ns.Faction.Side(group) or nil
end

-- The active specialization (talent tree): { index, name, points } or nil when unknown.
-- Forever has classic talent trees and no spec selection; GetSpecialization() answers
-- 1 (the first tree) for everyone, so it is trusted only when IsSpecSelectionEnabled
-- (class) is true, as Blizzard's Camelot PaperDollFrame does. Otherwise the tree with
-- the most talent points spent is the spec. No points, or a tie: unknown.
--
-- Points per tree, the way Forever's own talent window reads them (Blizzard_
-- PlayerSpells/Camelot/ClassTalents RefreshTreeHeaders): talents are traits. The
-- active config (C_ClassTalents.GetActiveConfigID, else C_SpecializationInfo.
-- GetCombatConfigIDForSpecGroup(active group)) has one tree (C_Traits.GetConfigInfo
-- .treeIDs[1]); each talent tree is a trait group of it (C_Traits.
-- GetGroupDisplayInfoByTreeID, left to right = tree 1, 2, 3), and C_Traits.
-- GetGroupCurrencyInfo(config, groups)[i].currencyInfos[1].spent is the "8" in the
-- tree header. GetSpecializationInfo's pointsSpent stays as a fallback: on Forever it
-- does not report them.
local function specInfo(i)
  local S = C_SpecializationInfo
  if not (S and S.GetSpecializationInfo) then return nil end
  local ok, _, name, _, _, _, _, points = pcall(S.GetSpecializationInfo, i, false, false, nil,
    UnitSex and UnitSex("player") or nil)
  if not ok or type(name) ~= "string" or name == "" then return nil end
  return name, type(points) == "number" and points or nil
end
local function specName(i) return (specInfo(i)) end

local function call(t, f, ...)
  if not (t and type(t[f]) == "function") then return nil end
  local ok, a = pcall(t[f], ...)
  if ok then return a end
  return nil
end

local function activeConfigID()
  local id = call(C_ClassTalents, "GetActiveConfigID")
  if type(id) == "number" then return id end
  local group = call(C_SpecializationInfo, "GetActiveSpecGroup", false, false) or 1
  id = call(C_SpecializationInfo, "GetCombatConfigIDForSpecGroup", group)
  return type(id) == "number" and id or nil
end

-- { points = {[tree] = n}, names = {[tree] = "Enhancement"} } from the trait config, or nil.
function G.TalentTreePoints()
  if not C_Traits then return nil end
  local config = activeConfigID()
  if not config then return nil end
  local info = call(C_Traits, "GetConfigInfo", config)
  local tree = type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1]
  if not tree then return nil end
  local groups = call(C_Traits, "GetGroupDisplayInfoByTreeID", tree)
  if type(groups) ~= "table" or #groups == 0 then return nil end
  local ids = {}
  for i, g in ipairs(groups) do ids[i] = g.groupID end
  local spent = {}
  for _, gi in ipairs(call(C_Traits, "GetGroupCurrencyInfo", config, ids) or {}) do
    local c = type(gi) == "table" and type(gi.currencyInfos) == "table" and gi.currencyInfos[1]
    if c and gi.traitNodeGroupID then spent[gi.traitNodeGroupID] = tonumber(c.spent) or 0 end
  end
  local out = { points = {}, names = {} }
  for i, g in ipairs(groups) do
    out.points[i] = spent[g.groupID] or 0
    out.names[i] = g.displayName
  end
  return out
end

local function selectionEnabled(S)
  if not S.IsSpecSelectionEnabled then return false end
  local classId = UnitClass and select(3, UnitClass("player"))
  local ok, on = pcall(S.IsSpecSelectionEnabled, classId)
  return ok and on == true
end

-- Pure: the tree with the most points (> 0), nil on a tie or nothing spent.
function G.MostPoints(points)
  local best, bestN, tie = nil, 0, false
  for i, n in pairs(points) do
    if n > bestN then best, bestN, tie = i, n, false
    elseif n == bestN and n > 0 then tie = true end
  end
  return (not tie) and best or nil
end

function G.Spec()
  local S = C_SpecializationInfo
  if S and selectionEnabled(S) and S.GetSpecialization then
    local ok, i = pcall(S.GetSpecialization)
    if ok and type(i) == "number" and i >= 1 then return { index = i, name = specName(i) } end
  end
  local traits = G.TalentTreePoints()
  if traits then
    local i = G.MostPoints(traits.points)
    if i then return { index = i, name = specName(i) or traits.names[i], points = traits.points[i] } end
  end
  local points = {}
  for i = 1, 4 do
    local name, n = specInfo(i)
    if not name then break end
    points[i] = n or 0
  end
  local i = G.MostPoints(points)
  return i and { index = i, name = specName(i), points = points[i] } or nil
end

-- One line for /profs gearspec: what the detection saw.
function G.SpecDebug()
  local t = G.TalentTreePoints()
  if not t then return "talent trees: not readable (no trait config)" end
  local parts = {}
  for i, n in ipairs(t.points) do parts[#parts + 1] = ("%s %d"):format(t.names[i] or ("tree " .. i), n) end
  return "talent points: " .. table.concat(parts, ", ")
end

-- Names of the class's specializations, by index (empty when the API is missing).
function G.SpecNames()
  local out = {}
  for i = 1, 4 do
    local n = specName(i)
    if not n then break end
    out[i] = n
  end
  return out
end

function G.PlayerInfo()
  local class, classId
  if UnitClass then class, classId = select(2, UnitClass("player")) end -- NOT `UnitClass and UnitClass(...)`: `and` keeps one value
  return { key = G.PlayerKey(), name = UnitName and UnitName("player"), class = class, classId = classId,
    level = UnitLevel and UnitLevel("player") or 1 }
end
