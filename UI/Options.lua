-- Options in the game's Settings panel (Settings API, Blizzard_Settings_Shared on
-- forever): Esc > Options > AddOns > Profs!. Proxy settings read and write ProfsDB /
-- ProfsCharDB directly, so the slash commands and this panel always agree.
-- /profs options (and Ctrl-click on a launcher) opens it.
local _, ns = ...
local O = ns:NewModule("Options")

-- Every option: key, label, tooltip, type ("boolean" | "number" | "string"), default,
-- get(), set(v), and for numbers min/max/step, for strings choices { {value, label} }.
function O.Definitions()
  local function settings() return ns.db.settings end
  local function alerts()
    settings().gearAlerts = settings().gearAlerts or {}
    return settings().gearAlerts
  end
  local function refreshRoute()
    if ns.Sidecar and ns.Sidecar.frame and ns.Sidecar.frame:IsShown() then ns.Sidecar.RequestRefresh() end
  end
  return {
    { key = "column", label = "Profession window column",
      tooltip = "Show the Profs! route column inside the profession window (this character).",
      type = "boolean", default = true,
      get = function() return ns.cdb.columnCollapsed ~= true end,
      set = function(v)
        ns.cdb.columnCollapsed = (not v) or nil
        ns.Sidecar.collapsed = not v
        local pf = ns.Embed.Frame()
        if pf and pf:IsShown() then ns.Sidecar.OnShow() end
      end },
    { key = "gearColumn", label = "Craftable upgrades in the character frame",
      tooltip = "Widen the character frame with a column of gear you can craft for your level.",
      type = "boolean", default = true,
      get = function() return settings().gearColumn ~= false end,
      set = function(v) settings().gearColumn = v and nil or false; ns.GearColumn.Update() end },
    { key = "alerts", label = "Level-up upgrade alerts",
      tooltip = "When you level up, list craftable upgrades that just became equippable.",
      type = "boolean", default = true,
      get = function() return alerts().enabled ~= false end,
      set = function(v) alerts().enabled = v and true or false end },
    { key = "alertPct", label = "Alert threshold (%)",
      tooltip = "Only announce upgrades at least this much better than what you wear.",
      type = "number", default = ns.GearAlert.DEFAULTS.minPct, min = 1, max = 50, step = 1,
      get = function() return alerts().minPct or ns.GearAlert.DEFAULTS.minPct end,
      set = function(v) alerts().minPct = v end },
    { key = "gearSpec", label = "Score gear for",
      tooltip = "Which specialization (or Pawn scale) rates craftable upgrades, for this character. "
        .. "Active specialization follows your talents (/profs gearspec).",
      type = "string", default = "auto", choicesFn = function() return ns.Pawn.Choices() end,
      get = function() return ns.cdb.gearSpec or "auto" end,
      set = function(v)
        ns.cdb.gearSpec = v ~= "auto" and v or nil
        if ns.GearColumn.RequestUpdate then ns.GearColumn.RequestUpdate() end
      end },
    { key = "vendorTooltip", label = "Nearest vendor in item tooltips",
      tooltip = "On items a vendor sells: the nearest friendly or neutral vendor, its "
        .. "coordinates and how far it is.",
      type = "boolean", default = true,
      get = function() return settings().vendorTooltip ~= false end,
      set = function(v) settings().vendorTooltip = v and nil or false end },
    { key = "colorblind", label = "Colour-blind skill-up markers",
      tooltip = "Add +++ / ++ / + after orange / yellow / green route steps. Off by default "
        .. "unless the game's colour-blind mode is on.",
      type = "boolean", default = false,
      get = function() return ns.Theme.Colorblind() end,
      set = function(v) settings().colorblind = v and true or false; refreshRoute() end },
    { key = "pricePolicy", label = "Price choice",
      tooltip = "Precedence: the first fresh source in your order wins. Lowest: the cheapest "
        .. "fresh price of any source (/profs prices).",
      type = "string", default = "precedence",
      choices = { { "precedence", "Source order" }, { "lowest", "Lowest price" } },
      get = function() return settings().pricePolicy or "precedence" end,
      set = function(v)
        settings().pricePolicy = v
        ns.PriceSources.epoch = ns.PriceSources.epoch + 1
        refreshRoute()
      end },
    { key = "minimap", label = "Minimap button",
      tooltip = "Show the Profs! button on the minimap (this character; /profs minimap).",
      type = "boolean", default = true,
      get = function() return ns.MinimapButton.Shown() end,
      set = function(v) ns.MinimapButton.SetShown(v) end },
  }
end

local function available()
  return Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting
    and Settings.RegisterAddOnCategory and Settings.VarType
end

function O.Register()
  if O.category or not available() then return O.category end
  local category = Settings.RegisterVerticalLayoutCategory(ns.displayName)
  for _, d in ipairs(O.Definitions()) do
    local varType = Settings.VarType[d.type == "boolean" and "Boolean" or d.type == "number" and "Number" or "String"]
    local setting = Settings.RegisterProxySetting(category, "PROFS_" .. d.key:upper(), varType, d.label,
      d.default, d.get, d.set)
    if d.type == "boolean" then
      Settings.CreateCheckbox(category, setting, d.tooltip)
    elseif d.type == "number" then
      local opts = Settings.CreateSliderOptions(d.min, d.max, d.step)
      if opts.SetLabelFormatter and MinimalSliderWithSteppersMixin then
        opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
      end
      Settings.CreateSlider(category, setting, opts, d.tooltip)
    else
      local function options()
        local c = Settings.CreateControlTextContainer()
        for _, ch in ipairs(d.choicesFn and d.choicesFn() or d.choices) do c:Add(ch[1], ch[2]) end
        return c:GetData()
      end
      Settings.CreateDropdown(category, setting, options, d.tooltip)
    end
  end
  -- a button for /profs resetui
  if CreateSettingsButtonInitializer and SettingsPanel and SettingsPanel.GetLayout then
    local ok, layout = pcall(SettingsPanel.GetLayout, SettingsPanel, category)
    if ok and layout and layout.AddInitializer then
      layout:AddInitializer(CreateSettingsButtonInitializer("Window positions", "Reset",
        function() ns.commands.resetui() end, "Put every Profs! window back at its default place.", true))
    end
  end
  Settings.RegisterAddOnCategory(category)
  O.category = category
  return category
end

function O.Open()
  local c = O.Register()
  if c and Settings.OpenToCategory then
    Settings.OpenToCategory(c.GetID and c:GetID() or c.ID)
    return true
  end
  ns.Log("info", "options: /profs show | minimap | alerts on|off|pct <n> | prices | resetui")
  return false
end

ns.Events.On("PROFS_LOADED", function()
  local ok, err = pcall(O.Register)
  if not ok then ns.Log("debug", "options panel unavailable: " .. tostring(err)) end
end)

ns.commands.options = O.Open
ns.commands.config = O.Open
