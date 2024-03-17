-- for debugging: DEFAULT_CHAT_FRAME:AddMessage("Test")
local function print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local unitIDs = {"player"} -- unitID player
for i=2,5 do unitIDs[i] = "party"..i-1 end -- unitIDs party
for i=6,45 do unitIDs[i] = "raid"..i-5 end -- unitIDs raid
local unitIDs_cache = {} -- init unitIDs_cache[name] = unitID
local eheal_prev = 0

local function GetUnitID(unitIDs_cache, unitIDs, name)
  if unitIDs_cache[name] and UnitName(unitIDs_cache[name]) == name then
      return unitIDs_cache[name]
  end
  for _,unitID in pairs(unitIDs) do
      if UnitName(unitID) == name then
        unitIDs_cache[name] = unitID
      return unitID
      end
  end
end

local function EHeal(unitIDs_cache, unitIDs, value, target)
  local unitID = GetUnitID(unitIDs_cache, unitIDs, target)
  local eheal = 0
  if unitID then
    eheal = math.min(UnitHealthMax(unitID) - UnitHealth(unitID), value)
  end
  return eheal
end

local parser = CreateFrame("Frame")
-- SPELL HEAL events
parser:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
parser:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
parser:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
parser:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")

local function MakeGfindReady(template) -- changes global string to fit gfind pattern
  template = gsub(template, "%%s", "(.+)") -- % is escape: %%s = %s raw
  return gsub(template, "%%d", "(%%d+)")
end

local combatlog_patterns = {} -- parser for combat log, order = {source, attack, target, value, school}, if not presenst = nil; parse order matters!!
-- ####### HEAL SOURCE:ME TARGET:ME
combatlog_patterns[1] = {string=MakeGfindReady(HEALEDCRITSELFSELF), order={nil, 1, nil, 2, nil}, kind="heal"} -- Your %s critically heals you for %d. (parse before Your %s heals you for %d.)
combatlog_patterns[2] = {string=MakeGfindReady(HEALEDSELFSELF), order={nil, 1, nil, 2, nil}, kind="heal"} -- Your %s heals you for %d.
combatlog_patterns[6] = {string=MakeGfindReady(PERIODICAURAHEALSELFSELF), order={nil, 2, nil, 1, nil}, kind="heal"} -- You gain %d health from %s.
-- ####### HEAL SOURCE:OTHER TARGET:ME
combatlog_patterns[4] = {string=MakeGfindReady(HEALEDCRITOTHERSELF), order={1, 2, nil, 3, nil}, kind="heal"} -- %s's %s critically heals you for %d. (parse before %s's %s critically heals %s for %d.)
combatlog_patterns[5] = {string=MakeGfindReady(HEALEDOTHERSELF), order={1, 2, nil, 3, nil}, kind="heal"} -- %s's %s heals you for %d.
combatlog_patterns[3] = {string=MakeGfindReady(PERIODICAURAHEALOTHERSELF), order={2, 3, nil, 1, nil}, kind="heal"} -- You gain %d health from %s's %s. (parse before You gain %d health from %s.)
-- ####### HEAL SOURCE:ME TARGET:OTHER
combatlog_patterns[7] = {string=MakeGfindReady(HEALEDCRITSELFOTHER), order={nil, 1, 2, 3, nil}, kind="heal"} -- Your %s critically heals %s for %d. (parse before Your %s heals %s for %d.)
combatlog_patterns[8] = {string=MakeGfindReady(HEALEDSELFOTHER), order={nil, 1, 2, 3, nil}, kind="heal"} -- Your %s heals %s for %d.
combatlog_patterns[9] = {string=MakeGfindReady(PERIODICAURAHEALSELFOTHER), order={nil, 3, 1, 2, nil}, kind="heal"} -- %s gains %d health from your %s.
-- ####### HEAL SOURCE:OTHER TARGET:OTHER
combatlog_patterns[10] = {string=MakeGfindReady(HEALEDCRITOTHEROTHER), order={1, 2, 3, 4, nil}, kind="heal"} -- %s's %s critically heals %s for %d.
combatlog_patterns[11] = {string=MakeGfindReady(HEALEDOTHEROTHER), order={1, 2, 3, 4, nil}, kind="heal"} -- %s's %s heals %s for %d.
combatlog_patterns[12] = {string=MakeGfindReady(PERIODICAURAHEALOTHEROTHER), order={3, 4, 1, 2, nil}, kind="heal"} -- %s gains %d health from %s's %s.

