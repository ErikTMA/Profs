-- Owned-item tracking across bags, bank, mail and alts (same account, this
-- client's SavedVariables). Bags/bank come from C_Item.GetItemCount (bank counts
-- are the client's cache, refreshed when the bank opens); mail is scanned when the
-- inbox updates (GetInboxNumItems / GetInboxItem). Only items the active routes
-- need are recorded, to keep SavedVariables small.
local _, ns = ...
local INV = ns:NewModule("Inventory")

INV.tracked = {}

function INV.Track(itemIds)
  for _, id in ipairs(itemIds) do INV.tracked[id] = true end
end

local function charRecord()
  local db = ns.db
  if not db then return nil end
  local me = ns.Game.PlayerInfo()
  local c = db.chars[me.key]
  if not c then c = { items = {}, mail = {} }; db.chars[me.key] = c end
  c.name, c.class, c.level = me.name, me.class, me.level
  c.items = c.items or {}
  c.mail = c.mail or {}
  return c
end

function INV.Snapshot()
  local c = charRecord()
  if not c then return end
  for id in pairs(INV.tracked) do
    local bags = ns.Game.ItemCount(id, false)
    local all = ns.Game.ItemCount(id, true)
    c.items[id] = { bags = bags, bank = math.max(0, all - bags) }
  end
  c.profs = {}
  for line, p in pairs(ns.Game.Professions()) do c.profs[line] = p.rank end
end

function INV.ScanMail()
  local c = charRecord()
  if not c or not GetInboxNumItems or not GetInboxItem then return end
  local mail = {}
  local maxAtt = ATTACHMENTS_MAX_RECEIVE or 16
  for i = 1, (GetInboxNumItems() or 0) do
    for a = 1, maxAtt do
      local _, id, _, count = GetInboxItem(i, a)
      if id and count then mail[id] = (mail[id] or 0) + count end
    end
  end
  c.mail = mail
end

-- have(itemId) for Engine/Shopping: { bags, bank, mail, alts }
function INV.Have(itemId)
  local db = ns.db
  local me = ns.Game.PlayerKey()
  local bags = ns.Game.ItemCount(itemId, false)
  local out = { bags = bags, bank = math.max(0, ns.Game.ItemCount(itemId, true) - bags) }
  if db then
    local mine = db.chars[me]
    if mine and mine.mail and mine.mail[itemId] then out.mail = mine.mail[itemId] end
    local alts = 0
    for key, c in pairs(db.chars) do
      if key ~= me then
        local rec = c.items and c.items[itemId]
        if rec then alts = alts + (rec.bags or 0) + (rec.bank or 0) end
        if c.mail and c.mail[itemId] then alts = alts + c.mail[itemId] end
      end
    end
    if alts > 0 then out.alts = alts end
  end
  return out
end

-- Highest enchanting skill on this account (self first), for disenchant synergy.
function INV.EnchantingSkill()
  local best
  local own = ns.Game.Professions()[ns.Professions.ENCHANTING]
  if own then best = own.rank end
  for _, c in pairs((ns.db and ns.db.chars) or {}) do
    local s = c.profs and c.profs[ns.Professions.ENCHANTING]
    if s and (not best or s > best) then best = s end
  end
  return best
end
