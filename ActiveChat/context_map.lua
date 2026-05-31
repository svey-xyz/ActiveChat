--[[
  Context vocabulary & mappings for the context-aware chatter feature
  (CONTEXT_AWARE_PLAN.md "Files"). Plain Lua data tables, kept OUT of the engine
  so a content author can retune them without touching npcTalk.lua -- same
  philosophy as npc_name.lua / npc_text.lua.

  Loaded via `require("context_map")` in npcTalk.lua (the same module mechanism
  ALE uses for npc_text / npc_name). Returns a single table; new maps are added
  as named fields by later phases.

  Phase 3 ships only `eventIdToName`. Phases 4-5 will add:
    * monthToSeason   -- in-game month (1..12) -> "spring"|"summer"|"autumn"|"winter"
    * timeKeyDisplay  -- timeKey -> display-string pool (currently inline in npcTalk)
  See the placeholder block at the bottom.
]]--

local M = {}

-- ---------------------------------------------------------------------------
-- eventId -> display-name (Phase 3).
-- ---------------------------------------------------------------------------
-- Keyed to AzerothCore 3.3.5 `game_event.eventEntry` IDs (data/sql/base/
-- db_world/game_event.sql). GetActiveGameEvents() yields these IDs; we map them
-- to the holiday DISPLAY NAMES already used by the engine's `events` table so
-- %event% / ctx.active speak the same vocabulary the authored lines do (articles
-- baked in where the name needs one -- e.g. "the Midsummer Fire Festival").
--
-- Only the player-facing holidays/world-events that map onto an `events` entry
-- are listed; PvP "Call to Arms", AQ war-effort, arena seasons, Brew-of-the-Month
-- and other internal events are intentionally omitted (no display name, never an
-- ambient-chatter subject). Several holidays span MULTIPLE game_event rows (the
-- Darkmoon Faire has per-zone variants; Brewfest/Darkmoon have separate
-- "building" setup events) -- every such ID maps to the SAME display name so the
-- holiday resolves identically however the server schedules it.
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

-- ---------------------------------------------------------------------------
-- Neutral event phrases (Phase 4).
-- ---------------------------------------------------------------------------
-- When the game_event SCHEDULE can't be read (WorldDBQuery absent) and nothing is
-- active, %event% / %nextevent% / %lastevent% resolve to one of these GENERIC
-- phrases rather than naming a specific holiday -- so a character never claims a
-- wrong holiday is "soon" or "just past". Phrasing is festival-agnostic and reads
-- naturally in place of a holiday name (articles baked in to match the events
-- vocabulary, e.g. "Everyone's here for the next festival").
M.eventNeutral = {
    "the next festival", "the holidays", "the coming festivities",
    "the season's celebrations", "the festival days", "the next holiday",
}

-- ---------------------------------------------------------------------------
-- Event-activation burst chains (Phase 6) -- CONTEXT_AWARE_PLAN.md
-- "Event-sparked ambient bursts" / phased item 6.
-- ---------------------------------------------------------------------------
-- When an event flips from not-active to active AND enableEventBurst is on, the
-- engine fires ONE short character<->character exchange so players see the
-- festival "begin" as overheard chatter. These are two-line duo chains (speaker A
-- then speaker B); the %event% token resolves to the just-activated holiday's
-- display name (the burst is seeded with that event tagged, so token & tag agree).
-- Kept festival-agnostic so a single small pool covers every holiday -- the
-- %event% substitution supplies the specific name. The engine has an inline
-- fallback pool if this field is missing, so the burst still works standalone.
M.eventBurst = {
    { "Word is %event% has begun -- did you hear?", "Aye, just now. Best get to the city before the crowds." },
    { "They've lit the lanterns -- %event% is on at last!", "About time. I've been waiting all season for this." },
    { "%event% starts today, friend.", "Then what are we standing here for? Let's go." },
    { "The bells are ringing for %event%.", "So they are. The whole city will be out tonight." },
    { "Have you heard? %event% is finally here.", "Heard it? I can already smell the feast cooking." },
}

-- ---------------------------------------------------------------------------
-- month -> season (Phase 5) -- CONTEXT_AWARE_PLAN.md decision 4.
-- ---------------------------------------------------------------------------
-- In-game month (1..12, from os.date over GetGameTime()) -> season name. The
-- engine derives ctx.season from this map, then cross-checks against any active
-- seasonal holiday so the two never disagree (Winter Veil => winter, etc.).
--
-- Northern-hemisphere conventional default: Dec/Jan/Feb winter, Mar/Apr/May
-- spring, Jun/Jul/Aug summer, Sep/Oct/Nov autumn. OVERRIDABLE for themed realms
-- (e.g. a perpetual-winter Northrend server can map every month to "winter", or
-- a southern-hemisphere realm can flip the pairs) -- edit this table only, no
-- engine change. Values must be one of "winter"|"spring"|"summer"|"autumn".
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

-- ---------------------------------------------------------------------------
-- PLACEHOLDER -- later phases.
-- ---------------------------------------------------------------------------
-- A later phase may relocate here (kept inline in npcTalk.lua for now):
--   M.timeKeyDisplay = { night={...}, dawn={...}, ... }       -- timeKey -> display pool

return M
