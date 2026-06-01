--[[
  Context vocabulary & mappings for context-aware chatter. Plain data tables, kept
  out of the engine so content authors can retune them without touching logic/chatter.lua.
  Loaded via require("data.context"); returns one table of named maps.
]]--

local M = {}

-- eventId -> holiday display name. Keyed to AzerothCore 3.3.5 game_event.eventEntry
-- IDs; GetActiveGameEvents() yields these. Names match the engine's `events` table
-- (articles baked in) so %event%/ctx.active share the authored vocabulary. Only
-- player-facing holidays are listed (PvP/AQ/arena/internal events omitted). Multi-
-- row holidays (Darkmoon per-zone, Brewfest "building" events) all map to one name.
M.eventIdToName = {
    [1]  = "the Midsummer Fire Festival",   -- Midsummer Fire Festival
    [2]  = "Winter Veil",                   -- Feast of Winter Veil
    [3]  = "the Darkmoon Faire",            -- Darkmoon Faire (Terokkar Forest)
    [4]  = "the Darkmoon Faire",            -- Darkmoon Faire (Elwynn Forest)
    [5]  = "the Darkmoon Faire",            -- Darkmoon Faire (Mulgore)
    [7]  = "the Lunar Festival",            -- Lunar Festival
    [8]  = "Love is in the Air",            -- Love is in the Air
    [9]  = "Noblegarden",                   -- Noblegarden
    [10] = "Children's Week",               -- Children's Week
    [11] = "the Harvest Festival",          -- Harvest Festival
    [12] = "Hallow's End",                  -- Hallow's End
    [13] = "the Elemental Invasion",        -- Elemental Invasions
    [15] = "the Stranglethorn Fishing Extravaganza", -- STV Extravaganza (Fishing Pools)
    [17] = "the Scourge Invasion",          -- Scourge Invasion
    [23] = "the Darkmoon Faire",            -- Darkmoon Faire Building (Elwynn Forest)
    [24] = "Brewfest",                      -- Brewfest
    [26] = "Pilgrim's Bounty",              -- Pilgrim's Bounty
    [50] = "Pirates' Day",                  -- Pirates' Day
    [51] = "the Day of the Dead",           -- Day of the Dead
    [64] = "the Kalu'ak Fishing Derby",     -- Kalu'ak Fishing Derby (Fishing Pools)
    [70] = "Brewfest",                      -- Brewfest Building (Ironforge)
    [71] = "the Darkmoon Faire",            -- Darkmoon Faire Building (Mulgore)
    [77] = "the Darkmoon Faire",            -- Darkmoon Faire Building (Terokkar Forest)
    [91] = "Brewfest",                      -- Brewfest Building (Orgrimmar)
}

-- Neutral event phrases. Used when the schedule is unreadable and nothing is active,
-- so %event%/%nextevent%/%lastevent% never name a wrong holiday. Festival-agnostic,
-- articles baked in to match the events vocabulary.
M.eventNeutral = {
    "the next festival", "the holidays", "the coming festivities",
    "the season's celebrations", "the festival days", "the next holiday",
}

-- Event-activation burst chains. When an event flips active (and enableEventBurst is
-- on) the engine fires one short two-line duo so players see the festival "begin".
-- %event% resolves to the just-activated holiday, so these stay festival-agnostic --
-- one small pool covers every holiday. (Engine has an inline fallback if absent.)
M.eventBurst = {
    { "Word is %event% has begun -- did you hear?", "Aye, just now. Best get to the city before the crowds." },
    { "They've lit the lanterns -- %event% is on at last!", "About time. I've been waiting all season for this." },
    { "%event% starts today, friend.", "Then what are we standing here for? Let's go." },
    { "The bells are ringing for %event%.", "So they are. The whole city will be out tonight." },
    { "Have you heard? %event% is finally here.", "Heard it? I can already smell the feast cooking." },
}

-- month (1..12) -> season name. The engine derives ctx.season from this, then lets
-- an active seasonal holiday override it. Northern-hemisphere default; override per
-- table for themed realms (e.g. perpetual-winter Northrend). Values must be one of
-- "winter"|"spring"|"summer"|"autumn".
M.monthToSeason = {
    [1]  = "winter",  -- January
    [2]  = "winter",  -- February
    [3]  = "spring",  -- March
    [4]  = "spring",  -- April
    [5]  = "spring",  -- May
    [6]  = "summer",  -- June
    [7]  = "summer",  -- July
    [8]  = "summer",  -- August
    [9]  = "autumn",  -- September
    [10] = "autumn",  -- October
    [11] = "autumn",  -- November
    [12] = "winter",  -- December
}

-- Future: M.timeKeyDisplay (timeKey -> display pool) may move here from logic/chatter.lua.

return M
