-- for debugging: DEFAULT_CHAT_FRAME:AddMessage("Test")
local function print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local function DeleteTable(t)
  if t then
    for k in pairs (t) do
      t[k] = nil
    end
  end
end

local function GetUnitName(unit_ids_cache, unit_id)
  local unit_name = UnitName(unit_id)
  if unit_name then
    unit_ids_cache[unit_name] = unit_id
  end
  return unit_name
end


-- Get UnitIDs and Names of Raid/Party
local player_ids = {"player"} -- unitID player
for i=2,5 do player_ids[i] = "party"..i-1 end -- unitIDs party
for i=6,45 do player_ids[i] = "raid"..i-5 end -- unitIDs raid

local pet_ids = {"pet"}
for i=2,5 do pet_ids[i] = "partypet"..i-1 end -- unitIDs party
for i=6,45 do pet_ids[i] = "raidpet"..i-5 end -- unitIDs raid
local unit_ids_cache = {} -- init unitIDs_cache[name] = unitID

local function AddPlayersFromRaid()
  for idx, player_id in ipairs(player_ids) do
    local pet_id = pet_ids[idx]
    local player_name = GetUnitName(unit_ids_cache, player_id)
    local _, player_class = UnitClass(player_id)
    local pet_name = GetUnitName(unit_ids_cache, pet_id)
    if player_name and player_class then
      if not Kikilogs_data_players_table[player_name] then
        Kikilogs_data_players_table[player_name] = {}
        Kikilogs_data_players_table[player_name]["class"] = player_class -- class won't change
      end
      if pet_name then
        Kikilogs_data_players_table[player_name]["pet"] = pet_name -- pet might change
      end
    end
  end
end

local function GetUnitID(unit_name)
  if unit_ids_cache[unit_name] and UnitName(unit_ids_cache[unit_name]) == unit_name then
      return unit_ids_cache[unit_name]
  end
  for _,player_id in pairs(player_ids) do
      if UnitName(player_id) == unit_name then
        unit_ids_cache[unit_name] = player_id
        return player_id
      end
  end
  for _,pet_id in pairs(pet_ids) do
    if UnitName(pet_id) == unit_name then
      unit_ids_cache[unit_name] = pet_id
      return pet_id
    end
  end
end

-- calculate EOHeal
local function EOHeal(value, target)
  local unit_id = GetUnitID(target)
  local eheal = 0
  local oheal = 0
  if unit_id then
    eheal = math.min(UnitHealthMax(unit_id) - UnitHealth(unit_id), value)
    oheal = value-eheal
  end
  return eheal, oheal
end

-- Init Data
local addon_loader = CreateFrame("Frame")
addon_loader:RegisterEvent("ADDON_LOADED")
addon_loader:RegisterEvent("PLAYER_LOGOUT")
addon_loader:SetScript("OnEvent", function()
  if event=="ADDON_LOADED" then
    Kikilogs_data_heal = Kikilogs_data_heal or ""
    Kikilogs_data_players_table = Kikilogs_data_players_table or {}
  elseif event=="PLAYER_LOGOUT" then
    Kikilogs_data_players = ""
    for player_name, player_info in pairs(Kikilogs_data_players_table) do
      local class = player_info["class"] or ""
      local pet = player_info["pet"] or ""
      Kikilogs_data_players = Kikilogs_data_players..player_name.."#"..class.."#"..pet.."$"
    end
  end
end)


local active = false

local party_members_changed = CreateFrame("Frame") -- should fire when players are moved around in raids as well
party_members_changed:RegisterEvent("PARTY_MEMBERS_CHANGED")
party_members_changed:RegisterEvent("UNIT_PET")
party_members_changed:SetScript("OnEvent", function()
  AddPlayersFromRaid()
end)


local event_parser = CreateFrame("Frame")
-- SPELL HEAL events
event_parser:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
event_parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
event_parser:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
event_parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
event_parser:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
event_parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
event_parser:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
event_parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")

local function MakeGfindReady(template) -- changes global string to fit gfind pattern
  template = gsub(template, "%%s", "(.+)") -- % is escape: %%s = %s raw
  return gsub(template, "%%d", "(%%d+)")
end

local combatlog_patterns = {} -- event_parser for combat log, order = {source, attack, target, value, school}, if not presenst = nil; parse order matters!!
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

event_parser:SetScript("OnEvent", function()
  if active and arg1 then
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

              local eheal, oheal = EOHeal(value, target)
              if eheal and oheal then
                Kikilogs_data_heal = Kikilogs_data_heal..GetTime().."#"..arg1.."#"..eheal.."#"..oheal.."$"
              end
              return
          end
      end
  end
end)


SLASH_KIKILOGS1 = "/kikilogs"
SlashCmdList["KIKILOGS"] = function(msg)
  if (msg == "" or msg == nil) then
    if active then
      active = false
      print("Kikilogs deactivated (reset with /kikilogs reset)")
    else
      active = true
      print("Kikilogs activated (reset with /kikilogs reset)")
      AddPlayersFromRaid()
    end
  elseif msg=="reset" then
    Kikilogs_data_heal = ""
    Kikilogs_data_players = ""
    DeleteTable(Kikilogs_data_players_table)
    print("Kikilogs has been reset")
  end
end