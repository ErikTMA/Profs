-- Profs! namespace. Every file receives (addonName, ns) from the client's loader.
local ADDON, ns = ...

ns.name = ADDON or "Profs"
ns.displayName = "Profs!"
ns.modules = ns.modules or {}
ns.commands = ns.commands or {} -- /profs subcommands; UI modules add theirs at load

-- One global handle for slash commands, other addons and /dump debugging.
_G.Profs = ns

function ns:NewModule(name)
  assert(type(name) == "string" and name ~= "", "module name required")
  assert(not self.modules[name], "duplicate module: " .. name)
  local m = { name = name }
  self.modules[name] = m
  self[name] = m
  return m
end
