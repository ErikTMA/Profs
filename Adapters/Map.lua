-- Maps and waypoints. Verified in Gethe/wow-ui-source branch `forever`: C_Map.GetMapInfo /
-- GetBestMapForUnit / GetWorldPosFromMapPos / CanSetUserWaypointOnMap / SetUserWaypoint
-- (Blizzard_APIDocumentationGenerated/MapDocumentation.lua), C_SuperTrack.
-- SetSuperTrackedUserWaypoint, UiMapPoint.CreateFromCoordinates (Blizzard_ObjectAPI/
-- Mainline), CreateVector2D (Blizzard_SharedXML). TomTom is used when installed.
local _, ns = ...
local M = ns:NewModule("Map")

local sizes = {}

-- Width and height of a uiMap in yards, or nil. HereBeDragons (GatherMate2 ships it)
-- first, else two map corners through C_Map.GetWorldPosFromMapPos (world x runs
-- north-south, so the map's width is the world y span).
function M.ZoneSize(uiMapID)
  local c = sizes[uiMapID]
  if c ~= nil then return c and c[1], c and c[2] end
  local w, h
  local hbd = LibStub and LibStub("HereBeDragons-2.0", true)
  if hbd and hbd.GetZoneSize then
    local ok, a, b = pcall(hbd.GetZoneSize, hbd, uiMapID)
    if ok and type(a) == "number" and a > 0 then w, h = a, b end
  end
  if not w and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
    local ok, _, p0 = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(0, 0))
    local ok2, _, p1 = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(1, 1))
    if ok and ok2 and type(p0) == "table" and type(p1) == "table" and p0.x and p1.x then
      w, h = math.abs(p0.y - p1.y), math.abs(p0.x - p1.x)
      if w <= 0 or h <= 0 then w, h = nil, nil end
    end
  end
  sizes[uiMapID] = w and { w, h } or false
  return w, h
end

local function info(uiMapID)
  if not (C_Map and C_Map.GetMapInfo) then return nil end
  local ok, i = pcall(C_Map.GetMapInfo, uiMapID)
  return ok and type(i) == "table" and i or nil
end

-- True for dungeon and raid maps (Enum.UIMapType.Dungeon); nil when unknown.
function M.IsInstance(uiMapID)
  local i = info(uiMapID)
  if not i or i.mapType == nil then return nil end
  local dungeon = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4
  return i.mapType == dungeon
end

-- The client's (localized) name of a map, else `fallback`.
function M.ZoneName(uiMapID, fallback)
  local i = info(uiMapID)
  return (i and type(i.name) == "string" and i.name ~= "" and i.name) or fallback
end

-- The continent (Enum.UIMapType.Continent) a map lies on, through its parents; nil
-- when unknown (Azeroth / cosmic maps, no C_Map).
function M.Continent(uiMapID)
  local cont = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
  local id, guard = uiMapID, 0
  while id and guard < 8 do
    local i = info(id)
    if not i then return nil end
    if i.mapType == cont then return id end
    id, guard = i.parentMapID, guard + 1
  end
  return nil
end

function M.PlayerMap()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
  return ok and id or nil
end

-- A waypoint at x, y (percent) on a uiMap. Returns "tomtom", "map" or nil.
function M.SetWaypoint(uiMapID, x, y, title)
  local tt = _G.TomTom
  if type(tt) == "table" and type(tt.AddWaypoint) == "function" then
    local ok = pcall(tt.AddWaypoint, tt, uiMapID, x / 100, y / 100, { title = title, from = ns.displayName })
    if ok then return "tomtom" end
  end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(uiMapID) then return nil end
    local ok, set = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(uiMapID, x / 100, y / 100))
    if ok and set ~= false then
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
      end
      return "map"
    end
  end
  return nil
end
