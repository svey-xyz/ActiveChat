--[[
  Lively World Chat -- faction-gated edition.

  Content lives in data/chatter.lua, returning three pools:
      shared   -> everyone (SendWorldMessage)   alliance -> team 0   horde -> team 1
  enableFactionChat = false merges all three and broadcasts to everyone (legacy).

  Voice: civilian/guard/NPC ambience -- gossip, weather, work, rumor, lore. Never
  LFG/LFM or gearscore talk. %role%/%difficulty%/%gearscore% are for the rare
  adventurer voice only; prefer world/flavor tokens. See data/chatter.lua header.
]]--

-- All tunable knobs live in AzerothChatter.lua (single source of truth).
local config = require("AzerothChatter")
local enableScript      = config.enableScript
local enableFactionChat = config.enableFactionChat

if enableScript then

-- Config this engine file uses. logic/context.lua reads the rest straight from AzerothChatter.lua.
local talk_time               = config.talk_time
local faction_talk_time       = config.faction_talk_time
local enableBurstConversations = config.enableBurstConversations
local convLineGap             = config.convLineGap or {1500, 4000}
local convMaxLines            = config.convMaxLines
local maxCharacters           = config.maxCharacters
local maxCharactersPerFaction = config.maxCharactersPerFaction
local newCharacterWeight      = config.newCharacterWeight
local lineCooldownTicks       = config.lineCooldownTicks
local homeCityBias            = config.homeCityBias
local roleMoodMatchStrength   = config.roleMoodMatchStrength
local areaMatchStrength       = config.areaMatchStrength
local genderRatio             = config.genderRatio or { male = 45, female = 45, neutral = 10 }
local enableTraitCorrelation  = config.enableTraitCorrelation
local traitCorrelationStrength = config.traitCorrelationStrength or 1.0
-- Context flags also read by the line scorer (timeFactor/seasonFactor/eventFactor):
local enableContextAware      = config.enableContextAware
local enableTimeContext       = config.enableTimeContext
local enableEventContext      = config.enableEventContext
local enableSeasonContext     = config.enableSeasonContext
local timeMatchStrength       = config.timeMatchStrength
local seasonMatchStrength     = config.seasonMatchStrength
local eventApproachDays       = config.eventApproachDays
local eventAfterDays          = config.eventAfterDays
local enableEventBurst        = config.enableEventBurst
local enablePlayerCommands    = config.enablePlayerCommands
local playerCreateGmOnly      = config.playerCreateGmOnly
local playerCreateLimit       = config.playerCreateLimit or 5
local ns                      = config.ns

local t = {}

-- Modules (data + subsystems). mod-ale adds the module dir AND its subdirectories to
-- package.path, so dotted names resolve from the AzerothChatter/ root. Paths are
-- qualified (data.* / logic.*) because basenames collide: data/chatter.lua vs
-- logic/chatter.lua, and data/context.lua vs logic/context.lua.
local pools      = require("data.tokens")   -- data/tokens.lua: %token% vocabulary + accessors
local rosterDefs = require("data.traits")   -- data/traits.lua: roster identity tables
local context    = require("logic.context") -- logic/context.lua: time/event/season cache + resolvers

-- data/context.lua (context vocabulary/maps) is consulted directly only for the
-- (optional, default-off) event-burst pool fallback below; the rest of its use lives
-- inside logic/context.lua.
local ctxMap = {}
do
    local ok, m = pcall(require, "data.context")
    if (ok and type(m) == "table") then ctxMap = m end
end

-- Context handles. ctx is mutated in place by refreshCtx, so this captured reference
-- stays live; the resolvers are the %token% backends for the renderer.
local ctx              = context.ctx
local refreshCtx       = context.refreshCtx
local resolveEvent     = context.resolveEvent
local resolveNextEvent = context.resolveNextEvent
local resolveLastEvent = context.resolveLastEvent
local resolveSeason    = context.resolveSeason
local resolveTimeOfDay = context.resolveTimeOfDay

-- Roster identity tables (see data/traits.lua); roleKeys/moodKeys derived below.
local AREAS          = rosterDefs.AREAS
local ROLES          = rosterDefs.ROLES
local PERSONALITIES  = rosterDefs.PERSONALITIES
local allianceCities = rosterDefs.allianceCities
local hordeCities    = rosterDefs.hordeCities
local GENDER_BIAS    = rosterDefs.GENDER_BIAS  or {}
local FACTION_BIAS   = rosterDefs.FACTION_BIAS or {}
local CITY_BIAS      = rosterDefs.CITY_BIAS    or {}
t.cc = rosterDefs.colors                     -- per-character name-colour palette

-- FORWARD-COMPAT no-op: the emit path calls this so wiring a real chat-topic buffer
-- later is a one-function change.
local function recordTopic(line) end


-- Load content pools --------------------------------------------------------
local world = require("data.chatter")    -- { shared/alliance/horde = {lines,duos,groups} }

-- Tagged-content parser. buildItems flattens typed pools ({lines, duos, groups})
-- into one cursored item list, each tagged with its `kind`: "line" (single
-- speaker), "duo" (2 alternating), "group" (rotating cast).
--
-- Authored entries (back-compatible):
--   * bare string            -> untagged line (global wildcard)
--   * table {[1]=text, ...}   -> tagged one-liner; named keys are metadata
--   * table {chain={...}, ...} -> tagged duo/group
--   * legacy {"a","b",...}    -> untagged chain (from the duos/groups list, [1] a string)
--
-- Normalized item shape: { kind, data (string for line / array for chain), roles,
-- moods (nil = any), areaGlobal+areas, timesGlobal+times, seasonsGlobal+seasons,
-- eventsGlobal+events+eventWindow, notTimes/notSeasons/notEvents, weight, cooldown }.
-- The *Global flags mean "untagged = matches any"; a tagged dimension hard-excludes
-- off-tag context at score time. All normalization happens at parse time below.

-- Normalize a positively-weighted tag field (areas/times/seasons) into {global, map}.
-- omitted => global (matches any); list form {"city","rural"} => each key weight 1;
-- map form {battlefield=3, rural=1} => graded weights as-is. Unlisted keys are
-- hard-excluded at score time (areaFactor/timeFactor/seasonFactor).
local function normalizeWeightedSet(field)
    if (field == nil) then
        return true, {}                         -- omitted => global / any
    end
    local map = {}
    if (field[1] ~= nil) then
        for _, k in ipairs(field) do map[k] = 1 end          -- list form
    else
        for k, w in pairs(field) do map[k] = w end           -- map (graded) form
    end
    return false, map
end

