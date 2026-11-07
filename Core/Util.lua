local _, ns = ...
local U = ns:NewModule("Util")

U.INF = math.huge

function U.round(x) return math.floor(x + 0.5) end

function U.clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

function U.copy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local c = {}
  seen[t] = c
  for k, v in pairs(t) do c[U.copy(k, seen)] = U.copy(v, seen) end
  return c
end

-- Overlay `src` onto a copy of `defaults` (one level of nested tables merged).
function U.merge(defaults, src)
  local out = U.copy(defaults or {})
  for k, v in pairs(src or {}) do
    if type(v) == "table" and type(out[k]) == "table" then
      for k2, v2 in pairs(v) do out[k][k2] = v2 end
    else
      out[k] = v
    end
  end
  return out
end

function U.sortedKeys(t, cmp)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, cmp)
  return keys
end

function U.count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Copper -> "1g 23s 45c". Negative values keep a leading "-". nil -> "?".
function U.money(copper)
  if copper == nil then return "?" end
  if copper == U.INF then return "n/a" end
  local neg = copper < 0
  copper = math.floor(math.abs(copper) + 0.5)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 or g > 0 then parts[#parts + 1] = s .. "s" end
  parts[#parts + 1] = c .. "c"
  return (neg and "-" or "") .. table.concat(parts, " ")
end
