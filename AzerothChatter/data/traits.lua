--[[
  Roster identity vocabulary -- the tables that give generated characters their
  shape: locale affinities, civic/occupation archetypes, personality descriptors,
  per-faction home cities, and the name-colour palette.

  Pure data, split out of logic/chatter.lua so tuning the roster's "cast of types" never
  touches engine logic. Loaded via require("data.traits"); returns one table.
  Derived lookups (roleKeys/moodKeys) are computed in the engine from these.
]]--

local R = {}

-- The six locale affinities. Characters and tagged lines carry one; untagged = global.
R.AREAS = { "city", "rural", "battlefield", "coast", "wilderness", "road" }

-- Civic/occupation archetypes. prefixes -> "{Role} {first}" name prefixes, keyed by
-- gender { male, female, neutral } so the title agrees with the character's gender
-- (buildName picks prefixes[gender] or prefixes.neutral). Genderless roles define
-- only `neutral`. weight -> roster frequency; area -> default affinity (must be one
-- of AREAS). A flat list (legacy shape) is still accepted and treated as neutral.
-- weight -> roster frequency. Tuned so common folk clearly dominate and nobles are
-- rare; every weight stays > 0 so no role is ever globally impossible.
R.ROLES = {
    guard      = { prefixes = { male = {"Guardsman", "Watchman"}, female = {"Guardswoman", "Watchwoman"}, neutral = {"Sentinel"} },           weight = 6, area = "city" },
    citizen    = { prefixes = { neutral = {"Citizen", "Townsfolk", "Commoner"} },                                                              weight = 10, area = "city" },
    vendor     = { prefixes = { neutral = {"Merchant", "Trader", "Peddler"} },                                                                 weight = 7, area = "city" },
    innkeeper  = { prefixes = { neutral = {"Innkeep", "Barkeep", "Host"} },                                                                    weight = 5, area = "city" },
    adventurer = { prefixes = { neutral = {"Adventurer", "Wanderer", "Seeker"} },                                                              weight = 5, area = "wilderness" },
    soldier    = { prefixes = { neutral = {"Sergeant", "Private", "Trooper"} },                                                                weight = 3, area = "battlefield" },
    mage       = { prefixes = { neutral = {"Magus", "Archmage", "Conjurer"} },                                                                 weight = 2, area = "city" },
    priest     = { prefixes = { male = {"Father", "Brother"}, female = {"Sister"}, neutral = {"Acolyte"} },                                    weight = 3, area = "city" },
    craftsman  = { prefixes = { neutral = {"Smith", "Mason", "Tinker"} },                                                                      weight = 6, area = "city" },
    farmer     = { prefixes = { male = {"Goodman"}, female = {"Goodwife"}, neutral = {"Farmer"} },                                             weight = 8, area = "rural" },
    sailor     = { prefixes = { neutral = {"Sailor", "Deckhand", "Bosun"} },                                                                   weight = 4, area = "coast" },
    noble      = { prefixes = { male = {"Lord", "Baron"}, female = {"Lady", "Baroness"}, neutral = {"Noble"} },                                weight = 1, area = "city" },
    drunkard   = { prefixes = { neutral = {"Old", "Sloshed", "Tipsy"} },                                                                       weight = 4, area = "city" },
    urchin     = { prefixes = { neutral = {"Little", "Ragged", "Street"} },                                                                    weight = 4, area = "city" },
}

-- Personality descriptors -> epithet pool for the "{first}, {epithet}" name pattern;
-- also doubles as a line-selection mood tag. weight -> draw frequency (parallel to
-- ROLES.weight): common/pleasant tempers high, rare/negative ones low. Every weight
-- stays > 0 so no temperament is ever globally impossible. The weight is only honored
-- when enableTraitCorrelation is on; off, personality is drawn uniformly (legacy).
R.PERSONALITIES = {
    warm     = { weight = 5, epithets = {"the Kind", "the Gentle", "the Warm"} },
    gruff    = { weight = 5, epithets = {"the Gruff", "the Surly", "the Blunt"} },
    cheerful = { weight = 5, epithets = {"the Merry", "the Jolly", "the Bright"} },
    weary    = { weight = 4, epithets = {"the Weary", "the Tired", "the Worn"} },
    wry      = { weight = 4, epithets = {"the Sly", "the Quick-Tongued", "the Wry"} },
    boastful = { weight = 3, epithets = {"the Great", "the Mighty", "the Boastful"} },
    nervous  = { weight = 3, epithets = {"the Jittery", "the Anxious", "the Skittish"} },
    solemn   = { weight = 3, epithets = {"the Solemn", "the Grave", "the Stoic"} },
    greedy   = { weight = 2, epithets = {"the Grasping", "the Miser", "the Greedy"} },
    kindly   = { weight = 6, epithets = {"the Kindly", "the Good", "the Tender"} },
    bitter   = { weight = 2, epithets = {"the Bitter", "the Sour", "the Jaded"} },
    dreamy   = { weight = 2, epithets = {"the Dreamer", "the Wistful", "the Distant"} },
    brave    = { weight = 3, epithets = {"the Brave", "the Bold", "the Fearless"} },
    cowardly = { weight = 1, epithets = {"the Timid", "the Craven", "the Faint-Hearted"} },
    gossipy  = { weight = 4, epithets = {"the Talkative", "the Nosy", "the Gossip"} },
}

