--[[
    Gossip Teleport & Repair NPC
    creature_template entry: 800001

    Talking to this NPC opens a gossip menu with three options:
      1. Teleport to Stormwind
      2. Teleport to Orgrimmar
      3. Repair all gear
    The menu closes after an option is selected.
]]

local NPC_ENTRY = 800001

-- Gossip option intids
local OPT_STORMWIND = 1
local OPT_ORGRIMMAR = 2
local OPT_REPAIR    = 3

-- Teleport coordinates: { mapId, x, y, z, o }
local STORMWIND = { 0, -8833.379, 628.628, 94.006, 1.065 }
local ORGRIMMAR = { 1, 1572.738, -4441.658, 9.999, 0.000 }

-- GOSSIP_ICON_CHAT = 0
local ICON_CHAT = 0

local function OnGossipHello(event, player, creature)
    player:GossipClearMenu()
    player:GossipMenuAddItem(ICON_CHAT, "Teleport me to Stormwind", 0, OPT_STORMWIND)
    player:GossipMenuAddItem(ICON_CHAT, "Teleport me to Orgrimmar", 0, OPT_ORGRIMMAR)
    player:GossipMenuAddItem(ICON_CHAT, "Repair all my gear",       0, OPT_REPAIR)
    player:GossipSendMenu(1, creature)
end

local function OnGossipSelect(event, player, creature, sender, intid, code)
    if intid == OPT_STORMWIND then
        player:Teleport(STORMWIND[1], STORMWIND[2], STORMWIND[3], STORMWIND[4], STORMWIND[5])
    elseif intid == OPT_ORGRIMMAR then
        player:Teleport(ORGRIMMAR[1], ORGRIMMAR[2], ORGRIMMAR[3], ORGRIMMAR[4], ORGRIMMAR[5])
    elseif intid == OPT_REPAIR then
        -- DurabilityRepairAll(takeCost, discountMod, guidBank)
        -- takeCost=false -> free repair, no copper charged.
        player:DurabilityRepairAll(false, 1.0, false)
        player:SendBroadcastMessage("Your gear has been fully repaired.")
    end

    -- Close the gossip menu after a selection is made.
    player:GossipComplete()
end

RegisterCreatureGossipEvent(NPC_ENTRY, 1, OnGossipHello)   -- GOSSIP_EVENT_ON_HELLO
RegisterCreatureGossipEvent(NPC_ENTRY, 2, OnGossipSelect)  -- GOSSIP_EVENT_ON_SELECT