-- Normalize `events` into {eventsGlobal, events-list}. events is BINARY (no graded
-- boost): omitted => fires regardless; a list of display-names => fires ONLY while
-- one is active, else hard-excluded. Map form accepted (keys = names, weights
-- ignored). Returns names as a plain array (also used to resolve %event%).
local function normalizeEvents(events)
    if (events == nil) then
        return true, {}                         -- omitted => global / any/no event
    end
    local list = {}
    if (events[1] ~= nil) then
        -- list form: {"Hallow's End", "the Day of the Dead"} -> names as-is.
        for _, name in ipairs(events) do list[#list + 1] = name end
    else
        -- map form: {["Hallow's End"]=anything} -> keys are the names (weights
        -- ignored; events is binary).
        for name, _ in pairs(events) do list[#list + 1] = name end
    end
    return false, list
end

-- Normalize `eventWindow`: "active" (default, live only), "approach" (also the
-- N-day run-up, keys off ctx.nextEvent), "after" (also the N-day wind-down,
-- ctx.lastEvent). Unrecognised -> "active" so a typo never widens eligibility.
local function normalizeEventWindow(w)
    if (w == "approach") or (w == "after") then return w end
    return "active"
end

-- Normalize an exclusion field (notTimes/notSeasons/notEvents) into a set { key=true }.
-- The NEGATIVE gate: "fires in ANY context EXCEPT these" (mirror of the positive
-- tags). List or map form accepted (binary, no weights); omitted => no exclusions.
-- Applies even to global lines, so a universal line can carve out one context.
local function normalizeExcludeSet(field)
    local set = {}
    if (field == nil) then return set end       -- omitted => no exclusions
    if (field[1] ~= nil) then
        for _, k in ipairs(field) do set[k] = true end   -- list form
    else
        for k, _ in pairs(field) do set[k] = true end    -- map/set form
    end
    return set
end

-- Wrap one authored entry into the normalized item shape. `forceChain` (true for
-- duos/groups) reads a legacy bare {"a","b"} array as the chain, not a one-liner.
local function makeItem(kind, entry, forceChain)
    -- Bare string -> untagged item.
    if (type(entry) == "string") then
        return {
            kind = kind, data = entry,
            roles = nil, moods = nil, genders = nil,
            areaGlobal = true, areas = {},
            timesGlobal = true, times = {},
            seasonsGlobal = true, seasons = {},
            eventsGlobal = true, events = {}, eventWindow = "active",
            notTimes = {}, notSeasons = {}, notEvents = {},
            weight = 1, cooldown = lineCooldownTicks,
        }
    end

    -- Table entry. Decide whether it carries an explicit chain, an implicit
    -- legacy chain, or is a tagged one-liner.
    local data
    if (entry.chain ~= nil) then
        data = entry.chain                       -- explicit tagged chain
    elseif (forceChain) and (type(entry[1]) == "string") then
        data = entry                             -- legacy untagged {"a","b",...}
    else
        data = entry[1]                          -- tagged one-liner: [1] is text
    end

    local areaGlobal, areaMap       = normalizeWeightedSet(entry.areas)
    local timesGlobal, timesMap     = normalizeWeightedSet(entry.times)
    local seasonsGlobal, seasonsMap = normalizeWeightedSet(entry.seasons)
    local eventsGlobal, eventsList = normalizeEvents(entry.events)
    return {
        kind = kind, data = data,
        roles = entry.roles, moods = entry.moods, genders = entry.genders,
        areaGlobal = areaGlobal, areas = areaMap,
        timesGlobal = timesGlobal, times = timesMap,
        seasonsGlobal = seasonsGlobal, seasons = seasonsMap,
        eventsGlobal = eventsGlobal, events = eventsList,
        eventWindow = normalizeEventWindow(entry.eventWindow),
        notTimes   = normalizeExcludeSet(entry.notTimes),
        notSeasons = normalizeExcludeSet(entry.notSeasons),
        notEvents  = normalizeExcludeSet(entry.notEvents),
        weight = entry.weight or 1,
        cooldown = entry.cooldown or lineCooldownTicks,
    }
end

local function buildItems(...)
    local items = {}
    for _, pool in ipairs({...}) do
        if pool then
            for _, s  in ipairs(pool.lines  or {}) do items[#items + 1] = makeItem("line",  s,  false) end
            for _, c  in ipairs(pool.duos   or {}) do items[#items + 1] = makeItem("duo",   c,  true)  end
            for _, gp in ipairs(pool.groups or {}) do items[#items + 1] = makeItem("group", gp, true)  end
        end
    end
    return items
end

-- Per-faction CANDIDATE item lists, keyed by SPEAKER faction: Alliance speaker ->
-- shared + alliance; Horde speaker -> horde. Each item carries an `audience` origin
-- tag (shared|alliance|horde) that decides routing at emit time, so one Alliance
-- speaker can voice either an everyone-visible or an Alliance-only line from the
-- same set. Legacy (enableFactionChat=false): all merged, all audience="shared".
-- taggedItems flattens buildItems' list into a plain array and stamps each item's
-- audience (per-cast conversation state lives in t.conv, not on the items).
local function taggedItems(pool, audience)
    local out = {}
    local built = buildItems(pool)
    for i = 1, #built do
        local it = built[i]
        it.audience = audience
        out[#out + 1] = it
    end
    return out
end

local function mergeCandidates(...)
    local out = {}
    for _, list in ipairs({...}) do
        for _, it in ipairs(list) do out[#out + 1] = it end
    end
    return out
end

local allianceCandidates, hordeCandidates
if enableFactionChat then
    -- Alliance voices shared (everyone) + alliance (Alliance-only) lines.
    allianceCandidates = mergeCandidates(
        taggedItems(world.shared,   "shared"),
        taggedItems(world.alliance, "alliance"))
    -- Horde voices horde (Horde-only) lines only.
    hordeCandidates = taggedItems(world.horde, "horde")
else
    -- Legacy: everything merged, broadcast to everyone (audience="shared").
    -- Both factions draw from the same everyone-visible pool.
    allianceCandidates = mergeCandidates(
        taggedItems(world.shared,   "shared"),
        taggedItems(world.alliance, "shared"),
        taggedItems(world.horde,    "shared"))
    hordeCandidates = allianceCandidates
end

-- Roster identity tables (AREAS / ROLES / PERSONALITIES) live in data/traits.lua,
-- required and aliased at the top of this file.

-- Roster state -- in-memory ONLY, never persisted, reset every restart (regrows
-- lazily as chatter is emitted). roster = all characters; rosterByFaction = the
-- same bucketed by faction; usedNames = dedup guard. generateCharacter fills them.
local roster          = {}
local rosterByFaction = { alliance = {}, horde = {} }
local usedNames       = {}

-- (allianceCities / hordeCities come from data/traits.lua, aliased at top.)

-- Pre-compute role/personality key lists once so
-- generation can index them uniformly. ROLES is weighted; PERSONALITIES is
-- picked uniformly.
local roleKeys = {}
for k in pairs(ROLES)         do roleKeys[#roleKeys + 1] = k end
local moodKeys = {}
for k in pairs(PERSONALITIES) do moodKeys[#moodKeys + 1] = k end

-- generateName -> display string via four weighted patterns: {first last} ~55%,
-- {Role first} ~20%, {first, epithet} ~15%, {first} ~10%. First names from
-- t.d[faction] (gender-matched sub-pool), surnames from t.d.surnames. Deduped vs
-- usedNames (12-try cap).
local function pickFrom(list)
    return list[math.random(#list)]
end

-- First-name pool for a faction+gender. New shape is a gender map
-- {male,female,neutral}; fall back to neutral, then any populated bucket, then the
-- surname pool. A legacy flat list (no gender keys) is treated as neutral -- mirrors
-- the flat-list-as-surnames fallback in t.init, so old name files still load.
local function firstNamePool(faction, gender)
    local f = t.d[faction]
    if (type(f) ~= "table") then return t.d.surnames end
    if (f[1] ~= nil) then return f end                        -- legacy flat list
    local pool = f[gender] or f.neutral
    if (pool) and (#pool > 0) then return pool end
    for _, sub in pairs(f) do                                 -- any populated bucket
        if (type(sub) == "table") and (#sub > 0) then return sub end
    end
    return t.d.surnames
end

-- Role title prefix agreeing with the character's gender. New shape is a gender map;
-- fall back to neutral, then any populated bucket. A legacy flat list is genderless.
-- Returns nil when the role has no usable prefix (caller then uses {first last}).
local function rolePrefix(role, gender)
    local p = ROLES[role] and ROLES[role].prefixes
    if (type(p) ~= "table") then return nil end
    if (p[1] ~= nil) then return (#p > 0) and pickFrom(p) or nil end   -- legacy flat list
    local bucket = p[gender] or p.neutral
    if (not bucket) or (#bucket == 0) then
        for _, b in pairs(p) do
            if (type(b) == "table") and (#b > 0) then bucket = b; break end
        end
    end
    if (bucket) and (#bucket > 0) then return pickFrom(bucket) end
    return nil
end

-- buildName -> displayName, nameParts. nameParts keeps the chosen components
-- (prefix/first/surname/epithet) so address (%target%) and pronoun features can reuse
-- them instead of re-parsing the finished string. `first` is always set.
local function buildName(faction, role, personality, gender)
    local firsts = firstNamePool(faction, gender)
    if (not firsts) or (#firsts == 0) then firsts = t.d.surnames end
    local first  = pickFrom(firsts)
    local parts  = { first = first }
    local roll   = math.random(100)
    if (roll <= 55) then
        -- {first} {last} (~55%)
        parts.surname = pickFrom(t.d.surnames)
        return first .. " " .. parts.surname, parts
    elseif (roll <= 75) then
        -- {Role} {first} (~20%) -- prefix agrees with gender (the "Sister Cedric" fix)
        local prefix = rolePrefix(role, gender)
        if (prefix) then
            parts.prefix = prefix
            return prefix .. " " .. first, parts
        end
        parts.surname = pickFrom(t.d.surnames)                -- defensive fallback
        return first .. " " .. parts.surname, parts
    elseif (roll <= 90) then
        -- {first}, {epithet} (~15%)
        local epithets = PERSONALITIES[personality] and PERSONALITIES[personality].epithets
        if (epithets) and (#epithets > 0) then
            parts.epithet = pickFrom(epithets)
            return first .. ", " .. parts.epithet, parts
        end
        return first, parts  -- defensive fallback
    else
        -- {first} bare (~10%)
        return first, parts
    end
end

-- Roll a gender from the configured weights (relative; need not sum to 100). Drives
-- the first-name sub-pool and role prefix so they always agree.
local function rollGender()
    local m = genderRatio.male    or 0
    local f = genderRatio.female  or 0
    local n = genderRatio.neutral or 0
    local total = m + f + n
    if (total <= 0) then return "neutral" end
    local r = math.random() * total
    if (r < m)     then return "male"   end
    if (r < m + f) then return "female" end
    return "neutral"
end

local function generateName(faction, role, personality, gender)
    local name, parts, guard = nil, nil, 0
    repeat
        name, parts = buildName(faction, role, personality, gender)
        guard = guard + 1
    until (not usedNames[name]) or (guard >= 12)
    return name, parts
end

-- Generic weighted roulette over a key list. baseOf(k) yields the base weight;
-- modifiers is an optional ordered list of {key -> factor} maps stacked
-- multiplicatively (missing key => 1.0, nil-safe). A modifier may zero a weight in
-- one context, but if EVERY effective weight ends up <= 0 we fall back to a uniform
-- pick so generation never stalls. Negative effective weights are clamped to 0.
local function weightedPick(keys, baseOf, modifiers)
    local eff, total = {}, 0
    for _, k in ipairs(keys) do
        local w = baseOf(k) or 1
        if modifiers then
            for _, m in ipairs(modifiers) do
                if (m) and (m[k]) then w = w * m[k] end
            end
        end
        if (w < 0) then w = 0 end
        eff[k], total = w, total + w
    end
    if (total <= 0) then return keys[math.random(#keys)] end
    local r, acc = math.random() * total, 0
    for _, k in ipairs(keys) do
        acc = acc + eff[k]
        if (r <= acc) then return k end
    end
    return keys[#keys]  -- float-rounding fallback
end

-- Soften a conditional modifier map toward 1.0 by traitCorrelationStrength s:
-- eff = 1 + (factor-1)*s. s=1 => authored factors; s=0 => all factors collapse to 1.0
-- (pure base weights), so the strength knob can disable correlations without editing
-- tables. nil/empty in => nil out (no tilt). Every Part B/C modifier flows through here.
local function scaleModifier(m)
    if (not m) then return nil end
    if (traitCorrelationStrength == 1.0) then return m end
    local out = {}
    for k, f in pairs(m) do out[k] = 1 + (f - 1) * traitCorrelationStrength end
    return out
end

-- Trait-vocabulary membership sets, derived from the same tables the pickers use, so
-- arg-form validation (createCharacter / .ac create) auto-tracks new vocab. roleKeys/
-- moodKeys are arrays above; these are {key=true} sets for O(1) checks + valid-set lists.
local function isMember(set, value)
    return (type(value) == "string") and (set[value] == true)
end
local roleSet = {}; for _, k in ipairs(roleKeys) do roleSet[k] = true end
local moodSet = {}; for _, k in ipairs(moodKeys) do moodSet[k] = true end
local areaSet = {}; for _, k in ipairs(AREAS)    do areaSet[k] = true end
local genderSet = { male = true, female = true, neutral = true }
local factionSet = { alliance = true, horde = true }

-- createCharacter(opts) -> character | nil, err. The roster factory. opts (all
-- optional): faction, role, personality, area, gender, name. Any missing field is
-- ROLLED exactly as ambient generation does -- the unrolled path below is identical
-- in RNG order and registration to the pre-refactor generateCharacter, so ambient
-- spawning is unchanged (regression). A supplied override REPLACES that field's roll
-- (and its RNG draw): expected, since explicit creation deliberately bypasses the
-- weighting. Validates supplied traits (unknown role/mood/area/gender/faction ->
-- nil,err); a supplied name is deduped against usedNames (auto-suffixed if taken).
-- Does NOT enforce maxCharacters -- the cap is the caller's decision (resolveSpeaker
-- yields, .ac create refuses) so ambient lazy growth keeps its existing semantics.
local function createCharacter(opts)
    opts = opts or {}

    -- Validate any supplied overrides up front (menus only offer valid values, but
    -- the arg form must guard). Faction resolves to a coin flip when unspecified.
    if (opts.faction ~= nil) and (not isMember(factionSet, opts.faction)) then
        return nil, "faction"
    end
    if (opts.role ~= nil)        and (not isMember(roleSet,   opts.role))        then return nil, "role"   end
    if (opts.personality ~= nil) and (not isMember(moodSet,   opts.personality)) then return nil, "mood"   end
    if (opts.area ~= nil)        and (not isMember(areaSet,   opts.area))        then return nil, "area"   end
    if (opts.gender ~= nil)      and (not isMember(genderSet, opts.gender))      then return nil, "gender" end

    local faction = opts.faction or (math.random() < 0.5 and "alliance" or "horde")

    -- Conditioning traits first so they can tilt role/mood. gender and homeCity are
    -- rolled before role/mood, then fed into the pickers via the gender/faction/city
    -- bias maps below. homeCity is a flat draw (cities are roughly equal); only its
    -- affinity (CITY_BIAS) tilts the resident, not its draw frequency.
    local gender   = opts.gender or rollGender()
    local homeCity = (faction == "horde")
        and pickFrom(hordeCities)
        or  pickFrom(allianceCities)

    local genderRoles  = GENDER_BIAS[gender]   and GENDER_BIAS[gender].roles
    local genderMoods  = GENDER_BIAS[gender]   and GENDER_BIAS[gender].moods
    local factionRoles = FACTION_BIAS[faction] and FACTION_BIAS[faction].roles
    local cityRoles    = CITY_BIAS[homeCity]   and CITY_BIAS[homeCity].roles
    local cityMoods    = CITY_BIAS[homeCity]   and CITY_BIAS[homeCity].moods

    -- Role always uses its base weight. Conditional modifiers (faction/gender/home-city)
    -- apply only when the correlation layer is on. All factors are softened by
    -- traitCorrelationStrength via scaleModifier. A supplied role bypasses the picker.
    local role = opts.role
    if (not role) then
        local roleMods
        if (enableTraitCorrelation) then
            roleMods = {
                scaleModifier(factionRoles),
                scaleModifier(genderRoles),
                scaleModifier(cityRoles),
            }
        end
        role = weightedPick(roleKeys, function(k) return ROLES[k].weight end, roleMods)
    end

    -- Personality honors its weight + role/gender/home-city bias only when the
    -- correlation layer is on; off => legacy uniform draw (preserves today's histogram).
    -- A supplied personality bypasses the picker.
    local personality = opts.personality
    if (not personality) then
        if (enableTraitCorrelation) then
            local moodMods = {
                scaleModifier(ROLES[role].moodBias),
                scaleModifier(genderMoods),
                scaleModifier(cityMoods),
            }
            personality = weightedPick(moodKeys, function(k) return PERSONALITIES[k].weight end, moodMods)
        else
            personality = moodKeys[math.random(#moodKeys)]
        end
    end

    -- area: biased to the role's default area (~65%), else a random AREAS member,
    -- so the roster reads roughly role-typed without being rigid. A supplied area
    -- bypasses the roll.
    -- FUTURE HOOK: derive area from a real player's current zone; v1 is static.
    local area = opts.area
    if (not area) then
        if (math.random() < 0.65) and (ROLES[role].area) then
            area = ROLES[role].area
        else
            area = AREAS[math.random(#AREAS)]
        end
    end

    -- Name: roll a gender-correct one unless supplied. A supplied name is deduped
    -- against the live roster -- auto-suffix " II", " III", ... rather than reject, so
    -- a player asking for a taken name still gets a character. nameParts.first is set
    -- so address/pronoun tokens still work on a custom name.
    local name, nameParts
    if (opts.name) then
        name = opts.name
        if (usedNames[name]) then
            local n = 2
            local base = name
            while usedNames[name] do
                name = base .. " " .. tostring(n)
                n = n + 1
            end
        end
        nameParts = { first = name }
    else
        name, nameParts = generateName(faction, role, personality, gender)
    end

    local character = {
        name         = name,
        gender       = gender,           -- "male" | "female" | "neutral"
        nameParts    = nameParts,        -- { prefix?, first, surname?, epithet? } for address/pronoun use
        faction      = faction,
        role         = role,
        personality  = personality,
        area         = area,
        homeCity     = homeCity,
        chattiness   = math.random(),   -- 0..1 selection weight (RNG seeded in t.init)
        friendliness = math.random(),   -- 0..1 likelihood to join a duo/group
        color        = t.cc[math.random(#t.cc)],  -- stable per-character name colour
    }

    -- Register. (rosterByFaction[faction] is guaranteed for alliance/horde.)
    roster[#roster + 1] = character
    local bucket = rosterByFaction[faction]
    bucket[#bucket + 1] = character
    usedNames[character.name] = true
    return character
end

-- generateCharacter(faction) -> a full character table, registered into roster /
-- rosterByFaction with its name marked used. Thin wrapper over createCharacter with
-- only the faction fixed: the ambient lazy-growth path. Does NOT enforce maxCharacters
-- -- the cap is checked by resolveSpeaker before calling this.
local function generateCharacter(faction)
    return createCharacter({ faction = faction })
end

-- Roster-query seam: two functions funnel all speaker selection.
--   pickCharacter(weightField, filters) -> EXISTING character | nil (never spawns).
--   resolveSpeaker(faction) -> ambient initiator; weighted over existing chars plus
--       one virtual "new character" slot, lazily spawning under the cap.

-- pickCharacter -- existing-only weighted pick. weightField = "chattiness" |
-- "friendliness". filters (all optional): faction, role, mood, area, excludeName.
-- (allowSpawn is ignored here -- spawning is a caller decision.) Returns nil if none match.
local function pickCharacter(weightField, filters)
    filters = filters or {}
    local source = filters.faction and rosterByFaction[filters.faction] or roster
    if (not source) then return nil end

    -- Build the candidate list + summed weight in one pass.
    local candidates, total = {}, 0
    for _, c in ipairs(source) do
        if  ((not filters.role)        or (c.role == filters.role))
        and ((not filters.mood)        or (c.personality == filters.mood))
        and ((not filters.area)        or (c.area == filters.area))
        and ((not filters.excludeName) or (c.name ~= filters.excludeName)) then
            local w = c[weightField] or 0
            if (w > 0) then
                candidates[#candidates + 1] = c
                total = total + w
            end
        end
    end
    if (#candidates == 0) or (total <= 0) then return nil end

    -- Weighted roulette.
    local r, acc = math.random() * total, 0
    for _, c in ipairs(candidates) do
        acc = acc + (c[weightField] or 0)
        if (r <= acc) then return c end
    end
    return candidates[#candidates]  -- float-rounding fallback
end

-- maxCharacters is the global cap; maxCharactersPerFaction (if set) is a per-faction sub-cap.
local function rosterAtCap(faction)
    if (#roster >= maxCharacters) then return true end
    if (maxCharactersPerFaction ~= nil)
        and (#rosterByFaction[faction] >= maxCharactersPerFaction) then
        return true
    end
    return false
end

-- resolveSpeaker(faction) -- ambient initiator. Weighted roulette over same-faction
-- characters (weight = chattiness) PLUS a virtual "new character" slot (weight =
-- newCharacterWeight): if the virtual slot wins and we're under cap -> spawn; at cap
-- -> reuse an existing char; else return the picked char. Self-balancing: as summed
-- chattiness grows the virtual slot wins less, so growth tapers and halts at the cap.
-- (Shared lines call resolveSpeaker("alliance") -> always Alliance-voiced.)
local function resolveSpeaker(faction)
    local bucket = rosterByFaction[faction] or {}

    -- Summed chattiness of existing same-faction characters + the virtual slot.
    local total = newCharacterWeight
    for _, c in ipairs(bucket) do total = total + (c.chattiness or 0) end

    local r, acc = math.random() * total, 0
    -- Roll across existing characters first; whatever is left of the roulette
    -- range belongs to the virtual "new character" slot.
    for _, c in ipairs(bucket) do
        acc = acc + (c.chattiness or 0)
        if (r <= acc) then return c end
    end

    -- Virtual "new character" slot won.
    if (not rosterAtCap(faction)) then
        return generateCharacter(faction)              -- spawn, register, speak now
    end
    -- At the cap: reuse an existing same-faction character.
    return pickCharacter("chattiness", { faction = faction })
end

-- Line scoring + weighted picker. globalTick advances once per emitted item (not
-- per chained line); each item records its lastTick for per-item recency.
local globalTick = 0

-- scoreLine(item, char, tick) -> score >= 0; 0 means EXCLUDE. Final score is the
-- product of these factors:
--   base         = item.weight
--   role/mood    = matchStrength on match, 1.0 if untagged, 1/matchStrength on mismatch
--   area         = 1.0 if global; else weight*strength if char.area is tagged, else 0 (EXCLUDE)
--   time/season  = like area, but also 1.0 when context is off/unavailable (never exclude blindly)
--   event        = binary 1.0/0 (see eventFactor)
--   exclude      = 0 if context lands in a notTimes/notSeasons/notEvents set (see excludeFactor)
--   recency      = 0 within cooldown ticks of last use, ramping back to 1.0 over the next cooldown
-- Untagged role/mood/area always score >0, so a character is never left silent.
local function listContains(list, value)
    if (not list) then return false end
    for _, v in ipairs(list) do
        if (v == value) then return true end
    end
    return false
end

local function matchFactor(list, value)
    if (list == nil) then return 1.0 end                 -- untagged = neutral
    if (listContains(list, value)) then
        return roleMoodMatchStrength                      -- preferred match: boost
    end
    return 1.0 / roleMoodMatchStrength                    -- mismatch: low floor (not 0)
end

local function areaFactor(item, char)
    if (item.areaGlobal) then return 1.0 end              -- untagged = any area
    local w = item.areas[char.area]
    if (not w) then return 0 end                          -- HARD EXCLUDE
    return w * areaMatchStrength
end

-- timeFactor -> parallel to areaFactor: 1.0 if timesGlobal; weight*strength if
-- ctx.timeKey is tagged; 0 (EXCLUDE) if not. Forced 1.0 when flags off or
-- ctx.timeKey unavailable, so a tagged line never excludes itself blindly.
-- Takes explicit (global, map) so both line items AND tagged token entries score
-- through the same code (Phase 8: tokenScorer below normalizes raw token tags into
-- this same shape).
local function timeFactor(timesGlobal, times, c)
    if (timesGlobal) then return 1.0 end                  -- untagged = any time
    -- Context off or unknown -> behave like today's random selection (no exclude).
    if (not enableContextAware) or (not enableTimeContext) then return 1.0 end
    if (not c) or (not c.timeKey) then return 1.0 end
    local w = times[c.timeKey]
    if (not w) then return 0 end                          -- HARD EXCLUDE (off-bucket)
    return w * timeMatchStrength
end

-- seasonFactor -> parallel to timeFactor: 1.0 if seasonsGlobal; weight*strength if
-- ctx.season is tagged; 0 (EXCLUDE) if not. Forced 1.0 when flags off or ctx.season
-- unavailable.
local function seasonFactor(seasonsGlobal, seasons, c)
    if (seasonsGlobal) then return 1.0 end                -- untagged = any season
    -- Context off or unknown -> behave like today's random selection (no exclude).
    if (not enableContextAware) or (not enableSeasonContext) then return 1.0 end
    if (not c) or (not c.season) then return 1.0 end
    local w = seasons[c.season]
    if (not w) then return 0 end                          -- HARD EXCLUDE (off-season)
    return w * seasonMatchStrength
end

-- eventFactor -> 1.0 or 0, BINARY (an event-tagged line is ABOUT that event, so it
-- applies or it doesn't). 1.0 if untagged, flags off, or nothing knowable (empty
-- ctx.active AND no schedule -- never exclude on a guess). Otherwise 1.0 when a
-- tagged event is live, or within eventWindow: "approach" (== ctx.nextEvent within
-- eventApproachDays) / "after" (== ctx.lastEvent within eventAfterDays); else 0.
local function eventFactor(eventsGlobal, events, eventWindow, c)
    if (eventsGlobal) then return 1.0 end                 -- untagged = any/no event
    if (not enableContextAware) or (not enableEventContext) then return 1.0 end

    local active   = c and c.active
    local liveKnown = active and (next(active) ~= nil)
    local window   = eventWindow or "active"
    -- If neither the active set nor the relevant nearest-event slot is known, we
    -- can't judge -> don't exclude (fallback invariant).
    local nearKnown = false
    if (window == "approach") then nearKnown = (c and c.nextEvent) ~= nil
    elseif (window == "after") then nearKnown = (c and c.lastEvent) ~= nil end
    if (not liveKnown) and (not nearKnown) then return 1.0 end  -- nothing to judge on

    -- Active now (any window includes the live event).
    if (liveKnown) then
        for _, name in ipairs(events) do
            if (active[name]) then return 1.0 end
        end
    end

    -- Approach window: the line's event is the soonest-upcoming, within the lead.
    if (window == "approach") and (c and c.nextEvent) then
        if (c.nextEvent.daysAway <= eventApproachDays) then
            for _, name in ipairs(events) do
                if (name == c.nextEvent.name) then return 1.0 end
            end
        end
    end

    -- After window: the line's event is the most-recently-ended, within the tail.
    if (window == "after") and (c and c.lastEvent) then
        if (c.lastEvent.daysAgo <= eventAfterDays) then
            for _, name in ipairs(events) do
                if (name == c.lastEvent.name) then return 1.0 end
            end
        end
    end

    return 0                                              -- HARD EXCLUDE (out of window)
end

-- scoreTokenEntry(tags, c) -> weight for a TAGGED TOKEN-POOL entry (Phase 8). Shares
-- the exact time/season/event factor code lines use, so a token value "fits the
-- moment" by the same rules a chatter line does. `tags` is the raw entry table from
-- data/tokens.lua ({ value=..., times/seasons/events=... }); normalize its sub-fields
-- on the fly (cheap, only for the few tagged pools) then multiply the factors. Any
-- factor returning 0 hard-excludes the value; with context off / ctx unavailable every
-- factor is 1 -> weight 1 (uniform fallback, preserved). Injected via pools.setTagScorer.
local function scoreTokenEntry(tags, c)
    local timesGlobal, times       = normalizeWeightedSet(tags.times)
    local seasonsGlobal, seasons   = normalizeWeightedSet(tags.seasons)
    local eventsGlobal, eventsList = normalizeEvents(tags.events)
    local tf = timeFactor(timesGlobal, times, c)
    if (tf <= 0) then return 0 end
    local sf = seasonFactor(seasonsGlobal, seasons, c)
    if (sf <= 0) then return 0 end
    local ef = eventFactor(eventsGlobal, eventsList, "active", c)
    if (ef <= 0) then return 0 end
    return tf * sf * ef
end
pools.setTagScorer(scoreTokenEntry)

-- excludeFactor -> 1.0 or 0. The NEGATIVE gate over notTimes/notSeasons/notEvents,
-- checked for EVERY line (even global ones) so a universal line can carve out one
-- context. Returns 0 when ctx.timeKey/ctx.season is in the set, or a notEvents event
-- is active. Each dimension respects its sub-flag and only excludes when ctx is known.
local function excludeFactor(item, c)
    if (not enableContextAware) then return 1.0 end       -- feature off => no exclusions
    if (not c) then return 1.0 end

    -- Time-of-day exclusion.
    if (enableTimeContext) and (c.timeKey) and (item.notTimes) then
        if (item.notTimes[c.timeKey]) then return 0 end
    end
    -- Season exclusion.
    if (enableSeasonContext) and (c.season) and (item.notSeasons) then
        if (item.notSeasons[c.season]) then return 0 end
    end
    -- Active-event exclusion (binary, keyed off the live event set).
    if (enableEventContext) and (item.notEvents) and (c.active) then
        for name, _ in pairs(item.notEvents) do
            if (c.active[name]) then return 0 end
        end
    end

    return 1.0
end

local function recencyPenalty(item, tick)
    local last = item.lastTick
    if (not last) then return 1.0 end                     -- never used
    local cd   = item.cooldown or lineCooldownTicks
    if (cd <= 0) then return 1.0 end
    local since = tick - last
    if (since >= 2 * cd) then return 1.0 end              -- fully recovered
    if (since <= cd) then return 0 end                    -- within cooldown: suppressed
    -- ramp 0 -> 1 over the second cooldown window.
    return (since - cd) / cd
end

local function scoreLine(item, char, tick)
    local af = areaFactor(item, char)
    if (af <= 0) then return 0 end                        -- area can hard-exclude
    local tf = timeFactor(item.timesGlobal, item.times, ctx)
    if (tf <= 0) then return 0 end                        -- times can hard-exclude (off-bucket)
    local sf = seasonFactor(item.seasonsGlobal, item.seasons, ctx)
    if (sf <= 0) then return 0 end                        -- seasons can hard-exclude (off-season)
    local ef = eventFactor(item.eventsGlobal, item.events, item.eventWindow, ctx)
    if (ef <= 0) then return 0 end                        -- events can hard-exclude (none active)
    local xf = excludeFactor(item, ctx)
    if (xf <= 0) then return 0 end                        -- notTimes/notSeasons/notEvents can hard-exclude
    local base = item.weight or 1
    local rf   = matchFactor(item.roles, char.role)
    local mf   = matchFactor(item.moods, char.personality)
    -- genderFactor: same boost/floor as role/mood. A gendered line is never required
    -- (untagged => 1.0, mismatch => low floor, never 0) so no character goes silent.
    local gf   = matchFactor(item.genders, char.gender)
    local rp   = recencyPenalty(item, tick)
    return base * rf * mf * gf * af * tf * sf * ef * xf * rp
end

-- pickLine -> item | nil. Scores every candidate, weighted-random picks among
-- score>0 items. If all are excluded, falls back to any global item so the speaker
-- is never silent; returns nil only when there is truly nothing to say.
local function pickLine(candidates, char, tick)
    local scored, total = {}, 0
    for _, item in ipairs(candidates) do
        local s = scoreLine(item, char, tick)
        if (s > 0) then
            scored[#scored + 1] = { item = item, score = s }
            total = total + s
        end
    end

    if (#scored == 0) or (total <= 0) then
        -- Hard-exclusion fallback: any global item (ignores recency/role/mood).
        for _, item in ipairs(candidates) do
            if (item.areaGlobal) then return item end
        end
        return nil                                         -- truly nothing to say
    end

    local r, acc = math.random() * total, 0
    for _, s in ipairs(scored) do
        acc = acc + s.score
        if (r <= acc) then return s.item end
    end
    return scored[#scored].item                            -- float-rounding fallback
end

-- Cast assembly. For a duo/group the initiator is voice A; co-speakers are drawn
-- from the castFaction roster (Alliance for shared lines) weighted by friendliness,
-- preferring role/mood/area match, deduped, lazily spawned if the roster is thin
-- (cap-aware). Each member is a full character (name + stable color).
local function assembleCast(initiator, item, castFaction)
    if (item.kind == "line") then
        return { initiator }                               -- single voice
    end

    local size = (item.kind == "duo") and 2 or math.random(4, 6)
    -- A group never needs more voices than its chain has lines.
    if (item.kind == "group") and (size > #item.data) then size = #item.data end
    if (size < 2) then size = 2 end

    local cast = { initiator }
    local used = { [initiator.name] = true }

    while (#cast < size) do
        -- Prefer a friendly same-faction resident matching the line's tags.
        -- We try progressively looser filters so a thin roster still fills:
        --   1) role+mood+area match, 2) area only, 3) any same-faction char.
        local pick
        local wantRole = item.roles and item.roles[1] or nil
        local wantMood = item.moods and item.moods[1] or nil
        local wantArea = (not item.areaGlobal) and next(item.areas) or nil
        -- next() on the area map yields one tagged area key (good enough as a
        -- soft preference; scoring already enforces hard area rules on the LINE).

        pick = pickCharacter("friendliness", {
            faction = castFaction, role = wantRole, mood = wantMood,
            area = wantArea, excludeName = nil })
        if (pick) and (used[pick.name]) then pick = nil end

        if (not pick) then
            -- Looser: drop role/mood, keep faction (area optional).
            pick = pickCharacter("friendliness", { faction = castFaction })
            -- dedup against the existing cast.
            if (pick) and (used[pick.name]) then
                pick = pickCharacter("friendliness",
                    { faction = castFaction, excludeName = initiator.name })
            end
        end

        if (not pick) or (used[pick.name]) then
            -- Roster too thin / only dupes available -> lazily spawn (cap-aware).
            if (not rosterAtCap(castFaction)) then
                pick = generateCharacter(castFaction)
            else
                break                                      -- at cap, can't fill more
            end
        end

        if (pick) and (not used[pick.name]) then
            cast[#cast + 1] = pick
            used[pick.name] = true
        else
            break                                          -- give up; emit a shorter cast
        end
    end

    return cast
end

-- Pick which cast member voices line `ti` (1-based). Duos alternate A/B/A/B;
-- groups pick a random member, never the same voice twice in a row.
local function speakerForLine(cast, kind, ti, prevName)
    if (#cast == 1) then return cast[1] end
    if (kind == "duo") then
        return (ti % 2 == 1) and cast[1] or cast[2]
    end
    -- group
    local pick, guard = cast[math.random(#cast)], 0
    while (pick.name == prevName) and (#cast > 1) and (guard < 12) do
        pick = cast[math.random(#cast)]
        guard = guard + 1
    end
    return pick
end


t.init = function(s)
    -- Seed the RNG ONCE at startup (reseeding per line tied variety to the wall clock).
    math.randomseed(os.time())
    math.random(); math.random(); math.random()  -- discard first low-entropy values
    s.d = require("data.names") or {}
    -- Back-compat: a flat name list (no faction keys) is treated as the surname pool.
    if (s.d[1] ~= nil) then s.d = {surnames = s.d} end
    s.d.surnames = s.d.surnames or {}
    s.d.alliance = s.d.alliance or {}
    s.d.horde    = s.d.horde    or {}
    if (ns ~= "") then
        -- Optional DB name source -> fed into the surname pool.
        local q = WorldDBQuery(ns)
        if (q) then
            repeat
                table.insert(s.d.surnames, q:GetString(0))
            until not q:NextRow()
        end
    end
end
t:init()

-- Conversation state machine over characters. A "channel" drives a candidate set;
-- per-channel state in t.conv[channel] lets a started duo/group finish line-by-line
-- with its FIXED cast before a new item begins. State fields: item (in-progress, nil
-- = start fresh), cast, ti (next chain line index), prevName (no-repeat guard),
-- speaker, audience (routing tag). A `line` is one-shot; a duo/group runs to the end.
t.conv = {}

-- Resolve %city% for the current speaker. homeCityBias=true -> the speaker's own
-- homeCity (faction-correct, since homeCity is drawn from that faction's capitals;
-- neutral hubs never appear here). false -> random over all cities. Called per LINE
-- so each cast member in a duo/group self-references their own home.
local function cityFor(speaker)
    if (homeCityBias) and (speaker) and (speaker.homeCity) then
        return speaker.homeCity
    end
    return pools.selectRandomCity()
end

-- Resolve the character `speaker` is addressing in a chain, for %target%/%targetfull%.
--   duo:   the OTHER cast member (B addresses A and vice-versa).
--   group: the previous speaker's character (so the line reads as a reply); on the
--          first line (no prevName) fall back to a random other cast member.
--   line:  no target (nil) -> the target tokens fall back to a vocative.
-- Returns a full character (needs nameParts + gender), looked up in `cast` by name.
local function targetForLine(cast, kind, speaker, prevName)
    if (type(cast) ~= "table") or (#cast < 2) then return nil end
    if (kind == "duo") then
        return (cast[1].name == speaker.name) and cast[2] or cast[1]
    end
    -- group: prefer the prior speaker; fall back to any other member.
    local target
    if (prevName) and (prevName ~= speaker.name) then
        for _, c in ipairs(cast) do
            if (c.name == prevName) then target = c; break end
        end
    end
    if (not target) then
        local guard = 0
        repeat
            target = cast[math.random(#cast)]
            guard = guard + 1
        until (target.name ~= speaker.name) or (guard >= 12)
        if (target.name == speaker.name) then return nil end
    end
    return target
end

-- Begin or continue the conversation on `channel`. Returns rawText, speaker,
-- audience, item (item lets the renderer honour the line's `events` tag for
-- %event%), target (addressed cast member for %target%, or nil). Advances the
-- per-channel state and global tick.
local function nextLine(channel, candidates, initiator, castFaction)
    local st = t.conv[channel]
    if (not st) then st = {}; t.conv[channel] = st end

    -- Continue an in-progress duo/group chain with its FIXED cast first.
    if (st.item) and (st.item.kind ~= "line") and (st.ti <= #st.item.data) then
        local item = st.item
        local ti   = st.ti
        local speaker = speakerForLine(st.cast, item.kind, ti, st.prevName)
        -- Resolve target BEFORE overwriting prevName (group target = prior speaker).
        local target = targetForLine(st.cast, item.kind, speaker, st.prevName)
        st.ti       = ti + 1
        st.prevName = speaker.name
        st.speaker  = speaker
        if (st.ti > #item.data) then st.item = nil end       -- chain finished
        return item.data[ti], speaker, st.audience, item, target
    end

    -- Start a fresh item for this speaker. The continue branch above handles
    -- mid-chain advancement off st.item/st.cast alone; the burst runner relies on
    -- that and calls in with nil candidates/initiator. Guard so a spurious nil-call
    -- (chain already cleared) returns cleanly instead of indexing nil candidates.
    if (not candidates) or (not initiator) then return nil end
    globalTick = globalTick + 1
    local item = pickLine(candidates, initiator, globalTick)
    if (not item) then return nil end                        -- nothing to say
    item.lastTick = globalTick                                -- record recency

    if (item.kind == "line") then
        st.item     = nil
        st.cast     = { initiator }
        st.audience = item.audience
        st.speaker  = initiator
        st.prevName = initiator.name
        return item.data, initiator, item.audience, item     -- no target for a single line
    end

    -- Duo/group: fix the cast now and emit its first line.
    local cast = assembleCast(initiator, item, castFaction)
    st.cast     = cast
    st.audience = item.audience
    local speaker = speakerForLine(cast, item.kind, 1, nil)
    local target  = targetForLine(cast, item.kind, speaker, nil)  -- first line: random other
    st.prevName = speaker.name
    st.speaker  = speaker
    st.ti       = 2
    st.item     = (#item.data > 1) and item or nil           -- chain or one-line
    return item.data[1], speaker, item.audience, item, target
end

-- Event-activation burst -- OPTIONAL, disabled by default (config.enableEventBurst =
-- false), so a dead path unless enabled. Kept inline rather than in its own module
-- because it is tightly coupled to the conversation machinery (makeItem, assembleCast,
-- resolveSpeaker, t.conv). context.lua's refreshCtx calls the registered hook
-- (setEventBurstHook, below) once when an event flips active: a short duo item is built
-- with makeItem (tagged with the event so %event% agrees), a cast assembled, and the
-- item SEEDED into t.conv so the next speak() tick plays it like an ambient duo. Voiced
-- everyone-visible (audience="shared") by an Alliance cast. Fully nil-/flag-guarded:
-- never errors, never clobbers an in-progress chain.

-- Burst content pool from data/context.lua + inline fallback. Each entry is a
-- two-line duo chain; %event% is filled at render time.
local eventBurstPool = (type(ctxMap.eventBurst) == "table" and #ctxMap.eventBurst > 0)
    and ctxMap.eventBurst
    or {
        { "Word is %event% has begun -- did you hear?", "Aye, just now. Best get to the city." },
        { "%event% starts today, friend.", "Then what are we waiting for? Let's go." },
    }

local function fireEventBurst(eventName)
    if (not enableEventBurst) then return end                -- flag guard (belt & braces)
    if (type(eventName) ~= "string") or (eventName == "") then return end
    if (type(eventBurstPool) ~= "table") or (#eventBurstPool == 0) then return end

    local channel = "alliance"                               -- shared lines are Alliance-voiced
    local st = t.conv[channel]
    -- Don't clobber an in-progress chain -- only seed when the channel is idle.
    if (st) and (st.item) and (st.item.kind ~= "line") then return end

    -- Build a duo burst item tagged with the event (forceChain so {a,b} is a chain).
    local chain = eventBurstPool[math.random(#eventBurstPool)]
    if (type(chain) ~= "table") or (#chain < 1) then return end
    local item = makeItem("duo", { chain = chain, events = { eventName } }, true)
    item.audience = "shared"                                 -- everyone-visible
    item.lastTick = globalTick

    -- Assemble a same-faction cast around a resolved Alliance speaker.
    local initiator = resolveSpeaker("alliance")
    if (not initiator) then return end                       -- no character available -> skip
    local cast = assembleCast(initiator, item, "alliance")
    if (type(cast) ~= "table") or (#cast < 1) then return end

    -- Seed the state so the next speak("alliance") tick plays the chain from line 1
    -- (same shape nextLine leaves behind for a duo).
    t.conv[channel] = {
        item     = item,
        cast     = cast,
        ti       = 1,
        prevName = nil,
        speaker  = initiator,
        audience = "shared",
    }
end

-- Register the burst with the context subsystem; refreshCtx invokes it (gated on
-- enableEventBurst) when an event flips active. Default-off: dead unless enabled.
context.setEventBurstHook(fireEventBurst)

-- Neutral vocatives for %target%/%targetfull% when there is no addressed character
-- (a single `line`, or a mis-tagged chain) so the token never renders literally.
local targetVocatives = { "friend", "traveler", "stranger", "neighbor", "comrade" }

-- Weighted short-form address over the parts that exist on `c.nameParts`. Lets a
-- "Captain Cedric" be addressed as "Captain", "Cedric", or his full name so replies
-- feel natural. Weights: prefix 30 / first 45 / prefix+first 15 / full 10; when there
-- is no prefix, its weight folds into "first alone". No target -> a random vocative.
local function addressName(c)
    if (type(c) ~= "table") then
        return targetVocatives[math.random(#targetVocatives)]
    end
    local np    = c.nameParts or {}
    local first = np.first or c.name
    local hasPrefix = (type(np.prefix) == "string") and (np.prefix ~= "")
    local r = math.random(100)
    if (hasPrefix) then
        if (r <= 30) then return np.prefix end                       -- prefix alone
        if (r <= 75) then return first end                           -- first alone (45%)
        if (r <= 90) then return np.prefix .. " " .. first end       -- prefix + first (15%)
        return c.name                                                -- full name (10%)
    end
    -- No prefix: the 30% prefix weight folds into "first alone" -> first 75%, full 25%.
    if (r <= 90) then return first end
    return c.name
end

-- Token -> resolver dispatch. One entry per %token%; the value is called as
-- f(speaker, ctx, item, target) and returns the substitution. Pool tokens ignore the
-- args (Lua drops extras); context/speaker-/target-aware tokens use them. To add a
-- token: add one line here and use it in chatter -- no gsub plumbing. An unmapped
-- %token% is left intact (so orphans are visible, never crash). Replaces the old wall
-- of ~50 sequential gsub calls; order no longer matters (each token keyed by name).
local tokenResolvers = {
    zone       = pools.selectRandomZone,        instance   = pools.selectRandomInstance,
    role       = pools.selectRandomRole,        class      = pools.selectRandomClass,
    bg         = pools.selectRandomBattleground, profession = pools.selectRandomProfession,
    activity   = pools.selectRandomActivity,    herb       = pools.selectRandomHerb,
    ore        = pools.selectRandomOre,          gem        = pools.selectRandomGem,
    fish       = pools.selectRandomFish,         npc        = pools.selectRandomNpc,
    currency   = pools.selectRandomCurrency,     food       = pools.selectRandomFood,
    drink      = pools.selectRandomDrink,        title      = pools.selectRandomTitle,
    tradegood  = pools.selectRandomTradegood,    companion  = pools.selectRandomCompanion,
    enchant    = pools.selectRandomEnchant,      toy        = pools.selectRandomToy,
    race       = pools.selectRandomRace,         monster    = pools.selectRandomMonster,
    critter    = pools.selectRandomCritter,      boss       = pools.selectRandomBoss,
    consumable = pools.selectRandomConsumable,   item       = pools.selectRandomItem,
    rep        = pools.selectRandomRep,          mount      = pools.selectRandomMount,
    spell      = pools.selectRandomSpell,        rare       = pools.selectRandomRare,
    pvptitle   = pools.selectRandomPvpTitle,     emote      = pools.selectRandomEmote,
    difficulty = pools.selectRandomDifficulty,   gold       = pools.selectRandomGold,
    level      = pools.selectRandomLevel,        gearscore  = pools.selectRandomGearscore,
    shop       = pools.selectRandomShop,         route      = pools.selectRandomRoute,
    tale       = pools.selectRandomTale,         weather    = pools.selectRandomWeather,
    -- Combined article tokens (Part B): "a/an <value>" in one step, vowel-aware, never
    -- prefixing a proper name. Use these instead of "a %food%" so a/an is always right.
    afood      = pools.selectRandomAFood,        adrink     = pools.selectRandomADrink,
    acompanion = pools.selectRandomACompanion,   atoy       = pools.selectRandomAToy,
    acritter   = pools.selectRandomACritter,
    -- Speaker pronouns, resolved from speaker.gender (default neutral when unset).
    heshe     = function(speaker)       local g = speaker and speaker.gender; return g == "male" and "he"  or g == "female" and "she"   or "they"  end,
    himher    = function(speaker)       local g = speaker and speaker.gender; return g == "male" and "him" or g == "female" and "her"   or "them"  end,
    hisher    = function(speaker)       local g = speaker and speaker.gender; return g == "male" and "his" or g == "female" and "her"   or "their" end,
    manwoman  = function(speaker)       local g = speaker and speaker.gender; return g == "male" and "man" or g == "female" and "woman" or "one"   end,
    -- Target address (chain-only; falls back to a vocative when no target is set).
    target     = function(_, _, _, target) return target and addressName(target) or targetVocatives[math.random(#targetVocatives)] end,
    targetfull = function(_, _, _, target) return (target and target.name) or targetVocatives[math.random(#targetVocatives)] end,
    -- Speaker-/context-aware (use the extra args):
    city      = function(speaker)       return cityFor(speaker) end,
    event     = function(_, ctx, item)  return resolveEvent(item, ctx) end,
    nextevent = function(_, ctx)        return resolveNextEvent(ctx) end,
    lastevent = function(_, ctx)        return resolveLastEvent(ctx) end,
    season    = function(_, ctx)        return resolveSeason(ctx) end,
    timeofday = function(_, ctx)        return resolveTimeOfDay(ctx) end,
}

-- Run the full %token% substitution on `txt` in ONE pass. `ctx`/`item`/`target` are
-- optional; when absent (or context off) the context-aware tokens fall back to random
-- helpers and the target tokens fall back to a vocative. `item` lets %event% honour the
-- line's `events` tag (see resolveEvent); `target` is the addressed cast member in a
-- chain. An unknown %token% is returned untouched (the gsub callback returns nil).
local function renderTokens(txt, speaker, ctx, item, target)
    return (string.gsub(txt, "%%(%w+)%%", function(tok)
        local f = tokenResolvers[tok]
        if (not f) then return nil end                       -- unmapped: leave %tok% intact
        local v = f(speaker, ctx, item, target)
        if (v == nil) then return nil end
        return tostring(v)
    end))
end

-- Wrap a line in the colored [World] name prefix. The color is the speaker's stable
-- per-character color (set once at generation), so a recurring voice keeps its identity.
local function formatWorld(speaker, body)
    local name  = speaker.name
    local color = speaker.color
    return string.format("|cFFFFC0C0[World] |r|cff%s|Hplayer:%s|h[%s]|h|r: |cFFFFC0C0%s|r",
        color, name, name, body)
end

-- Route a rendered message to the right listeners by the line's audience tag:
--   shared   -> SendWorldMessage (everyone)
--   alliance -> Alliance players only (team 0)
--   horde    -> Horde players only    (team 1)
local function emit(audience, msg)
    if (audience == "shared") then
        SendWorldMessage(msg)
        return
    end
    -- Stock ALE's GetPlayersInWorld(team) already filters by team (0=Alliance,
    -- 1=Horde). We ALSO re-check p:GetTeam() so a faction-only line never leaks
    -- cross-faction even if a future ALE build ignores the team argument.
    local team = (audience == "horde") and 1 or 0
    local players = GetPlayersInWorld(team)
    if (not players) then return end
    for _, p in pairs(players) do
        if (type(p.GetTeam) ~= "function") or (p:GetTeam() == team) then
            p:SendBroadcastMessage(msg)
        end
    end
end

-- Render + route one already-resolved chain step (shared by speak and the burst
-- runner so they format/emit identically).
local function deliver(raw, speaker, audience, item, target)
    local body = renderTokens(raw, speaker, ctx, item, target)
    recordTopic(raw)                                         -- FORWARD-COMPAT no-op (chat-topic awareness)
    emit(audience, formatWorld(speaker, body))
end

-- runChainBurst -- self-rescheduling one-shot timer that plays the rest of an
-- in-progress duo/group at convLineGap pacing, decoupled from the ambient cadence.
-- The cast is FIXED at start (st.cast); this only re-voices it via nextLine's
-- continue path (nil candidates/initiator). It reschedules until the chain clears,
-- a convMaxLines airtime cap is hit, or the channel state is gone (interrupted) --
-- so one-shot timers never accumulate and an interrupted chain ends without orphans.
-- ZONE NOTE: with zone-aware delivery, key t.conv by zone bucket; this runner must
-- target the same delivery group the chain started in (carry the bucket, not just channel).
local function runChainBurst(channel, castFaction)
    local gap = math.random(convLineGap[1], convLineGap[2])
    CreateLuaEvent(function()
        local st = t.conv[channel]
        if (not st) or (not st.item) or (st.item.kind == "line") then
            if (st) then st.bursting = false end             -- finished/cleared/interrupted
            return
        end
        -- Airtime cap: stop voicing further lines, abandon the chain cleanly.
        if (convMaxLines) and (st.aired) and (st.aired >= convMaxLines) then
            st.item, st.bursting = nil, false
            return
        end
        local raw, speaker, audience, item, target = nextLine(channel, nil, nil, castFaction)
        if (raw) then
            st.aired = (st.aired or 1) + 1
            deliver(raw, speaker, audience, item, target)
        end
        if (t.conv[channel]) and (t.conv[channel].item) then
            runChainBurst(channel, castFaction)              -- more lines: reschedule
        elseif (t.conv[channel]) then
            t.conv[channel].bursting = false                 -- chain done: release the channel
        end
    end, gap, 1)
end

-- Drive one emission on `channel`: resolve a speaker, pick & render a line, route
-- it by the line's audience tag. Returns silently if nothing can be said.
local function speak(channel, candidates, castFaction)
    -- A mid-flight burst owns this channel; the ambient tick must yield so it never
    -- starts a second item or double-emits a line the runner already handles.
    local cur = t.conv[channel]
    if (enableBurstConversations) and (cur) and (cur.bursting) then return end

    refreshCtx()                                             -- cheap (TTL-guarded); keeps ctx fresh
    local initiator = resolveSpeaker(castFaction)
    if (not initiator) then return end                       -- no character available
    local raw, speaker, audience, item, target = nextLine(channel, candidates, initiator, castFaction)
    if (not raw) then return end
    deliver(raw, speaker, audience, item, target)

    -- Burst hand-off: nextLine left st.item set => this is a multi-line chain mid-flight.
    -- speak emitted line 1; hand the rest to the burst runner and stop advancing the
    -- chain on ambient ticks. Legacy (flag off): leave st.item for the next tick to advance.
    if (enableBurstConversations) then
        local st = t.conv[channel]
        if (st) and (st.item) and (st.item.kind ~= "line") then
            st.bursting = true
            st.aired    = 1                                  -- line 1 just aired (for convMaxLines)
            runChainBurst(channel, castFaction)
        end
    end
end

-- Events --------------------------------------------------------------------
-- Two timers, mapped to FACTIONS (candidates are per-speaker-faction):
--   * alliance-driver -> an Alliance speaker over allianceCandidates (shared +
--       alliance). Each line routes by its OWN audience tag, so this one timer
--       carries both everyone-visible and Alliance-only chatter (on talk_time).
--   * horde-driver    -> a Horde speaker over hordeCandidates, Horde-only (faction_talk_time).
-- No separate alliance-only timer: Alliance-only lines are already alliance-origin
-- items in the Alliance set, so a third timer would double-voice them.
-- Legacy (enableFactionChat=false): both pools merged, all audience="shared", so
-- both timers broadcast everything to everyone.

-- Alliance-driver (also carries everyone-visible shared lines).
CreateLuaEvent(function()
    speak("alliance", allianceCandidates, "alliance")
end, {talk_time[1], talk_time[2]}, 0)

if enableFactionChat then
    -- Horde-driver: Horde speakers, Horde-only audience.
    CreateLuaEvent(function()
        speak("horde", hordeCandidates, "horde")
    end, {faction_talk_time[1], faction_talk_time[2]}, 0)
else
    -- Legacy: a second everyone-visible driver over the merged pool (keeps the
    -- original two-timer cadence). Alliance-voiced; audience="shared" -> everyone.
    CreateLuaEvent(function()
        speak("horde", hordeCandidates, "alliance")
    end, {faction_talk_time[1], faction_talk_time[2]}, 0)
end

-- One-line load confirmation to the worldserver log (the script is otherwise silent).
if (type(PrintInfo) == "function") then
    PrintInfo(string.format(
        "[ActiveChat] loaded: %d alliance / %d horde candidate lines; context=%s, factionChat=%s",
        #allianceCandidates, #hordeCandidates,
        enableContextAware and "on" or "off",
        enableFactionChat and "on" or "off"))
end

-- Player commands (.ac …) --------------------------------------------------
-- Out-of-character worldbuilding/debug tooling, NOT chatter: all output goes to the
-- requesting player via SendBroadcastMessage, never into World chat. Gated on
-- enablePlayerCommands; the whole block is skipped (and no hooks registered) when off.
-- Player-created characters share the maxCharacters cap with ambient spawns (simplest
-- model; see the cap note in .ac create) and are ephemeral like every roster member.
if (enablePlayerCommands) then

    -- Per-player scratch: gossip create wizard state + per-session create count, keyed
    -- by GUIDLow. Cleared on confirm/cancel/logout so a relog resets the spam allowance.
    local pcreate     = {}   -- guidLow -> partial { faction, role, personality, gender, area, name }
    local createCount = {}   -- guidLow -> characters spawned this session

    -- A dedicated player-gossip menu id for the create wizard. Must not collide with a
    -- real gossip_menu DB row; high custom ids are conventional for ALE-only menus.
    local PCREATE_MENU = 0xACC0

    local function msg(player, line)
        player:SendBroadcastMessage(line)
    end

    -- Compact one-line roster-entry summary (used by .ac list and .ac who header).
    local function summaryLine(c)
        return string.format("[ActiveChat] %s -- %s %s, %s | %s, %s",
            c.name, c.faction, c.role, c.gender, c.personality, c.area)
    end

    local function helpText(player)
        msg(player, "[ActiveChat] commands (output is private; characters are in-memory and vanish on restart):")
        msg(player, "  .ac create                     - open the trait-picker menu")
        msg(player, "  .ac create k=v [k=v ...]        - faction/role/mood/gender/area/name=\"...\"")
        msg(player, "  .ac who <name>                  - show a roster character's traits")
        msg(player, "  .ac list [alliance|horde]       - list current roster")
        msg(player, "  .ac help                        - this text")
    end

    -- Sorted, comma-joined valid set for a trait dimension (error messages list it).
    local function joinKeys(arr)
        local copy = {}
        for i = 1, #arr do copy[i] = arr[i] end
        table.sort(copy)
        return table.concat(copy, ", ")
    end

    -- .ac who <name> -- case-insensitive exact, then case-insensitive prefix. Ambiguous
    -- prefix (>1 match, no exact) lists the candidate names instead of dumping one.
    local function cmdWho(player, name)
        if (not name) or (name == "") then
            msg(player, "[ActiveChat] usage: .ac who <name>")
            return
        end
        local lname = string.lower(name)
        local exact, prefix = nil, {}
        for _, c in ipairs(roster) do
            local lc = string.lower(c.name)
            if (lc == lname) then exact = c; break end
            if (string.sub(lc, 1, #lname) == lname) then prefix[#prefix + 1] = c end
        end
        local hit = exact or (#prefix == 1 and prefix[1]) or nil
        if (not hit) then
            if (#prefix > 1) then
                msg(player, string.format("[ActiveChat] %d matches for '%s':", #prefix, name))
                for _, c in ipairs(prefix) do msg(player, "  " .. c.name) end
            else
                msg(player, string.format("[ActiveChat] no roster character matching '%s'.", name))
            end
            return
        end
        -- Compact dump.
        msg(player, string.format("[ActiveChat] %s -- %s %s, %s",
            hit.name, hit.faction, hit.role, hit.gender))
        msg(player, string.format("  personality: %s   area: %s   home: %s",
            hit.personality, hit.area, hit.homeCity))
        msg(player, string.format("  chattiness: %.2f   friendliness: %.2f",
            hit.chattiness or 0, hit.friendliness or 0))
    end

    -- .ac list [faction] -- one line per character, capped output so a full roster
    -- doesn't flood chat; prints "+N more" when truncated.
    local LIST_CAP = 40
    local function cmdList(player, faction)
        if (faction ~= nil) and (not isMember(factionSet, faction)) then
            msg(player, "[ActiveChat] faction must be alliance or horde.")
            return
        end
        local source = faction and rosterByFaction[faction] or roster
        local n = #source
        if (n == 0) then
            msg(player, "[ActiveChat] roster is empty (it grows as the world chatters).")
            return
        end
        msg(player, string.format("[ActiveChat] %d character%s%s:",
            n, n == 1 and "" or "s", faction and (" (" .. faction .. ")") or ""))
        local shown = math.min(n, LIST_CAP)
        for i = 1, shown do msg(player, "  " .. summaryLine(source[i]):gsub("^%[ActiveChat%] ", "")) end
        if (n > shown) then msg(player, string.format("  ... +%d more", n - shown)) end
    end

    -- GM gate for create (when playerCreateGmOnly). Defensive about which method the
    -- build exposes (IsGameMaster / IsGM / GetGMRank) so it works across ALE versions.
    local function isGm(player)
        if (type(player.IsGameMaster) == "function") then return player:IsGameMaster() end
        if (type(player.IsGM) == "function")          then return player:IsGM() end
        if (type(player.GetGMRank) == "function")     then return (player:GetGMRank() or 0) > 0 end
        return false
    end

    -- Shared create entrypoint: gate (GM-only + per-session limit + roster cap), then
    -- createCharacter, then announce to the requester. Returns the character or nil.
    local function doCreate(player, opts)
        if (playerCreateGmOnly) and (not isGm(player)) then
            msg(player, "[ActiveChat] .ac create is restricted to GMs on this server.")
            return nil
        end
        local guid = player:GetGUIDLow()
        local used = createCount[guid] or 0
        if (used >= playerCreateLimit) then
            msg(player, string.format("[ActiveChat] you've created your session limit of %d characters.", playerCreateLimit))
            return nil
        end
        -- Resolve the faction the cap is checked against (createCharacter coin-flips an
        -- unspecified faction, but the cap pre-check needs a concrete one; mirror its
        -- default so the check matches the spawn).
        local faction = opts.faction or (math.random() < 0.5 and "alliance" or "horde")
        opts.faction = faction
        -- Cap model: player creations share maxCharacters with ambient spawns (simple,
        -- no separate accounting). ALTERNATIVE (not taken): a reserved slice so players
        -- can't starve ambient variety -- would need a second cap + counter here.
        if (rosterAtCap(faction)) then
            msg(player, "[ActiveChat] the roster is full -- cannot create another character right now.")
            return nil
        end
        local c, err = createCharacter(opts)
        if (not c) then
            local valid = (err == "role" and joinKeys(roleKeys))
                or (err == "mood"   and joinKeys(moodKeys))
                or (err == "area"   and joinKeys(AREAS))
                or (err == "gender" and "male, female, neutral")
                or (err == "faction" and "alliance, horde")
                or ""
            msg(player, string.format("[ActiveChat] invalid %s. valid: %s", err or "value", valid))
            return nil
        end
        createCount[guid] = used + 1
        msg(player, "[ActiveChat] created " .. summaryLine(c):gsub("^%[ActiveChat%] ", ""))
        return c
    end

    -- Parse `.ac create` arg form: k=v tokens with optional quoted values (name="Old
    -- Borin"). `mood` is an alias for personality. Returns an opts table (validation
    -- happens in createCharacter; unknown keys are ignored). Quoting only matters for
    -- name (the rest are single words). Simple split honoring double-quotes.
    local function parseCreateArgs(rest)
        local opts = {}
        -- Tokenize honoring "double quotes" so name="Old Borin" stays one value.
        for k, v in string.gmatch(rest, '(%w+)%s*=%s*"([^"]*)"') do
            opts[k] = v
        end
        -- Then unquoted k=v (won't re-match the quoted ones: their '=' is consumed, but
        -- to be safe only set keys not already taken).
        for k, v in string.gmatch(rest, '(%w+)%s*=%s*([^%s"]+)') do
            if (opts[k] == nil) then opts[k] = v end
        end
        -- `mood` is the user-facing alias for `personality`.
        if (opts.mood) then opts.personality = opts.personality or opts.mood; opts.mood = nil end
        -- Only carry through the keys createCharacter understands.
        return {
            faction     = opts.faction,
            role        = opts.role,
            personality = opts.personality,
            area        = opts.area,
            gender      = opts.gender,
            name        = opts.name,
        }
    end

    -- Gossip create wizard ---------------------------------------------------
    -- Stepwise menu over the live trait vocabularies (roleKeys/moodKeys/AREAS), so new
    -- vocab appears automatically. Partial selection in pcreate[guid]. intid encodes
    -- (step*1000 + index); a sentinel range drives confirm/reroll/cancel actions.
    local STEP_FACTION, STEP_ROLE, STEP_MOOD, STEP_GENDER, STEP_AREA, STEP_CONFIRM = 1, 2, 3, 4, 5, 6
    local ACT_SPAWN, ACT_REROLL, ACT_CANCEL = 9001, 9002, 9003
    local factionChoices = { "alliance", "horde" }
    local genderChoices  = { "male", "female", "neutral" }

    -- Roll a preview name for the current partial selection (gender-correct). Stored on
    -- the scratch so the confirm step + reroll show the actual name that will be used.
    local function rollPreviewName(st)
        local nm = generateName(st.faction or "alliance", st.role or roleKeys[1],
            st.personality or moodKeys[1], st.gender or "neutral")
        return nm
    end

    -- Render the menu for `step` to the player. Each option's intid is step*1000+index.
    local function sendStep(player, step)
        player:GossipClearMenu()
        if (step == STEP_FACTION) then
            for i, f in ipairs(factionChoices) do player:GossipMenuAddItem(0, "Faction: " .. f, 0, STEP_FACTION * 1000 + i) end
        elseif (step == STEP_ROLE) then
            for i, r in ipairs(roleKeys) do player:GossipMenuAddItem(0, "Role: " .. r, 0, STEP_ROLE * 1000 + i) end
        elseif (step == STEP_MOOD) then
            for i, m in ipairs(moodKeys) do player:GossipMenuAddItem(0, "Personality: " .. m, 0, STEP_MOOD * 1000 + i) end
        elseif (step == STEP_GENDER) then
            for i, g in ipairs(genderChoices) do player:GossipMenuAddItem(0, "Gender: " .. g, 0, STEP_GENDER * 1000 + i) end
        elseif (step == STEP_AREA) then
            for i, a in ipairs(AREAS) do player:GossipMenuAddItem(0, "Area: " .. a, 0, STEP_AREA * 1000 + i) end
        elseif (step == STEP_CONFIRM) then
            local st = pcreate[player:GetGUIDLow()] or {}
            player:GossipMenuAddItem(0, string.format("Name: %s (click to re-roll)", st.name or "?"), 0, ACT_REROLL)
            player:GossipMenuAddItem(0, string.format("Confirm: %s %s/%s/%s in %s",
                st.faction, st.role, st.personality, st.gender, st.area), 0, ACT_SPAWN)
            player:GossipMenuAddItem(0, "Cancel", 0, ACT_CANCEL)
        end
        player:GossipSendMenu(1, player, PCREATE_MENU)   -- npc_text 1; player is the gossip source
    end

    local function startWizard(player)
        if (playerCreateGmOnly) and (not isGm(player)) then
            msg(player, "[ActiveChat] .ac create is restricted to GMs on this server.")
            return
        end
        pcreate[player:GetGUIDLow()] = {}
        sendStep(player, STEP_FACTION)
    end

    -- Gossip select handler for the wizard menu. Advances the scratch one step per
    -- click; the confirm step spawns / re-rolls the name / cancels.
    local function onGossipSelect(event, player, object, sender, intid, code, menu_id)
        if (menu_id ~= PCREATE_MENU) then return end
        local guid = player:GetGUIDLow()
        local st = pcreate[guid]
        if (not st) then player:GossipComplete(); return false end

        if (intid == ACT_CANCEL) then
            pcreate[guid] = nil
            player:GossipComplete()
            msg(player, "[ActiveChat] create cancelled.")
            return false
        elseif (intid == ACT_REROLL) then
            st.name = rollPreviewName(st)
            sendStep(player, STEP_CONFIRM)
            return false
        elseif (intid == ACT_SPAWN) then
            pcreate[guid] = nil
            player:GossipComplete()
            doCreate(player, { faction = st.faction, role = st.role,
                personality = st.personality, gender = st.gender, area = st.area, name = st.name })
            return false
        end

        local step  = math.floor(intid / 1000)
        local index = intid % 1000
        if (step == STEP_FACTION) then
            st.faction = factionChoices[index]; sendStep(player, STEP_ROLE)
        elseif (step == STEP_ROLE) then
            st.role = roleKeys[index]; sendStep(player, STEP_MOOD)
        elseif (step == STEP_MOOD) then
            st.personality = moodKeys[index]; sendStep(player, STEP_GENDER)
        elseif (step == STEP_GENDER) then
            st.gender = genderChoices[index]; sendStep(player, STEP_AREA)
        elseif (step == STEP_AREA) then
            st.area = AREAS[index]
            st.name = rollPreviewName(st)        -- roll a name to show on confirm
            sendStep(player, STEP_CONFIRM)
        else
            player:GossipComplete()
        end
        return false
    end
    RegisterPlayerGossipEvent(PCREATE_MENU, 2, onGossipSelect)  -- 2 = GOSSIP_EVENT_ON_SELECT

    -- Command hook -----------------------------------------------------------
    -- PLAYER_EVENT_ON_COMMAND (42): fires on any `.`-prefixed input. We claim only a
    -- leading "ac" token, dispatch the subcommand, and return false to swallow it (so
    -- the core doesn't report "unknown command"). Anything else returns nothing and
    -- passes through untouched. player is nil from the server console -> ignore.
    local function onCommand(event, player, command)
        if (not player) then return end
        -- Match "ac" or "ac <rest>" (case-insensitive head). Leave other commands alone.
        local head, rest = string.match(command, "^(%S+)%s*(.*)$")
        if (not head) or (string.lower(head) ~= "ac") then return end

        local sub, args = string.match(rest, "^(%S*)%s*(.*)$")
        sub = string.lower(sub or "")

        if (sub == "" ) or (sub == "help") then
            helpText(player)
        elseif (sub == "who") then
            cmdWho(player, args ~= "" and args or nil)
        elseif (sub == "list") then
            cmdList(player, (args ~= "" and string.lower(args)) or nil)
        elseif (sub == "create") then
            if (args == "") then
                startWizard(player)
            else
                doCreate(player, parseCreateArgs(args))
            end
        else
            msg(player, string.format("[ActiveChat] unknown subcommand '%s'.", sub))
            helpText(player)
        end
        return false   -- handled: swallow so the core doesn't flag an unknown command
    end
    RegisterPlayerEvent(42, onCommand)   -- 42 = PLAYER_EVENT_ON_COMMAND

    -- Logout cleanup: drop per-player scratch + create-count so memory doesn't grow and
    -- a relog resets the per-session create allowance.
    RegisterPlayerEvent(4, function(event, player)   -- 4 = PLAYER_EVENT_ON_LOGOUT
        if (not player) then return end
        local guid = player:GetGUIDLow()
        pcreate[guid]     = nil
        createCount[guid] = nil
    end)

end

--[[
-- Optional: echo nearby /whispers and declined invites into world chat.
-- Left disabled (as in the original). Uncomment to enable.
RegisterServerEvent(5, function(_, p, w)
    local c = p:GetOpcode()
    if (c == 0x095) then
        local typ = p:ReadULong()
        local lng = p:ReadULong()
        local n   = p:ReadString()
        local m   = p:ReadString()
        if (typ == 7 and n ~= w:GetName()) then
            SendWorldMessage(string.format("|cFFFF80FF|Hplayer:%s|h[%s]|h whispered quietly:%s|r", n, n, m))
        end
    end
    if (c == 0x06E) then
        local n = p:ReadString()
        SendWorldMessage(string.format("%s declined your invitation.", n))
    end
    if (c == 0x069) then
        local n = p:ReadString()
        SendWorldMessage(string.format("%s declined your invitation.", n))
    end
end)
]]--

end