-- Role -> mood bias: a role nudges temperament. Multipliers only (all > 0), so no
-- role makes a mood globally impossible -- the only intentional zeros are reserved for
-- the city affinity tables. Roles absent here contribute no tilt. Consumed as a
-- modifier in the mood weightedPick; softened by traitCorrelationStrength in the engine.
R.ROLES.craftsman.moodBias = { gruff = 2.0, dreamy = 0.5 }
R.ROLES.priest.moodBias    = { solemn = 1.8, kindly = 1.6, boastful = 0.5 }
R.ROLES.soldier.moodBias   = { brave = 1.8, gruff = 1.4, cowardly = 0.4 }
R.ROLES.noble.moodBias     = { boastful = 2.0, greedy = 1.8, warm = 0.6 }
R.ROLES.drunkard.moodBias  = { cheerful = 1.6, weary = 1.5 }
R.ROLES.urchin.moodBias    = { nervous = 1.6, wry = 1.4 }

-- Gender skews (light). Each gender maps to optional `roles`/`moods` modifier maps fed
-- into the role/mood pickers. Multipliers only; a gender with no entry yields no tilt.
R.GENDER_BIAS = {
    male    = { roles = { soldier = 1.4, guard = 1.2 } },
    female  = { roles = { priest  = 1.2 } },
    neutral = {},
}

-- Faction skews (subtle): Alliance leans civic/aristocratic, Horde martial. Multipliers
-- only. A faction/key absent here yields no tilt.
R.FACTION_BIAS = {
    alliance = { roles = { vendor  = 1.2, noble = 1.3 } },
    horde    = { roles = { soldier = 1.2, guard = 1.2 } },
}

-- Home-city affinity: a native's locale shapes their archetype. city -> { roles, moods }
-- modifier maps, stacked into the role/mood pickers alongside the gender/faction biases
-- and softened by traitCorrelationStrength. All eight home cities are authored (a
-- half-filled table would read as a bug). A city absent here contributes no tilt ({}).
-- Multipliers; the intentional zeros (e.g. no nobles in Thunder Bluff) are per-context
-- exclusions only -- every base weight stays > 0, so no trait is ever globally impossible.
R.CITY_BIAS = {
    -- Alliance
    ["Ironforge"]       = { roles = { craftsman = 3.0, soldier = 1.6, noble = 0.4 },
                            moods = { gruff = 2.5, boastful = 1.4, dreamy = 0.4 } },
    ["Darnassus"]       = { roles = { priest = 2.2, mage = 1.6, soldier = 0.5 },
                            moods = { dreamy = 2.0, solemn = 1.6, warm = 1.3, gruff = 0.5 } },
    ["Stormwind"]       = { roles = { guard = 1.5, vendor = 1.3, noble = 1.4 },
                            moods = { boastful = 1.3, brave = 1.3 } },
    ["The Exodar"]      = { roles = { priest = 1.8, mage = 1.5 },
                            moods = { solemn = 1.5, kindly = 1.4, weary = 1.3 } },
    -- Horde
    ["Orgrimmar"]       = { roles = { soldier = 1.8, guard = 1.5, noble = 0.4 },
                            moods = { gruff = 1.8, brave = 1.5, boastful = 1.4, dreamy = 0.4 } },
    ["Thunder Bluff"]   = { roles = { farmer = 2.0, priest = 1.6, adventurer = 1.4, noble = 0 },
                            moods = { solemn = 1.6, warm = 1.5, kindly = 1.4, greedy = 0.5 } },
    ["Undercity"]       = { roles = { mage = 1.6, craftsman = 1.4 },
                            moods = { bitter = 2.0, solemn = 1.5, wry = 1.4, cheerful = 0.4 } },
    ["Silvermoon City"] = { roles = { noble = 1.6, mage = 1.8 },
                            moods = { boastful = 1.6, greedy = 1.5, wry = 1.4, gruff = 0.5 } },
}

-- Home-city pools by faction. Neutral hubs (Dalaran/Shattrath/Booty Bay) are travel
-- hubs, not home cities, so they're excluded here despite being in the %city% pool.
R.allianceCities = {"Stormwind", "Ironforge", "Darnassus", "The Exodar"}
R.hordeCities    = {"Orgrimmar", "Thunder Bluff", "Undercity", "Silvermoon City"}

-- Name-colour palette (class-ish colours). One is assigned per character at
-- generation and kept stable so a recurring voice keeps its identity.
R.colors = {"C79C6E","F58CBA","ABD473","FFF569","FFFFFF","C41F3B","0070DE","69CCF0","9482C9","FF7d0A"}

return R
