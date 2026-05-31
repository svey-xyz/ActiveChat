--[[
    .heal chat command (Eluna / AzerothCore)

    Typing ".heal" in chat fully heals the player who typed it and their
    current target, but ONLY if the player is a Game Master.
    Non-GMs get no special behaviour (the command is ignored).
]]

local COMMAND = "heal"

-- Fully restore a unit's health, mana, and other power types.
local function FullRestore(unit)
    if not unit or not unit:IsAlive() then
        return
    end

    -- Health
    unit:SetHealth(unit:GetMaxHealth())

    -- Mana (power type 0)
    local maxMana = unit:GetMaxPower(0)
    if maxMana > 0 then
        unit:SetPower(maxMana, 0)
    end
end

local function OnCommand(event, player, command)
    -- Only react to ".heal" (Eluna strips the leading dot before passing it in).
    if command:lower() ~= COMMAND then
        return -- let other handlers / default processing run
    end

    -- GM check. GetGMRank() > 0 means the account has a GM level.
    if not player:IsGM() then
        return -- not a GM: do nothing special, allow normal handling
    end

    -- Heal the caster.
    FullRestore(player)

    -- Heal the current target, if any.
    local target = player:GetSelection()
    if target then
        FullRestore(target)
        player:SendBroadcastMessage("You fully healed yourself and " .. target:GetName() .. ".")
    else
        player:SendBroadcastMessage("You fully healed yourself.")
    end

    return false -- command handled; stop further processing
end

RegisterPlayerEvent(42, OnCommand) -- 42 = PLAYER_EVENT_ON_COMMAND
