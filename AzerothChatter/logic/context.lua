--[[
  Context awareness -- the "what's true in the world right now" subsystem: a slow,
  TTL-cached snapshot of time-of-day, active/near holidays, and season, plus the
  token resolvers that read it. Split out of logic/chatter.lua so the engine file is about
  selection/conversation logic; this file owns everything clock/calendar/event.

  Loaded via require("logic.context"). Returns:
    M.ctx                      -- the live cache table (mutated in place by refreshCtx;
                                  a captured reference stays valid)
    M.refreshCtx()             -- TTL-guarded refresh, called each emission
    M.resolveEvent/NextEvent/LastEvent/Season/TimeOfDay  -- %token% resolvers
    M.setEventBurstHook(fn)    -- engine registers fireEventBurst here (see logic/chatter.lua)

  Every dimension is flag- and API-guarded: a disabled flag or a missing ALE API
  leaves that field neutral and the resolver falls back to a random pool value --
  no silent characters, no errors. Preserve that fallback invariant.
]]--

local config = require("AzerothChatter")
local pools  = require("data.tokens")

-- Context vocabulary/maps from data/context.lua (eventIdToName, monthToSeason,
-- eventNeutral). Guarded so a missing/broken file falls back to inline defaults.
local ctxMap = {}
do
    local ok, m = pcall(require, "data.context")
    if (ok and type(m) == "table") then ctxMap = m end
end

local enableContextAware  = config.enableContextAware
local enableTimeContext   = config.enableTimeContext
local enableEventContext  = config.enableEventContext
local enableSeasonContext = config.enableSeasonContext
local contextRefreshMs    = config.contextRefreshMs
local enableEventBurst    = config.enableEventBurst

local M = {}

-- Single cache of "what's true right now", refreshed on a slow TTL (never recomputed
-- per candidate line). Fields default to neutral values. Mutated in place -- the
-- engine captures this table once and reads fields live.
local ctx = {
    hour      = 0,          -- server hour 0..23 (from GetGameTime; see refreshCtx note)
    timeKey   = "night",    -- bucketed: "dawn"|"morning"|"midday"|"afternoon"|"dusk"|"night"
    season    = "spring",   -- derived from the month
    active    = {},         -- set-like ACTIVE event names
    nextEvent = nil,        -- { name=..., daysAway=N } soonest upcoming
    lastEvent = nil,        -- { name=..., daysAgo=N }  most recently ended
    refreshed = 0,          -- ms tick of last refresh
}
M.ctx = ctx

-- Event-burst hook + state (dead unless enableEventBurst). The engine registers its
-- fireEventBurst via setEventBurstHook; refreshCtx calls it when an event flips
-- active. ctxActivePrev = last refresh's active set, diffed against the fresh set to
-- fire once per activation; ctxActiveSeeded guards the first refresh (snapshot only,
-- no startup burst flood).
local eventBurstHook  = nil
local ctxActivePrev   = {}
local ctxActiveSeeded = false
function M.setEventBurstHook(fn) eventBurstHook = fn end

-- Coarse, fiction-friendly hour buckets; tune freely. The bucket is the
-- tag/selection vocabulary; the display pool below is the wording vocabulary.
local function bucketHour(h)
    if h < 5  then return "night"     end
    if h < 8  then return "dawn"      end
    if h < 11 then return "morning"   end
    if h < 14 then return "midday"    end
    if h < 18 then return "afternoon" end
    if h < 21 then return "dusk"      end
    return "night"
end

-- month (1..12) -> season name, from ctxMap.monthToSeason with a northern-hemisphere
-- inline fallback. Nil-safe: a bad/out-of-range month returns nil (ctx.season stays neutral).
local monthToSeasonMap = (type(ctxMap.monthToSeason) == "table")
    and ctxMap.monthToSeason
    or {
        [1]="winter", [2]="winter", [3]="spring", [4]="spring", [5]="spring",
        [6]="summer", [7]="summer", [8]="summer", [9]="autumn", [10]="autumn",
        [11]="autumn", [12]="winter",
    }
local function monthToSeason(month)
    if (type(month) ~= "number") then return nil end
    return monthToSeasonMap[month]
end

-- Holiday -> season cross-check: an active seasonal holiday overrides the month-
-- derived season so calendar and holiday never disagree (Winter Veil => winter).
-- Keys are EXACT eventIdToName display names; season-neutral holidays are omitted.
local holidayToSeason = {
    ["Winter Veil"]                 = "winter",
    ["the Midsummer Fire Festival"] = "summer",
    ["the Harvest Festival"]        = "autumn",
    ["Pilgrim's Bounty"]            = "autumn",
    ["Noblegarden"]                 = "spring",
    ["the Lunar Festival"]          = "spring",
}

