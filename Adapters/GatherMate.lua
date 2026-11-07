-- GatherMate2 (optional): read the nodes the player recorded, and add Profs!' spawn data
-- to GatherMate2's database so its map and minimap pins show them.
--
-- API used (Nevcairiel/GatherMate2, GatherMate2.lua): the AceAddon is the global
-- GatherMate2; gmdbs[type] is a proxy over the saved tables (__gm2_base_storage, plus
-- one table per storage add-on in __gm2_storage_map), each zone -> {coord -> nodeID};
-- GetNameForNode / GetIDForNode map GatherMate's node ids to LOCALIZED names
-- (AceLocale "GatherMate2Nodes" maps the English name to the client's);
-- InjectNode2(zone, coord, type, nodeID) is the call its own importers use (no
-- per-node message; it honours dbLocks and its map blacklist); profile.cleanupRange
-- [type] is how close (yards) two nodes are one; EncodeLoc(x, y) packs x, y (0..1) as floor(x*10000)*1e6 + floor(y*10000)*100, the
-- same packing as Wowhead's spawn coordinates. Types: "Herb Gathering", "Mining".
local _, ns = ...
local GM = ns:NewModule("GatherMate")

GM.TYPE = { [182] = "Herb Gathering", [186] = "Mining" }

function GM.Addon()
  local gm = _G.GatherMate2
  if type(gm) ~= "table" or type(gm.gmdbs) ~= "table" or type(gm.GetNameForNode) ~= "function" then
    return nil
  end
  return gm
end

function GM.Available() return GM.Addon() ~= nil end

-- The client's name for an English node name, as GatherMate2 keys it.
local function localized(name)
  local AL = LibStub and LibStub("AceLocale-3.0", true)
  local ok, NL = false, nil
  if AL and AL.GetLocale then ok, NL = pcall(AL.GetLocale, AL, "GatherMate2Nodes", true) end
  -- rawget: AceLocale reports every missing key, and Forever-new nodes are missing
  local l = ok and type(NL) == "table" and rawget(NL, name)
  return type(l) == "string" and l or name
end
GM.Localized = localized

-- Our node id per GatherMate2 name (the lowest id of a name's variants).
local function nodesByName(ds, prof)
  local out = {}
  for id, n in pairs(ds.nodes or {}) do
    if n.prof == prof then
      local l = localized(n.n)
      if not out[l] or id < out[l] then out[l] = id end
    end
  end
  return out
end

local function stores(db)
  if type(db.__gm2_base_storage) == "table" then
    local list = { db.__gm2_base_storage }
    for _, t in pairs(db.__gm2_storage_map or {}) do
      if type(t) == "table" then list[#list + 1] = t end
    end
    return list
  end
  return { db } -- a database registered as a plain table
end

function GM.Decode(coord)
  return math.floor(coord / 1000000) / 100, math.floor(coord % 1000000 / 100) / 100
end

-- The player's recorded nodes of a profession as engine points
-- { {zone, x, y, node}, ... } (percent), and how many GatherMate2 nodes Profs! does not
-- know (Forever-new nodes, other expansions). nil when GatherMate2 is not loaded.
function GM.Points(ds, prof)
  local gm, typ = GM.Addon(), GM.TYPE[prof]
  local db = gm and typ and gm.gmdbs[typ]
  if type(db) ~= "table" then return nil end
  local byName = nodesByName(ds, prof)
  local out, unknown = {}, 0
  for _, store in ipairs(stores(db)) do
    for zone, nodes in pairs(store) do
      if type(zone) == "number" and type(nodes) == "table" then
        for coord, nodeID in pairs(nodes) do
          local ok, name = pcall(gm.GetNameForNode, gm, typ, nodeID)
          local id = ok and name and byName[name]
          if id and type(coord) == "number" then
            local x, y = GM.Decode(coord)
            out[#out + 1] = { zone = zone, x = x, y = y, node = id }
          else
            unknown = unknown + 1
          end
        end
      end
    end
  end
  return out, unknown
end

-- Existing nodes of one zone in 1%-cells, to test "a node within `range` yards" in
-- O(1) (GatherMate2's FindNearbyNode scans the whole zone per call). w, h: the zone's
-- size in yards; nil = unknown, then only the exact coordinate counts.
local function nearIndex(existing, w, h, range)
  local cells = {}
  local function add(coord)
    local x, y = GM.Decode(coord)
    local key = math.floor(x) * 1000 + math.floor(y)
    cells[key] = cells[key] or {}
    table.insert(cells[key], { x, y })
  end
  for coord in pairs(existing or {}) do if type(coord) == "number" then add(coord) end end
  local idx = { coords = {} }
  for coord in pairs(existing or {}) do idx.coords[coord] = true end
  -- cells to search on each side: the range in percent of the map
  local rx = w and math.ceil(range / (w / 100)) or 0
  local ry = h and math.ceil(range / (h / 100)) or 0
  function idx:near(coord)
    if self.coords[coord] then return true end
    if not (w and h) then return false end
    local x, y = GM.Decode(coord)
    local cx, cy = math.floor(x), math.floor(y)
    for dx = -rx, rx do
      for dy = -ry, ry do
        for _, p in ipairs(cells[(cx + dx) * 1000 + cy + dy] or {}) do
          local ex, ey = (p[1] - x) * w / 100, (p[2] - y) * h / 100
          if ex * ex + ey * ey <= range * range then return true end
        end
      end
    end
    return false
  end
  function idx:add(coord) self.coords[coord] = true; add(coord) end
  return idx
end

-- Add Profs!' spawns of a profession to GatherMate2. A spawn is skipped when GatherMate2
-- already has a node within its cleanup range there (or at the same coordinate when the
-- zone's size is unknown). Returns { added, present, unknown = {names} } or nil,
-- reason ("missing" | "locked").
function GM.Import(ds, prof)
  local gm, typ = GM.Addon(), GM.TYPE[prof]
  if not (gm and typ and type(gm.InjectNode2) == "function" and type(gm.EncodeLoc) == "function") then
    return nil, "missing"
  end
  local profile = gm.db and gm.db.profile
  if profile and profile.dbLocks and profile.dbLocks[typ] then return nil, "locked" end
  local range = profile and profile.cleanupRange and profile.cleanupRange[typ] or 15
  local res, unknown, indexes = { added = 0, present = 0, unknown = {} }, {}, {}
  local db = gm.gmdbs[typ]
  for _, id in ipairs(ns.Gathering.NodesOf(ds, prof)) do
    local nd = ds.nodes[id]
    local nid = gm.GetIDForNode and gm:GetIDForNode(typ, localized(nd.n))
    if not nid then
      if not unknown[nd.n] then unknown[nd.n] = true; res.unknown[#res.unknown + 1] = nd.n end
    else
      for zone, list in pairs(nd.spawns) do
        local idx = indexes[zone]
        if not idx then
          local w, h = ns.Map.ZoneSize(zone)
          idx = nearIndex(db[zone], w, h, range)
          indexes[zone] = idx
        end
        for _, v in ipairs(list) do
          local x, y = ns.Gathering.Unpack(v)
          local coord = gm:EncodeLoc(x / 100, y / 100)
          if idx:near(coord) then
            res.present = res.present + 1
          else
            gm:InjectNode2(zone, coord, typ, nid)
            idx:add(coord)
            res.added = res.added + 1
          end
        end
      end
    end
  end
  table.sort(res.unknown)
  if res.added > 0 and gm.SendMessage then pcall(gm.SendMessage, gm, "GatherMate2ConfigChanged") end
  return res
end
