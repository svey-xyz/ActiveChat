--[[
    First Login Reward (Eluna / AzerothCore)
    ----------------------------------------
    The first time a player ever logs in on a given character, grant:
      - 5 gold
      - a Hearthstone (item 6948)
    and send them a personalized welcome message.

    "First time ever" is per-character persistent state, so it is tracked in
    the characters database (acore_characters) in a module-owned table keyed
    by the character low GUID. Once a row exists for that GUID, the reward is
    never granted again -- it survives logout, server restarts, etc.

    Conventions follow AzerothCore module practice:
      - custom_ table prefix so it can never collide with a core table
      - guid stored as INT UNSIGNED to mirror characters.guid (no casts)
      - no hard FOREIGN KEY to characters.guid (the core owns delete ordering)
]]

local GOLD_REWARD       = 5 * 10000   -- ModifyMoney is in copper (1 gold = 10000 copper)
local HEARTHSTONE_ITEM  = 6948
local HEARTHSTONE_COUNT = 1

-- Ensure the tracking table exists. Per-character data -> CharDB (acore_characters).
CharDBExecute([[
    CREATE TABLE IF NOT EXISTS `custom_first_login_reward` (
        `guid`        INT UNSIGNED NOT NULL COMMENT 'Player guidLow (characters.guid)',
        `rewarded_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`guid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]])

local function OnLogin(event, player)
    local guid = player:GetGUIDLow()

    -- Has this character ever been rewarded before? One sync read on login is fine.
    if CharDBQuery("SELECT 1 FROM custom_first_login_reward WHERE guid = " .. guid) then
        return
    end

    -- Mark as rewarded BEFORE granting, so a disconnect mid-grant can never
    -- double-reward on the next login. INSERT IGNORE keeps it idempotent.
    CharDBExecute("INSERT IGNORE INTO custom_first_login_reward (guid) VALUES (" .. guid .. ")")

    -- Grant the rewards.
    player:ModifyMoney(GOLD_REWARD)
    player:AddItem(HEARTHSTONE_ITEM, HEARTHSTONE_COUNT)

    -- Personalized welcome message addressed by character name.
    player:SendBroadcastMessage("Welcome, " .. player:GetName() ..
        "! As a first-time gift you have received 5 gold and a Hearthstone. Enjoy your adventures!")
end

-- 3 = PLAYER_EVENT_ON_LOGIN
RegisterPlayerEvent(3, OnLogin)