local HEALEDCRITSELFSELF_s = getglobal("HEALEDCRITSELFSELF")
local HEALEDSELFSELF_s = getglobal("HEALEDSELFSELF")
local PERIODICAURAHEALSELFSELF_s = getglobal("PERIODICAURAHEALSELFSELF")
local HEALEDCRITOTHERSELF_s = getglobal("HEALEDCRITOTHERSELF")
local HEALEDOTHERSELF_s = getglobal("HEALEDOTHERSELF")
local PERIODICAURAHEALOTHERSELF_s = getglobal("PERIODICAURAHEALOTHERSELF")
local HEALEDCRITSELFOTHER_s = getglobal("HEALEDCRITSELFOTHER")
local HEALEDSELFOTHER_s = getglobal("HEALEDSELFOTHER")
local PERIODICAURAHEALSELFOTHER_s = getglobal("PERIODICAURAHEALSELFOTHER")
local HEALEDCRITOTHEROTHER_s = getglobal("HEALEDCRITOTHEROTHER")
local HEALEDOTHEROTHER_s = getglobal("HEALEDOTHEROTHER")
local PERIODICAURAHEALOTHEROTHER_s = getglobal("PERIODICAURAHEALOTHEROTHER")
setglobal("HEALEDCRITSELFSELF", HEALEDCRITSELFSELF_s..eheal_prev) -- Hack: adds eheal info from previous heal to current heal (this means last heal done wont be counted, but whateves)
setglobal("HEALEDSELFSELF", HEALEDSELFSELF_s..eheal_prev)
setglobal("PERIODICAURAHEALSELFSELF", PERIODICAURAHEALSELFSELF_s..eheal_prev)
setglobal("HEALEDCRITOTHERSELF", HEALEDCRITOTHERSELF_s..eheal_prev)
setglobal("HEALEDOTHERSELF", HEALEDOTHERSELF_s..eheal_prev)
setglobal("PERIODICAURAHEALOTHERSELF", PERIODICAURAHEALOTHERSELF_s..eheal_prev)
setglobal("HEALEDCRITSELFOTHER", HEALEDCRITSELFOTHER_s..eheal_prev)
setglobal("HEALEDSELFOTHER", HEALEDSELFOTHER_s..eheal_prev)
setglobal("PERIODICAURAHEALSELFOTHER", PERIODICAURAHEALSELFOTHER_s..eheal_prev)
setglobal("HEALEDCRITOTHEROTHER", HEALEDCRITOTHEROTHER_s..eheal_prev)
setglobal("HEALEDOTHEROTHER", HEALEDOTHEROTHER_s..eheal_prev)
setglobal("PERIODICAURAHEALOTHEROTHER", PERIODICAURAHEALOTHEROTHER_s..eheal_prev)

parser:SetScript("OnEvent", function()
  if arg1 then
      local pars = {}
      for _,combatlog_pattern in ipairs(combatlog_patterns) do
          for par_1, par_2, par_3, par_4, par_5 in string.gfind(arg1, combatlog_pattern.string) do
              pars = {par_1, par_2, par_3, par_4, par_5}
              local target = pars[combatlog_pattern.order[3]]
              local value = pars[combatlog_pattern.order[4]]
              -- Default values
              if not target then
                  target = UnitName("player")
              end
              if not value then
                  value = 0
              end

              eheal_prev = EHeal(unitIDs_cache, unitIDs, value, target)

              setglobal("HEALEDCRITSELFSELF", HEALEDCRITSELFSELF_s..eheal_prev)
              setglobal("HEALEDSELFSELF", HEALEDSELFSELF_s..eheal_prev)
              setglobal("PERIODICAURAHEALSELFSELF", PERIODICAURAHEALSELFSELF_s..eheal_prev)
              setglobal("HEALEDCRITOTHERSELF", HEALEDCRITOTHERSELF_s..eheal_prev)
              setglobal("HEALEDOTHERSELF", HEALEDOTHERSELF_s..eheal_prev)
              setglobal("PERIODICAURAHEALOTHERSELF", PERIODICAURAHEALOTHERSELF_s..eheal_prev)
              setglobal("HEALEDCRITSELFOTHER", HEALEDCRITSELFOTHER_s..eheal_prev)
              setglobal("HEALEDSELFOTHER", HEALEDSELFOTHER_s..eheal_prev)
              setglobal("PERIODICAURAHEALSELFOTHER", PERIODICAURAHEALSELFOTHER_s..eheal_prev)
              setglobal("HEALEDCRITOTHEROTHER", HEALEDCRITOTHEROTHER_s..eheal_prev)
              setglobal("HEALEDOTHEROTHER", HEALEDOTHEROTHER_s..eheal_prev)
              setglobal("PERIODICAURAHEALOTHEROTHER", PERIODICAURAHEALOTHEROTHER_s..eheal_prev)
              return
          end
      end
  end
end)