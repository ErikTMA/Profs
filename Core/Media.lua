-- Textures. The approved Profs! emblem ships as Media/ProfsIcon.tga (64 px) and
-- Media/ProfsLogo.tga (256 px). If a file cannot be loaded, every use falls back to a
-- stock game icon. Texture:SetTexture returns false for a missing file (documented
-- `success` result, SimpleTextureBase API, forever 1.60.1), so the fallback is
-- decided at runtime and no missing-texture square is ever shown.
local _, ns = ...
local M = ns:NewModule("Media")

M.ICON = "Interface\\AddOns\\Profs\\Media\\ProfsIcon"
M.LOGO = "Interface\\AddOns\\Profs\\Media\\ProfsLogo"
-- the minimap button badge, drawn for the 26 px button
M.MINIMAP = "Interface\\AddOns\\Profs\\Media\\MinimapIcon"
M.FALLBACK = "Interface\\Icons\\Trade_BlackSmithing"   -- stock icon, NOT the Profs! logo

-- Set `which` ("ICON" | "LOGO" | "MINIMAP") on a texture; returns the path actually shown.
function M.Apply(texture, which)
  local path = M[which or "ICON"] or M.ICON
  local ok = texture:SetTexture(path)
  if ok == false then
    texture:SetTexture(M.FALLBACK)
    M.missing = true
    return M.FALLBACK
  end
  return path
end