-- timeKey -> display-string pool for %timeofday%, agreeing with the clock.
-- IMPORTANT: bare nouns, NO leading article -- lines supply their own ("this
-- %timeofday%", "at %timeofday%"). "the evening" would render "this the evening".
local timeKeyDisplay = {
    night     = { "midnight", "nightfall", "night" },
    dawn      = { "dawn", "first light" },
    morning   = { "morning", "first light" },
    midday    = { "midday" },
    afternoon = { "afternoon", "midday" },
    dusk      = { "dusk", "twilight", "evening" },
}

-- ms tick source for the refresh TTL. Prefer GetGameTime() (seconds on ALE),
-- fall back to os.time(). Capability-guarded -- always returns a sane value.
local function nowMs()
    if (type(GetGameTime) == "function") then
        local ok, secs = pcall(GetGameTime)
        if (ok and type(secs) == "number") then return secs * 1000 end
    end
    return os.time() * 1000
end

-- Set { [displayName]=true } of currently-active events, via GetActiveGameEvents()
-- mapped through ctxMap.eventIdToName (unmapped IDs skipped). Returns {} if the API
-- is absent (engine then never excludes on events and %event% goes random).
local function activeEventNameSet()
    local set = {}
    if (type(GetActiveGameEvents) ~= "function") then return set end
    local ok, ids = pcall(GetActiveGameEvents)
    if (not ok) or (type(ids) ~= "table") then return set end
    local map = ctxMap.eventIdToName or {}
    for _, id in pairs(ids) do
        local name = map[id]
        if (name) then set[name] = true end
    end
    return set
end

-- Nearest-event scheduling. Read the game_event schedule once at startup, then
-- compute soonest-upcoming / most-recently-ended per refresh as cheap arithmetic
-- over the snapshot. game_event cols (AC 3.3.5): start_time (sec, via
-- UNIX_TIMESTAMP), length (min), occurence (min between repeats; 0 = one-shot).
-- Only IDs mapping to a display name are kept.

local DAY_SECONDS = 86400

-- Days past which an event is no longer surfaced as "near" -- beyond this the slot
-- stays nil and %event% uses the neutral pool rather than naming a far-off holiday.
local NEAREST_HORIZON_DAYS = 30

-- Schedule snapshot: array of { id, name, startSec, lengthSec, occurSec }. Empty
-- when WorldDBQuery is absent/fails -> nearestEvents() returns nil/nil.
local eventSchedule = {}

-- One-shot startup read of the game_event schedule. Guarded on WorldDBQuery and
-- wrapped in pcall so an absent API or odd result shape leaves the snapshot empty
-- rather than erroring. ALEQuery API: GetRowCount/GetUInt32/NextRow, 0-indexed cols.
local function readEventSchedule()
    if (type(WorldDBQuery) ~= "function") then return {} end
    local map = ctxMap.eventIdToName or {}
    local out = {}
    local ok = pcall(function()
        local q = WorldDBQuery(
            "SELECT eventEntry, UNIX_TIMESTAMP(start_time), length, occurence FROM game_event")
        if (not q) then return end
        -- GetRowCount() bounds the loop so an empty/odd result can't spin; we
        -- still guard NextRow() for engines that only support row-walking.
        local rows = (type(q.GetRowCount) == "function") and q:GetRowCount() or nil
        local n = 0
        repeat
            local id        = q:GetUInt32(0)
            local name      = map[id]
            if (name) then
                local startSec  = q:GetUInt32(1)        -- UNIX_TIMESTAMP -> seconds
                local lengthMin = q:GetUInt32(2)        -- minutes
                local occurMin  = q:GetUInt32(3)        -- minutes (0 = non-recurring)
                out[#out + 1] = {
                    id        = id,
                    name      = name,
                    startSec  = startSec,
                    lengthSec = (lengthMin or 0) * 60,
                    occurSec  = (occurMin or 0) * 60,
                }
            end
            n = n + 1
            if (rows ~= nil) and (n >= rows) then break end
        until (type(q.NextRow) ~= "function") or (not q:NextRow())
    end)
    if (not ok) then return {} end
    return out
end

eventSchedule = readEventSchedule()

-- nearestEvents(now_sec) -> nextEvent, lastEvent (each {name=, daysAway/daysAgo=}
-- or nil). Projects each holiday's recurrence cycle around `now` (recurring events
-- repeat every occurSec, which handles the year-wrap; occurence > length so windows
-- never overlap), keeps the soonest future start and most recent past end, both
-- capped to NEAREST_HORIZON_DAYS (else nil -> neutral).
local function nearestEvents(now)
    if (type(now) ~= "number") or (#eventSchedule == 0) then return nil, nil end
    local horizonSec = NEAREST_HORIZON_DAYS * DAY_SECONDS

    local nextName, nextStart                     -- soonest future start
    local lastName, lastEnd                        -- most recent past end

    for _, ev in ipairs(eventSchedule) do
        local nextS, prevS                         -- this event's bracketing starts
        if (ev.occurSec and ev.occurSec > 0) then
            -- Recurring: locate the cycle around `now`. k = how many whole cycles
            -- have elapsed since the very first start (clamped at >= 0).
            local elapsed = now - ev.startSec
            local k = math.floor(elapsed / ev.occurSec)
            if (k < 0) then k = 0 end
            prevS = ev.startSec + k * ev.occurSec      -- start of the current/just-past cycle
            nextS = prevS + ev.occurSec                -- start of the next cycle (WRAP case)
            -- If we're still BEFORE this event's first ever start, prevS would be
            -- in the future; in that case there is no past occurrence yet.
            if (prevS > now) then nextS = prevS; prevS = nil end
        else
            -- Non-recurring single window.
            if (ev.startSec >= now) then nextS = ev.startSec else prevS = ev.startSec end
        end

        -- Upcoming start candidate.
        if (nextS) and (nextS >= now) then
            if (not nextStart) or (nextS < nextStart) then
                nextStart = nextS; nextName = ev.name
            end
        end

        -- Most-recent past END candidate (start of the past cycle + its length).
        if (prevS) and (prevS <= now) then
            local endS = prevS + (ev.lengthSec or 0)
            if (endS <= now) then
                if (not lastEnd) or (endS > lastEnd) then
                    lastEnd = endS; lastName = ev.name
                end
            end
        end
    end

    local nextEvent, lastEvent
    if (nextName) then
        local away = nextStart - now
        if (away <= horizonSec) then                   -- horizon cap: don't surface far-off events
            nextEvent = { name = nextName, daysAway = math.floor(away / DAY_SECONDS) }
        end
    end
    if (lastName) then
        local ago = now - lastEnd
        if (ago <= horizonSec) then
            lastEvent = { name = lastName, daysAgo = math.floor(ago / DAY_SECONDS) }
        end
    end
    return nextEvent, lastEvent
end

-- TTL-guarded refresh of ctx (time, events, season). Each dimension is flag- and
-- API-guarded; a missing clock/API leaves that field neutral and falls back to random.
local function refreshCtx()
    local now = nowMs()
    if (now - ctx.refreshed < contextRefreshMs) then return end   -- common path: cheap early-exit
    ctx.refreshed = now

    if (not enableContextAware) then return end

    -- Time + season share ONE os.date decomposition of the GetGameTime() timestamp.
    -- NOTE: on AzerothCore GetGameTime() is the server's real wall-clock Unix time, so
    -- this decomposition is the HOST's local date/hour (its OS timezone) -- not an
    -- accelerated in-game day. "Night lines at night" => the server machine's night.
    -- API-guarded so an absent clock leaves both neutral. dt.hour drives time;
    -- dt.month drives season.
    local dt
    if ((enableTimeContext or enableSeasonContext)
        and type(GetGameTime) == "function" and type(os.date) == "function") then
        local ok, decomposed = pcall(function() return os.date("*t", GetGameTime()) end)
        if (ok and type(decomposed) == "table") then dt = decomposed end
    end

    -- Time: derive the hour -> timeKey bucket.
    if (enableTimeContext and dt and type(dt.hour) == "number") then
        ctx.hour    = dt.hour
        ctx.timeKey = bucketHour(ctx.hour)
        -- else: leave ctx.timeKey at its prior/neutral value; %timeofday% falls back.
    end

    -- Active events: set { ["Hallow's End"]=true, ... }, empty when the API is
    -- absent. Populated BEFORE the season block so its holiday cross-check sees it.
    if (enableEventContext) then
        ctx.active = activeEventNameSet()

        -- Burst: diff the fresh active set against the previous snapshot to fire a
        -- one-shot festival burst for each newly-active event (once per activation,
        -- since a still-active event sits in both sets). First refresh only seeds
        -- the snapshot (ctxActiveSeeded) so startup holidays don't all burst at once.
        if (enableEventBurst and eventBurstHook) then
            if (ctxActiveSeeded) then
                for name, _ in pairs(ctx.active) do
                    if (not ctxActivePrev[name]) then       -- newly active this refresh
                        eventBurstHook(name)
                    end
                end
            end
            ctxActiveSeeded = true
            local snap = {}
            for name, _ in pairs(ctx.active) do snap[name] = true end
            ctxActivePrev = snap                            -- store AFTER diffing
        end

        -- Nearest events over the cached schedule. nil-safe (absent schedule ->
        -- neutral pool). Uses raw game-time seconds when available, else os.time.
        local nowSec
        if (type(GetGameTime) == "function") then
            local ok, secs = pcall(GetGameTime)
            if (ok and type(secs) == "number") then nowSec = secs end
        end
        if (not nowSec) and (type(os.time) == "function") then nowSec = os.time() end
        ctx.nextEvent, ctx.lastEvent = nearestEvents(nowSec)
    end

    -- Season: derive from the month, then let any active seasonal holiday override it
    -- (Winter Veil active => winter even in a summer month). Absent clock or unmapped
    -- month leaves ctx.season neutral (%season% goes random).
    if (enableSeasonContext and dt and type(dt.month) == "number") then
        local season = monthToSeason(dt.month)
        if (season) then ctx.season = season end
        if (ctx.active) then
            for name, _ in pairs(ctx.active) do
                local s = holidayToSeason[name]
                if (s) then ctx.season = s break end
            end
        end
    end
end
M.refreshCtx = refreshCtx

-- Resolve %timeofday% from context (flags on + a pool for ctx.timeKey), else random.
local function resolveTimeOfDay(c)
    if (enableContextAware and enableTimeContext and c and c.timeKey) then
        local pool = timeKeyDisplay[c.timeKey]
        if (pool and #pool > 0) then return pool[math.random(#pool)] end
    end
    return pools.selectRandomTimeOfDay()                    -- fallback: random behaviour
end
M.resolveTimeOfDay = resolveTimeOfDay

-- Resolve %season% from context (flags on + ctx.season set), else random. ctx.season
-- is already a fiction word ("spring"|...) so it substitutes directly.
local function resolveSeason(c)
    if (enableContextAware and enableSeasonContext and c and c.season) then
        return c.season
    end
    return pools.selectRandomSeason()                       -- fallback: random behaviour
end
M.resolveSeason = resolveSeason

-- Festival-agnostic phrases used when no real holiday is active/near, so a character
-- never names a specific holiday out of context. From data/context.lua + inline fallback.
local eventNeutralPool = (type(ctxMap.eventNeutral) == "table" and #ctxMap.eventNeutral > 0)
    and ctxMap.eventNeutral
    or { "the next festival", "the holidays", "the coming festivities" }
local function selectNeutralEvent()
    return eventNeutralPool[math.random(#eventNeutralPool)]
end

-- Resolve %event% to the most relevant real event, in priority order:
--   1. the line's `events` tag (tag WINS so token & eligibility agree; prefer an
--      active tagged event, else the first tagged name).
--   2. else something live now (c.active).
--   3. else the nearest event in time: c.nextEvent then c.lastEvent.
--   4. else a neutral phrase -- NEVER a random specific holiday.
local function resolveEvent(item, c)
    if (enableContextAware and enableEventContext) then
        -- 1. tagged line: the tag's event wins (prefer an active one).
        if (item) and (not item.eventsGlobal) and (item.events) and (#item.events > 0) then
            if (c and c.active) then
                for _, name in ipairs(item.events) do
                    if (c.active[name]) then return name end
                end
            end
            return item.events[1]
        end
        -- 2. else something live right now.
        if (c and c.active) then
            for name in pairs(c.active) do return name end
        end
        -- 3. else the nearest event in time (upcoming preferred, then just-past).
        if (c) then
            if (c.nextEvent and c.nextEvent.name) then return c.nextEvent.name end
            if (c.lastEvent and c.lastEvent.name) then return c.lastEvent.name end
        end
    end
    -- 4. neutral phrase -- never a random specific holiday.
    return selectNeutralEvent()
end
M.resolveEvent = resolveEvent

-- Resolve %nextevent% / %lastevent% to the soonest-upcoming / most-recently-ended
-- holiday; both fall back to the neutral pool when scheduling is unknown.
local function resolveNextEvent(c)
    if (enableContextAware and enableEventContext and c and c.nextEvent and c.nextEvent.name) then
        return c.nextEvent.name
    end
    return selectNeutralEvent()
end
M.resolveNextEvent = resolveNextEvent

local function resolveLastEvent(c)
    if (enableContextAware and enableEventContext and c and c.lastEvent and c.lastEvent.name) then
        return c.lastEvent.name
    end
    return selectNeutralEvent()
end
M.resolveLastEvent = resolveLastEvent

return M
