--[[
    .heal  -  GM-only full heal command (AzerothCore / ALE-Eluna)

    A GM types ".heal" to fully restore their own health and power, and the
    same for their current target (if they have one).

    Hook: PLAYER_EVENT_ON_COMMAND (event id 42). The `command` arg is the
    typed command WITHOUT its leading dot, and includes any arguments.
]]

local PLAYER_EVENT_ON_COMMAND = 42

-- Fully restore a unit's health and its active power (mana/rage/energy/etc.).
local function FullyRestore(unit)
    if not unit then
        return
    end

    unit:SetHealth(unit:GetMaxHealth())

    local powerType = unit:GetPowerType()
    if powerType then
        unit:SetPower(unit:GetMaxPower(powerType), powerType)
    end
end

local function OnCommand(event, player, command)
    -- `player` is nil when a command is run from the server console.
    if not player then
        return
    end

    -- Only react to exactly ".heal" (ignore other commands / trailing args).
    if command ~= "heal" then
        return  -- pass through: let the core handle anything that isn't ours
    end

    -- GM gate. If they're not a GM, do nothing special and let the core
    -- process the command normally (it'll report "unknown command").
    if not player:IsGM() then
        return
    end

    -- Heal the GM.
    FullyRestore(player)

    -- Heal their current target, if any.
    local target = player:GetSelection()
    if target then
        FullyRestore(target)
        player:SendBroadcastMessage("|cff00ff00[.heal]|r You and your target have been fully healed.")
    else
        player:SendBroadcastMessage("|cff00ff00[.heal]|r You have been fully healed.")
    end

    -- We handled it; stop the core from reporting "unknown command".
    return false
end

RegisterPlayerEvent(PLAYER_EVENT_ON_COMMAND, OnCommand)
