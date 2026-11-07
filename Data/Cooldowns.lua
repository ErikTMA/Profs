-- Recipes on a long (daily or multi-day) cooldown. They cannot be spammed for skill
-- points, so the optimizer excludes them unless the user allows them.
--
-- The cooldown itself is NOT in the generated dataset; this list holds the Classic Era
-- cooldown crafts. Each id was checked against the exported WoW Forever dataset
-- (2026-11-06) and resolves there to the recipe named beside it.
local _, ns = ...
local C = ns:NewModule("Cooldowns")

C.spells = {
  [18560] = true, -- Mooncloth
  [17187] = true, -- Transmute: Arcanite
  [11479] = true, -- Transmute: Iron to Gold
  [11480] = true, -- Transmute: Mithril to Truesilver
  [17559] = true, -- Transmute: Air to Fire
  [17560] = true, -- Transmute: Fire to Earth
  [17561] = true, -- Transmute: Earth to Water
  [17562] = true, -- Transmute: Water to Air
  [17563] = true, -- Transmute: Undeath to Water
  [17564] = true, -- Transmute: Water to Undeath
  [17565] = true, -- Transmute: Life to Earth
  [17566] = true, -- Transmute: Earth to Life
  [25146] = true, -- Transmute: Elemental Fire
}

function C.Has(recipeId) return C.spells[recipeId] == true end
