--[[
    first_login_reward.lua

    The first time a character ever logs in, give the player:
      * 5 gold
      * 1 Hearthstone (item entry 6948)
    and send them a personalized welcome message.

    Uses PLAYER_EVENT_ON_FIRST_LOGIN (event id 30), which fires exactly once
    per character on its very first login -- so no manual "have we rewarded
    them yet?" tracking is required.

    Drop this file in the server's lua_scripts/ directory and run
    `.reload ale` (or restart the worldserver).
]]

local GOLD_REWARD     = 5          -- gold pieces
local COPPER_PER_GOLD = 10000      -- 1 gold = 10000 copper
local HEARTHSTONE     = 6948       -- item entry
local HEARTHSTONE_QTY = 1

local function OnFirstLogin(event, player)
    if not player then
        return
    end

    -- 5 gold (ModifyMoney takes copper)
    player:ModifyMoney(GOLD_REWARD * COPPER_PER_GOLD)

    -- A Hearthstone
    player:AddItem(HEARTHSTONE, HEARTHSTONE_QTY)

    -- Personalized welcome, addressed by character name
    local name = player:GetName()
    player:SendBroadcastMessage("Welcome to the server, " .. name ..
        "! Here are 5 gold and a Hearthstone to get you started. Enjoy your adventure!")
end

-- 30 = PLAYER_EVENT_ON_FIRST_LOGIN
RegisterPlayerEvent(30, OnFirstLogin)
