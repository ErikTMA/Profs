-- Dataset schema (version 1). A dataset is the generated profession data for ONE game
-- flavor (Data/<flavor>/Dataset.lua).
--
--   meta        { schema=1, flavor="forever", generated="<iso8601>", source="..." }
--   recipes     [spellId] = {
--                 prof     skill-line id (197 Tailoring, 333 Enchanting, ...)
--                 name     display name (display only; logic keys on ids)
--                 learn    skill required to learn
--                 colors   { orange, yellow, green, grey } skill thresholds
--                 reagents { {itemId, count}, ... }
--                 creates  { itemId, min, max } or nil (enchants create nothing)
--                 skillups points per successful skill-up (default 1)
--                 spec     specialization required (spell id), excluded unless the
--                          character has it (Optimizer opts.specs)
--                 sources  { {t="trainer", cost=copper, npcs={...}}
--                          | {t="vendor", item=recipeItemId, cost=copper, npcs={...}, limited=bool}
--                          | {t="reputation", item=, faction=, standing=}
--                          | {t="token", item=recipeItemId, cost=copper (often 0),
--                             currencies={{currencyId,n}}, costItems={{itemId,n}},
--                             npcs={...}, limited=bool}  bought with a currency or
--                             items (e.g. Merchant's Favor); never a gold price
--                          | {t="quest", quest=} | {t="other"}
--                          | {t="drop", item=recipeItemId, mobs={{npcId, percent, kills, 1=pickpocket|nil}},
--                             nmobs=n}  mobs: the best DROP_MOBS of the n mobs dropping
--                             it (well-sampled first); percent = drops / kills seen
--                             on Wowhead, -1 = drops but the rate is not measured;
--                             mobs absent = the data names none (containers, fishing)
--                          | {t="starter"} granted with the Apprentice rank
--                          ; unknownCost=true: the source is known, its price is not }
--   professions [skillLine] = { ranks = { {name, max, cost, charLevel, learnAt}, ... },
--                               trainers = {npcId, ...} (gathering professions: who
--                               teaches the ranks) }
--   nodes       [objectId] = { n=name, prof=182 Herbalism | 186 Mining, skill=required,
--                 (skinnable mobs: [-npcId] = { ..., prof=393 Skinning, lv={lo, hi}, skill
--                 from the level; spawns one per 1% cell of the map })
--                 yields = { {itemId, percent, min, max}, ... } most likely first,
--                 spawns = { [uiMapId] = { xxxyyy, ... } } every spawn, x and y in
--                 tenths of a percent (382333 = 38.2, 33.3) }   (optional)
--   zones       [uiMapId] = { n=name, lv={lo, hi} level spread of its hostile mobs,
--                 na/nh/nb = npcs friendly to the Alliance only / Horde only / both }
--   items       [itemId] = { n=name, q=quality, il=itemLevel, rl=reqLevel,
--                            vsell=copper, vbuy=copper (sold by a vendor, unlimited),
--                            c=classId, sc=subclassId, slot=inventoryType,
--                            de={ {itemId, chance, min, max}, ... } measured DE yield }
--   npcs        [npcId]  = { n=name, zone=name, x=percent, y=percent, side="A"|"H"|"B",
--                            fa=1|0|-1, fh=1|0|-1 }  reaction to Alliance / Horde:
--                            friendly / neutral / hostile; absent = not in the data
--                            (Engine/Faction.lua decides access from these)
--                            mobs (named by drop sources): mob=true, lv={min,max},
--                            cl=1 elite|2 rare elite|3 boss|4 rare; instance mobs have
--                            a zone but no x/y
--
-- Everything is keyed on ids; names are for display only.
local _, ns = ...
local S = ns:NewModule("Schema")

S.VERSION = 1

S.SOURCE_TYPES = {
  trainer = true, vendor = true, reputation = true, quest = true, drop = true, other = true,
  token = true,
  starter = true, -- granted with the Apprentice rank
}

local function isInt(v) return type(v) == "number" and v == math.floor(v) end

-- Returns ok, errors (list of strings). Never throws on bad data.
function S.Validate(ds)
  local errs = {}
  local function err(fmt, ...) errs[#errs + 1] = string.format(fmt, ...) end
  if type(ds) ~= "table" then return false, { "dataset is not a table" } end
  if type(ds.meta) ~= "table" then err("meta missing")
  elseif ds.meta.schema ~= S.VERSION then err("meta.schema %s ~= %d", tostring(ds.meta.schema), S.VERSION) end
  if type(ds.recipes) ~= "table" then err("recipes missing") end
  if type(ds.items) ~= "table" then err("items missing") end
  if #errs > 0 then return false, errs end

  for id, r in pairs(ds.recipes) do
    local where = "recipe " .. tostring(id)
    if not isInt(id) then err("%s: key not an integer", where) end
    if not isInt(r.prof) then err("%s: prof", where) end
    if type(r.colors) ~= "table" or #r.colors ~= 4 then
      err("%s: colors must have 4 thresholds", where)
    else
      for i = 1, 4 do
        if not isInt(r.colors[i]) then err("%s: colors[%d]", where, i) end
      end
      for i = 2, 4 do
        if isInt(r.colors[i]) and isInt(r.colors[i - 1]) and r.colors[i] < r.colors[i - 1] then
          err("%s: colors not ascending", where)
        end
      end
    end
    if r.learn ~= nil and not isInt(r.learn) then err("%s: learn", where) end
    if type(r.reagents) ~= "table" then
      err("%s: reagents", where)
    else
      for i, rg in ipairs(r.reagents) do
        if type(rg) ~= "table" or not isInt(rg[1]) or not isInt(rg[2]) or rg[2] <= 0 then
          err("%s: reagent %d", where, i)
        end
      end
    end
    if r.creates ~= nil then
      local c = r.creates
      if type(c) ~= "table" or not isInt(c[1]) then err("%s: creates", where) end
    end
    if type(r.sources) ~= "table" then
      err("%s: sources", where)
    else
      for i, s in ipairs(r.sources) do
        if type(s) ~= "table" or not S.SOURCE_TYPES[s.t] then err("%s: source %d type", where, i)
        elseif s.mobs ~= nil then
          if type(s.mobs) ~= "table" then err("%s: source %d mobs", where, i) else
            for j, m in ipairs(s.mobs) do
              if type(m) ~= "table" or not isInt(m[1]) or type(m[2]) ~= "number" or not isInt(m[3]) then
                err("%s: source %d mob %d", where, i, j)
              end
            end
          end
        end
      end
    end
  end
  if ds.nodes ~= nil and type(ds.nodes) ~= "table" then err("nodes not a table") end
  for id, n in pairs(type(ds.nodes) == "table" and ds.nodes or {}) do
    local where = "node " .. tostring(id)
    if not isInt(id) then err("%s: key not an integer", where) end
    if type(n) ~= "table" or not isInt(n.prof) or not isInt(n.skill) or type(n.spawns) ~= "table"
        or type(n.yields) ~= "table" then
      err("%s: needs prof, skill, yields, spawns", where)
    else
      for zone, list in pairs(n.spawns) do
        if not isInt(zone) or type(list) ~= "table" then err("%s: spawns of %s", where, tostring(zone))
        else
          for _, v in ipairs(list) do
            if not isInt(v) or v < 0 or v > 999999 then
              err("%s: spawn %s", where, tostring(v)); break
            end
          end
        end
      end
    end
  end
  if ds.zones ~= nil and type(ds.zones) ~= "table" then err("zones not a table") end
  for id, it in pairs(ds.items) do
    if not isInt(id) then err("item %s: key not an integer", tostring(id)) end
    if type(it) ~= "table" then err("item %s: not a table", tostring(id)) end
  end
  return #errs == 0, errs
end
