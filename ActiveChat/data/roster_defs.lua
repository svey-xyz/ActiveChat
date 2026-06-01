--[[
  Roster identity vocabulary -- the tables that give generated characters their
  shape: locale affinities, civic/occupation archetypes, personality descriptors,
  per-faction home cities, and the name-colour palette.

  Pure data, split out of npcTalk.lua so tuning the roster's "cast of types" never
  touches engine logic. Loaded via require("roster_defs"); returns one table.
  Derived lookups (roleKeys/moodKeys) are computed in the engine from these.
]]--

local R = {}

-- The six locale affinities. Characters and tagged lines carry one; untagged = global.
R.AREAS = { "city", "rural", "battlefield", "coast", "wilderness", "road" }

-- Civic/occupation archetypes. prefixes -> "{Role} {first}" name prefixes;
-- weight -> roster frequency; area -> default affinity (must be one of AREAS).
R.ROLES = {
    guard      = { prefixes = {"Guardsman", "Sentinel", "Watchman"},      weight = 7, area = "city" },
    citizen    = { prefixes = {"Citizen", "Townsfolk", "Commoner"},       weight = 9, area = "city" },
    vendor     = { prefixes = {"Merchant", "Trader", "Peddler"},          weight = 7, area = "city" },
    innkeeper  = { prefixes = {"Innkeep", "Barkeep", "Host"},             weight = 6, area = "city" },
    adventurer = { prefixes = {"Adventurer", "Wanderer", "Seeker"},       weight = 6, area = "wilderness" },
    soldier    = { prefixes = {"Sergeant", "Private", "Trooper"},         weight = 5, area = "battlefield" },
    mage       = { prefixes = {"Magus", "Archmage", "Conjurer"},          weight = 4, area = "city" },
    priest     = { prefixes = {"Father", "Sister", "Brother"},            weight = 4, area = "city" },
    craftsman  = { prefixes = {"Smith", "Mason", "Tinker"},               weight = 5, area = "city" },
    farmer     = { prefixes = {"Farmer", "Goodman", "Goodwife"},          weight = 6, area = "rural" },
    sailor     = { prefixes = {"Sailor", "Deckhand", "Bosun"},            weight = 4, area = "coast" },
    noble      = { prefixes = {"Lord", "Lady", "Baron"},                  weight = 3, area = "city" },
    drunkard   = { prefixes = {"Old", "Sloshed", "Tipsy"},                weight = 4, area = "city" },
    urchin     = { prefixes = {"Little", "Ragged", "Street"},             weight = 4, area = "city" },
}

-- Personality descriptors -> epithet pool for the "{first}, {epithet}" name pattern;
-- also doubles as a line-selection mood tag.
R.PERSONALITIES = {
    warm     = { epithets = {"the Kind", "the Gentle", "the Warm"} },
    gruff    = { epithets = {"the Gruff", "the Surly", "the Blunt"} },
    cheerful = { epithets = {"the Merry", "the Jolly", "the Bright"} },
    weary    = { epithets = {"the Weary", "the Tired", "the Worn"} },
    wry      = { epithets = {"the Sly", "the Quick-Tongued", "the Wry"} },
    boastful = { epithets = {"the Great", "the Mighty", "the Boastful"} },
    nervous  = { epithets = {"the Jittery", "the Anxious", "the Skittish"} },
    solemn   = { epithets = {"the Solemn", "the Grave", "the Stoic"} },
    greedy   = { epithets = {"the Grasping", "the Miser", "the Greedy"} },
    kindly   = { epithets = {"the Kindly", "the Good", "the Tender"} },
    bitter   = { epithets = {"the Bitter", "the Sour", "the Jaded"} },
    dreamy   = { epithets = {"the Dreamer", "the Wistful", "the Distant"} },
    brave    = { epithets = {"the Brave", "the Bold", "the Fearless"} },
    cowardly = { epithets = {"the Timid", "the Craven", "the Faint-Hearted"} },
    gossipy  = { epithets = {"the Talkative", "the Nosy", "the Gossip"} },
}

-- Home-city pools by faction. Neutral hubs (Dalaran/Shattrath/Booty Bay) are travel
-- hubs, not home cities, so they're excluded here despite being in the %city% pool.
R.allianceCities = {"Stormwind", "Ironforge", "Darnassus", "The Exodar"}
R.hordeCities    = {"Orgrimmar", "Thunder Bluff", "Undercity", "Silvermoon City"}

-- Name-colour palette (class-ish colours). One is assigned per character at
-- generation and kept stable so a recurring voice keeps its identity.
R.colors = {"C79C6E","F58CBA","ABD473","FFF569","FFFFFF","C41F3B","0070DE","69CCF0","9482C9","FF7d0A"}

return R
