--[[
    Gossip Teleport NPC
    Creature entry: 800001

    Talking to the NPC opens a gossip menu with three options:
      1) Teleport to Stormwind
      2) Teleport to Orgrimmar
      3) Repair all gear

    The menu closes after an option is selected.
]]

local NPC_ENTRY = 800001

-- Gossip option intids
local OPTION_STORMWIND = 1
local OPTION_ORGRIMMAR = 2
local OPTION_REPAIR    = 3

-- Teleport destinations: { mapId, x, y, z, o }
local STORMWIND = { 0, -8833.38, 628.628, 94.0066, 1.06535 }
local ORGRIMMAR = { 1, 1633.33, -4439.11, 15.4346, 1.10044 }

-- GOSSIP_ICON_CHAT = 0
local ICON = 0

-- Fired when the player opens the NPC gossip window
local function OnGossipHello(event, player, creature)
    player:GossipClearMenu()

    player:GossipMenuAddItem(ICON, "Teleport me to Stormwind", 0, OPTION_STORMWIND)
    player:GossipMenuAddItem(ICON, "Teleport me to Orgrimmar", 0, OPTION_ORGRIMMAR)
    player:GossipMenuAddItem(ICON, "Repair all my gear", 0, OPTION_REPAIR)

    player:GossipSendMenu(1, creature)
end

-- Fired when the player selects a gossip option
local function OnGossipSelect(event, player, creature, sender, intid, code)
    if intid == OPTION_STORMWIND then
        player:Teleport(STORMWIND[1], STORMWIND[2], STORMWIND[3], STORMWIND[4], STORMWIND[5])
    elseif intid == OPTION_ORGRIMMAR then
        player:Teleport(ORGRIMMAR[1], ORGRIMMAR[2], ORGRIMMAR[3], ORGRIMMAR[4], ORGRIMMAR[5])
    elseif intid == OPTION_REPAIR then
        player:DurabilityRepairAll(false, 0, false)
    end

    -- Close the gossip menu after the choice is made
    player:GossipComplete()
end

-- Register hooks
-- 2 = GOSSIP_EVENT_ON_HELLO, 3 = GOSSIP_EVENT_ON_SELECT
RegisterCreatureGossipEvent(NPC_ENTRY, 2, OnGossipHello)
RegisterCreatureGossipEvent(NPC_ENTRY, 3, OnGossipSelect)
