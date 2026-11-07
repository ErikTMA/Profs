-- Bootstrap: SavedVariables, logging, slash command. Loaded LAST (see Profs.toc).
local _, ns = ...

local LEVELS = { error = 1, warn = 2, info = 3, debug = 4 }
ns.logLevel = LEVELS.info

function ns.Log(level, msg)
  if (LEVELS[level] or 3) > ns.logLevel then return end
  local line = "|cffd4a017Profs!|r " .. (level == "info" and "" or ("[" .. level .. "] ")) .. tostring(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) else print(line) end
end

-- The flavor whose dataset is active. The Game adapter detects it; default forever.
function ns.ActiveDataset()
  local flavor = (ns.Game and ns.Game.Flavor and ns.Game.Flavor()) or "forever"
  return ns.Registry.Get(flavor), flavor
end

local function onAddonLoaded()
  ProfsDB = ns.Routes.InitDB(ProfsDB)
  ProfsCharDB = ns.Routes.InitChar(ProfsCharDB)
  ns.db, ns.cdb = ProfsDB, ProfsCharDB
  if ProfsDB.settings.debug then ns.logLevel = LEVELS.debug end
  ns.Events.Fire("PROFS_LOADED")
end

local commands = ns.commands

commands.status = function()
  local ds, flavor = ns.ActiveDataset()
  ns.Log("info", ("flavor %s, dataset %s"):format(flavor,
    ds and ("%d recipes (%s)"):format(ns.Util.count(ds.recipes), tostring(ds.meta.generated)) or "MISSING"))
  if not ds then
    ns.Log("warn", "No recipe dataset for this client. See README: Exporting data.")
  end
  if ns.Game and ns.Game.Describe then ns.Log("info", ns.Game.Describe()) end
end

commands.debug = function()
  ProfsDB.settings.debug = not ProfsDB.settings.debug
  ns.logLevel = ProfsDB.settings.debug and LEVELS.debug or LEVELS.info
  ns.Log("info", "debug " .. (ProfsDB.settings.debug and "on" or "off"))
end

commands.help = function()
  ns.Log("info", "/profs [show|options|status|recommend|gear|save|load|reset|ah|prices|alerts|minimap|resetui|debug|help]")
end

commands.resetui = function()
  ns.Widgets.ResetPositions()
  ns.Log("info", "window positions reset")
end

local function slash(input)
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  local fn = commands[cmd ~= "" and cmd or "show"] or commands.help
  fn(rest)
end

if CreateFrame then
  local f = CreateFrame("Frame")
  f:RegisterEvent("ADDON_LOADED")
  f:RegisterEvent("PLAYER_LOGIN")
  f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ns.name then
      onAddonLoaded()
    elseif event == "PLAYER_LOGIN" then
      ns.Events.Fire("PLAYER_LOGIN")
    end
  end)
  SLASH_PROFS1 = "/profs"
  SlashCmdList.PROFS = slash
end

ns.Slash = slash

-- Launchers: the minimap button (UI/MinimapButton.lua) and the addon compartment
-- (Blizzard_Minimap on forever reads ## AddonCompartmentFunc / ...OnEnter / ...OnLeave
-- and ## IconTexture from Profs.toc and calls the named globals with (addonName,
-- buttonName | button)). Both share these actions.
ns.LAUNCHER_LINES = {
  "Click: route for the open profession",
  "Shift-click: craftable gear upgrades",
  "Right-click: which professions to pick",
  "Ctrl-click: options",
}

function ns.LauncherClick(button)
  if IsControlKeyDown and IsControlKeyDown() then
    commands.options()
  elseif IsShiftKeyDown and IsShiftKeyDown() then
    commands.gear()
  elseif button == "RightButton" then
    commands.recommend()
  elseif ns.Game and ns.Game.OpenProfession and ns.Game.OpenProfession() then
    ns.Sidecar.Open()
  else
    commands.status()
    ns.Log("info", "open a profession window to see its route")
  end
end

function Profs_OnAddonCompartmentClick(_, button)
  ns.LauncherClick(button)
end

function Profs_OnAddonCompartmentEnter(_, owner)
  if not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:SetText(ns.displayName)
  for _, l in ipairs(ns.LAUNCHER_LINES) do GameTooltip:AddLine(l, 1, 1, 1) end
  GameTooltip:Show()
end

function Profs_OnAddonCompartmentLeave()
  if GameTooltip then GameTooltip:Hide() end
end
ns.OnAddonLoaded = onAddonLoaded
