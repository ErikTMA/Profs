-- Holds the validated datasets per flavor and derived indexes.
local _, ns = ...
local R = ns:NewModule("Registry")

local datasets = {}

local function buildIndexes(ds)
  local byProf, producers = {}, {}
  for id, r in pairs(ds.recipes) do
    r.id = id
    r.learn = r.learn or r.colors[1]
    r.skillups = r.skillups or 1
    byProf[r.prof] = byProf[r.prof] or {}
    table.insert(byProf[r.prof], r)
    if r.creates then
      local item = r.creates[1]
      producers[item] = producers[item] or {}
      table.insert(producers[item], r)
    end
  end
  for _, list in pairs(byProf) do
    table.sort(list, function(a, b)
      if a.learn ~= b.learn then return a.learn < b.learn end
      return a.id < b.id
    end)
  end
  ds.recipesByProf = byProf
  ds.producers = producers
  ds.npcs = ds.npcs or {}
end

-- Register a dataset. Invalid data is refused loudly (returns false + errors),
-- never half-loaded.
function R.Register(flavor, ds)
  local ok, errs = ns.Schema.Validate(ds)
  if not ok then
    R.lastErrors = errs
    if ns.Log then
      ns.Log("error", ("dataset %s rejected: %d errors, first: %s"):format(flavor, #errs, errs[1]))
    end
    return false, errs
  end
  buildIndexes(ds)
  datasets[flavor] = ds
  return true
end

function R.Get(flavor) return datasets[flavor] end

function R.Flavors() return ns.Util.sortedKeys(datasets) end

function R.Clear() datasets = {} end
