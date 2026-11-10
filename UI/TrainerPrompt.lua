-- At a profession trainer: offers to learn what your routes need that the trainer can
-- teach you now (Engine/Training.lua), with the price and a Yes/No popup. Once per
-- trainer visit; "No" keeps quiet until the trainer is opened again. Options:
-- "Offer route recipes at trainers" (settings.trainerPrompt).
--
-- API (Gethe/wow-ui-source `forever`, Blizzard_TrainerUI/Mainline): TRAINER_SHOW /
-- TRAINER_CLOSED, IsTradeskillTrainer, GetNumTrainerServices, GetTrainerServiceInfo(i)
-- -> name, type ("available" | "unavailable" | "used"), texture, reqLevel, subText,
-- GetTrainerServiceStepIndex (the rank row, listed apart from the rest),
-- GetTrainerServiceCost(i), BuyTrainerService(i), GetMoney. The list follows the
-- trainer window's filters; "available" is the one that matters and is on by default.
local _, ns = ...
local TP = ns:NewModule("TrainerPrompt")
local U = ns.Util

TP.POPUP = "PROFS_TRAINER_LEARN"

function TP.Enabled()
  return not (ns.db and ns.db.settings and ns.db.settings.trainerPrompt == false)
end

-- What the open trainer lists: { {index, name, subText, type, cost}, ... }
function TP.Services()
  local out = {}
  if not (GetNumTrainerServices and GetTrainerServiceInfo) then return out end
  local n = GetNumTrainerServices() or 0
  local seen = {}
  local function add(i)
    if not i or seen[i] then return end
    seen[i] = true
    local name, kind, _, _, subText = GetTrainerServiceInfo(i)
    local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
    out[#out + 1] = { index = i, name = name, type = kind, subText = subText, cost = cost or 0 }
  end
  for i = 1, n do add(i) end
  if GetTrainerServiceStepIndex then add(GetTrainerServiceStepIndex()) end
  table.sort(out, function(a, b) return a.index < b.index end)
  return out
end

-- Popup text for what will be learned; nil when there is nothing to offer.
function TP.Text(picked, total, skipped)
  if #picked == 0 then return nil end
  local profs, seen = {}, {}
  for _, o in ipairs(picked) do
    local name = ns.Professions.Name(o.prof)
    if name and not seen[name] then seen[name] = true; profs[#profs + 1] = name end
  end
  local lines = { ("%s: learn what your %s route needs?"):format(ns.displayName,
    #profs > 0 and table.concat(profs, " / ") or "profession"), "" }
  for _, o in ipairs(picked) do
    lines[#lines + 1] = ("%s  %s"):format(o.rank and (o.rank .. " " .. (ns.Professions.Name(o.prof) or ""))
      or o.name, ns.Theme.Wrap("muted", U.money(o.cost)))
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Total: " .. U.money(total)
  if #skipped > 0 then
    local names = {}
    for _, o in ipairs(skipped) do names[#names + 1] = o.name end
    lines[#lines + 1] = ns.Theme.Wrap("warn", "Not enough money for: " .. table.concat(names, ", "))
  end
  return table.concat(lines, "\n")
end

-- Buy from the last index down: learning a service can drop it from the list (the
-- "used" filter), which only moves the rows after it.
function TP.Learn(picked)
  if not BuyTrainerService then return 0 end
  local order = {}
  for i, o in ipairs(picked or {}) do order[i] = o end
  table.sort(order, function(a, b) return a.index > b.index end)
  for _, o in ipairs(order) do BuyTrainerService(o.index) end
  ns.Log("info", ("learning %d from the trainer"):format(#order))
  return #order
end

function TP.Check()
  if TP.asked or not TP.Enabled() then return end
  if IsTradeskillTrainer and not IsTradeskillTrainer() then return end
  local wanted = ns.cdb and ns.cdb.trainList
  if not wanted or not next(wanted) then return end
  local offers = ns.Training.Match(TP.Services(), wanted)
  if #offers == 0 then return end
  local picked, total, skipped = ns.Training.Affordable(offers, GetMoney and GetMoney() or nil)
  local text = TP.Text(picked, total, skipped)
  if not text then return end
  TP.asked = true
  TP.pending = picked
  if StaticPopupDialogs and StaticPopup_Show then
    StaticPopupDialogs[TP.POPUP] = StaticPopupDialogs[TP.POPUP] or {
      text = "%s", button1 = YES or "Yes", button2 = NO or "No",
      timeout = 0, whileDead = true, hideOnEscape = true,
      OnAccept = function() TP.Learn(TP.pending); TP.pending = nil end,
      OnCancel = function() TP.pending = nil end,
    }
    StaticPopup_Show(TP.POPUP, text)
  end
end

function TP.OnClose()
  TP.asked, TP.pending = nil, nil
  if StaticPopup_Hide then StaticPopup_Hide(TP.POPUP) end
end

ns.Events.On("PROFS_LOADED", function()
  if not CreateFrame then return end
  local f = CreateFrame("Frame")
  f:RegisterEvent("TRAINER_SHOW")
  f:RegisterEvent("TRAINER_CLOSED")
  f:SetScript("OnEvent", function(_, e)
    if e == "TRAINER_SHOW" then TP.Check() else TP.OnClose() end
  end)
end)
