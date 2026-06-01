--[[
  AzerothChatter -- module entry point and the single source of truth for every
  tunable knob. This is the primary file: it carries all config at the top and is
  required by the engine (logic/chatter.lua) and logic/context.lua as require("AzerothChatter"),
  each pulling the values it needs into locals. Edit values HERE, not in the engine.
  Returns one flat config table.

  NOTE: a nil-valued key (maxCharactersPerFaction) is simply absent from the table;
  reading it still yields nil, which is the intended "unset" sentinel.
]]--

return {
    -- Master switches.
    enableScript      = true,   -- master on/off for the whole script
    enableFactionChat = true,   -- true = gate alliance/horde lines by faction
                                -- false = legacy: broadcast everything to everyone

    -- Spam intervals (ms). 1 second = 1000.
    talk_time         = {8000, 120000},   -- shared WORLD chat
    faction_talk_time = {20000, 180000},   -- faction WORLD chat (per faction)

    -- Roster / selection-engine. The roster starts empty and grows lazily on demand
    -- up to maxCharacters, then self-balances (reuses existing voices) at the cap.
    maxCharacters           = 64,   -- cap on the lazily-grown roster
    maxCharactersPerFaction = nil,   -- optional per-faction sub-cap (nil = share maxCharacters)
    newCharacterWeight      = 4,     -- virtual "spawn a new character" weight vs existing chattiness
    lineCooldownTicks       = 8,     -- default per-line repeat cooldown (ticks), in the line scorer
    homeCityBias            = true,  -- bias %city% toward the speaker's home city
    roleMoodMatchStrength   = 3.0,   -- how hard role/mood matching is weighted (1 = off)
    areaMatchStrength       = 3.0,   -- how hard area matching is weighted (1 = off)

    -- Per-character gender. Rolled once at generation; drives the gender-agreeing
    -- first-name sub-pool (data/names.lua) and role prefix (data/traits.lua), and
    -- backs the pronoun tokens. Weights are relative (need not sum to 100). "neutral"
    -- covers genderless flavour (gnome/utility + surname-style names) and is the
    -- fallback when a gender bucket is empty -- a low share keeps those names rare;
    -- raise it to surface more of the neutral pool.
    genderRatio             = { male = 45, female = 45, neutral = 10 },

    -- Trait correlation layer. Base role/personality weights (data/traits.lua) are
    -- ALWAYS honored. This flag governs only the correlation layer: with it OFF,
    -- personality reverts to a uniform draw (legacy behavior) and conditional
    -- modifiers (role/gender/faction/city skews) are skipped; ON, personality uses
    -- its authored weight and modifiers apply. strength scales each modifier toward
    -- 1.0 (eff = 1 + (factor-1)*s): 0 = base weights only, 1 = as authored.
    enableTraitCorrelation  = true,
    traitCorrelationStrength = 1.0,

    -- Context-aware chatter. When a flag is off (or its API is missing) that
    -- dimension falls back to random behaviour -- no silent characters, no errors.
    enableContextAware   = true,    -- master switch for the whole context feature
    enableTimeContext    = true,    -- clock-aware times + %timeofday%
    enableEventContext   = true,    -- active-event gating + %event%
    enableSeasonContext  = true,    -- month-derived season + %season%
    timeMatchStrength    = 3.0,     -- like areaMatchStrength; 1 = off
    seasonMatchStrength  = 3.0,     -- like areaMatchStrength; 1 = off
    contextRefreshMs     = 60000,   -- ctx cache TTL (ms)
    eventApproachDays    = 5,       -- "approach" window before an event starts
    eventAfterDays       = 3,       -- "after" window once an event ends
    enableEventBurst     = false,   -- one-shot "festival has begun" burst on activation

    -- Optional WorldDBQuery string to source NPC names from the DB. Blank => names
    -- come from data/names.lua.
    ns = "",
}
