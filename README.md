# ALE Script: Lively World Chat

This script is for AzerothCore using Eluna Lua scripting. It fills **World chat**
with **ambient, in-world roleplay chatter** — the kind of talk you'd overhear in a
busy capital: citizens, vendors, guards, adventurers, and soldiers swapping gossip,
lore, jokes, and quiet observations about life in Azeroth. It's intended for
single-player and low-population servers, where it makes the world feel inhabited
without anyone else being online.

The chatter is voiced by a **roster of recurring in-world characters** — named,
personality-bearing residents who reappear over a play session with a consistent
identity, mood, and name color — rather than an endless stream of one-off random
names. (See "The character roster" below.)

The chatter is **deliberately not an imitation of real players.** There's no
gearscore spam, no auction-house adverts, no out-of-character meta. If you want
characters that behave like real players (LFG, trade, raid logistics), pair this
with a playerbot module instead — this script is for *flavor and atmosphere.*
Every line is written to stay inside the fiction: Azeroth is real to these voices.

> **Note on Guild chat.** Earlier versions also emitted Guild chat. Guild chat has
> been **removed entirely** — a guild is a player-organization construct that
> doesn't fit the civilian/guard/NPC scope. This module is now **World-chat only.**

Note: I am not the original author. I just modified and expanded it. The content
was reworked away from player-imitation/meme humor toward lore-grounded RP.

If you expand the text, please make a pull request so we can all share in the fun —
and keep new lines in-character (no real-world references, no fourth-wall jokes).

## Installation
- This script requires mod-ale for your server.
- Download the zip and extract the folder into your server's `lua_scripts` folder.

## Features

- **Ambient World chat** — a steady stream of in-world chatter so the cities feel
  alive.
- **A recurring character roster** — chatter is voiced by named, personality-bearing
  residents who reappear with a stable identity and name color, not by a fresh
  random name every line.
- **Faction-aware** — lines can be broadcast to everyone (`shared`) or sent only to
  one faction (`alliance` / `horde`), each with its own city flavor
  (Stormwind/Ironforge/Darnassus/Exodar vs. Orgrimmar/Thunder Bluff/Silvermoon/Undercity).
- **Trait- and area-aware line selection** — each character prefers lines tagged for
  their role/personality/area but always falls back to generic lines, so no one ever
  goes silent.
- **Three conversation shapes** — standalone one-liners, two-person back-and-forth
  exchanges, and multi-voice group discussions.
- **Placeholder substitution** — ~44 `%token%` swaps pull in random, lore-appropriate
  values so the chatter never reads the same way twice.
- **Easy to extend** — content lives in plain Lua tables; add or edit lines without
  touching the engine.

---

## The character roster

Chatter is spoken by an **in-memory roster of characters**. Key properties:

- **Lazily generated.** The roster starts **empty** on every server start and grows
  on demand: each time a chat timer fires, the engine either reuses an existing
  character or spawns a fresh one (see "Lazy growth" below).
- **In-memory only.** Characters live entirely in Lua memory. They are **never
  persisted** — no DB rows, no creatures, no per-character save — and are **reset on
  every server restart**. A restart regrows a brand-new roster from scratch.
- **Recurring.** Within one session a character reappears across many lines with the
  same name, color, and personality, so the world feels populated by familiar voices.

### Character fields

Each generated character is a small Lua table:

| Field | Meaning |
|---|---|
| `name` | Display name (generated; see "Name generation") |
| `faction` | `"alliance"` or `"horde"` — intrinsic, never changes |
| `role` | Civic/occupation archetype, one of `ROLES` (e.g. `guard`, `vendor`) |
| `personality` | Mood descriptor, one of `PERSONALITIES` (e.g. `gruff`, `warm`) |
| `area` | Locale affinity, one of `AREAS` (e.g. `city`, `battlefield`) |
| `homeCity` | A capital **of the character's own faction** |
| `chattiness` | `0..1` — **selection weight**: how often this character is chosen to speak |
| `friendliness` | `0..1` — how likely they are to be pulled in as a **co-speaker** in a duo/group |
| `color` | Name color, **picked once at generation** and used for every line they speak |

#### chattiness vs friendliness

These are **distinct levers**:

- **`chattiness`** is the weight a character carries when a global chat timer resolves
  *who speaks*. Higher chattiness ⇒ chosen more often across timer ticks.
- **`friendliness`** sets how likely a character is to be drawn in as a *co-speaker*
  when someone else starts a duo or group conversation.

A gruff hermit can be chatty but unfriendly (talks a lot, rarely joins others); a shy
regular can be friendly but quiet (seldom starts, often joins).

#### Stable name color

A character's `color` is assigned **once**, at generation, from a small class-color
palette, and is used by every line that character ever speaks. There is no per-line
random color — a recurring voice keeps a stable visual identity in chat.

### Lazy growth & self-balancing

The roster grows toward `maxCharacters` and then holds steady, with no startup batch
generation:

- On each chat tick the engine runs a weighted roulette over **every existing
  same-faction character** (weight = their `chattiness`) **plus one virtual
  "spawn a new character" slot** (weight = `newCharacterWeight`).
- If the virtual slot wins **and** the roster is below `maxCharacters`, a fresh
  character is generated, registered, and speaks immediately. Otherwise an existing
  character is reused.
- **Cold start:** an empty roster has only the virtual slot, so the first tick always
  spawns.
- **Self-balancing:** when the roster is small its summed chattiness is low, so the
  virtual slot usually wins and the population grows; as it fills, existing weight
  dominates, spawning tapers, and growth **halts exactly at `maxCharacters`**. After
  that it's pure reuse. `newCharacterWeight` tunes how eagerly the world populates.

`maxCharactersPerFaction` (optional) adds a per-faction sub-cap on top of the global
`maxCharacters`.

### Name generation

Names are built from `ActiveChat/npc_name.lua`
(`{ alliance = <first names>, horde = <first names>, surnames = <list> }`) plus the
role prefixes and personality epithets in `ROLES` / `PERSONALITIES`. One of four
weighted patterns is chosen per character:

| Pattern | ~Weight | Example |
|---|---|---|
| `{first} {last}` | 55% | *Aldric Stormbringer* |
| `{Role} {first}` | 20% | *Innkeep Hellena*, *Sergeant Brom* |
| `{first}, {epithet}` | 15% | *Actal, the Brave* |
| `{first}` (bare) | 10% | *Maelara* |

Names are de-duplicated against the live roster (bounded retry). You can optionally
feed additional surnames from the world DB via the `ns` query string near the top of
`npcTalk.lua`.

---

## Roles, personalities, areas

These three identity vocabularies are each defined in **exactly one table** at the
top of the character-data block in `ActiveChat/npcTalk.lua`. To add or change a
role/personality/area, edit only that table — no engine changes needed.

- **`ROLES`** (civic/occupation archetypes). Each entry has name `prefixes`, a
  roster-frequency `weight`, and a default `area` affinity:
  `guard`, `citizen`, `vendor`, `innkeeper`, `adventurer`, `soldier`, `mage`,
  `priest`, `craftsman`, `farmer`, `sailor`, `noble`, `drunkard`, `urchin`.
- **`PERSONALITIES`** (mood descriptors). Each maps to a pool of name epithets and
  doubles as a line-selection tag:
  `warm`, `gruff`, `cheerful`, `weary`, `wry`, `boastful`, `nervous`, `solemn`,
  `greedy`, `kindly`, `bitter`, `dreamy`, `brave`, `cowardly`, `gossipy`.
- **`AREAS`** (locale affinities):
  `city`, `rural`, `battlefield`, `coast`, `wilderness`, `road`.

At generation a character's `area` is biased (~65%) toward its role's default area,
else picked at random — so the roster reads as roughly role-typed without being rigid.

---

## The `area` tag (global vs zone-specific)

`area` makes setting-specific chatter land where it fits. Both characters (affinity)
and lines (tags) carry area information, and line selection compares them:

- **Untagged line ⇒ global wildcard.** A line with no `areas` tag fits **any** area
  and any character. This is the universal fallback pool.
- **`areas` as a list ⇒ uniform fit.** `areas={"city","rural"}` means the line is
  equally at home in those areas (and excluded elsewhere).
- **`areas` as a map ⇒ graded fit.** `areas={battlefield=3, rural=1}` means the line
  is three times as likely on a battlefield as in the countryside.
- **Hard-exclude.** With a tagged line, an area **not listed** is hard-excluded: a
  city character will *never* draw a battlefield-only line. Area is the **only**
  factor that can hard-exclude — role/mood mismatches merely lower the odds, so a
  character always has eligible fallback lines and never goes silent.

### Future hook: zone-specific chatter

In v1, a character's `area` is a **static affinity** assigned once at generation. The
code carries a **documented seam** (a clearly-commented `FUTURE HOOK` at the `area`
assignment in `generateCharacter`) for a later version to derive a character's
*effective* area from a **real player's current zone**, enabling true zone-specific
chatter (e.g. battlefield lines while players are in a contested zone) without
changing the selection engine.

---

## Authoring content

World chatter lives in `ActiveChat/talk_text/npc_text.lua`. It returns three pools:

```lua
return {
  shared   = { lines = {...}, duos = {...}, groups = {...} },  -- seen by everyone
  alliance = { lines = {...}, duos = {...}, groups = {...} },  -- Alliance only
  horde    = { lines = {...}, duos = {...}, groups = {...} },  -- Horde only
}
```

Each pool has three lists:

- **`lines`** — standalone one-liners, spoken by a single character.
- **`duos`** — two-person back-and-forth; two fixed speakers alternate A / B / A / B.
- **`groups`** — group discussions; a rotating cast of 4–6 voices, one line each, no
  voice speaking twice in a row.

See the header comment block at the top of `talk_text/npc_text.lua` for the canonical
authoring reference.

### Tagged authoring format (string-first)

A **`lines`** entry is **either** a bare string (untagged = a global wildcard) **or** a
table whose `[1]` is the text and whose named keys are metadata:

```lua
-- bare string: untagged, fits any character in any area (the universal fallback)
"The lamplighters are making their rounds.",

-- tagged one-liner with a LIST of areas (uniform fit)
{ "Three coppers a loaf and not a copper less.",
  roles={"vendor"}, moods={"gruff","greedy"}, areas={"city"} },

-- tagged one-liner with a GRADED map of areas (never fires in city)
{ "Orcs in the treeline -- to arms!", roles={"soldier","guard"},
  moods={"nervous","brave"}, areas={battlefield=3, rural=1} },
```

A **`duos`** / **`groups`** entry is a table with **`chain={...}`** (the ordered lines)
plus the same optional tags:

```lua
-- a tagged duo: two guards on a quiet wall
{ chain={"Quiet on the wall tonight.", "Too quiet. I don't like it."},
  roles={"guard","soldier"}, moods={"solemn"}, areas={"city","battlefield"} },
```

(Legacy bare `{"a","b"}` arrays still parse as untagged chains, but new content
should use the `chain=` form.)

#### Tag fields (all optional)

| Field | Meaning |
|---|---|
| `roles` | List of role archetypes the line suits. **Omit = any role.** |
| `moods` | List of personalities the line suits. **Omit = any personality.** |
| `areas` | Area fit: **omit** = global; **list** = uniform; **map** = graded (unlisted areas hard-excluded). |
| `times` | Time-of-day fit: **omit** = any time; **list** = uniform; **map** = graded (unlisted buckets hard-excluded). See "Context-aware chatter". |
| `events` | Event fit (binary): **omit** = fires regardless; **list** of event names = fires only while one is active (or, with `eventWindow`, in its run-up/wind-down). See "Context-aware chatter". |
| `eventWindow` | Pairs with `events`: `"active"` (default) / `"approach"` / `"after"`. See "Context-aware chatter". |
| `seasons` | Season fit: same list/map/hard-exclude semantics as `times`. See "Context-aware chatter". |
| `notTimes` / `notSeasons` / `notEvents` | **Negative gate** — fires in any context **except** the ones listed (e.g. `notTimes={"night"}`). Works even on an otherwise-global line. See "Context-aware chatter". |
| `weight` | Relative pick frequency (default `1`). Bump good generic lines up. |
| `cooldown` | Min ticks before this exact line repeats (default `lineCooldownTicks`). Raise for distinctive lines. |

> **Leave genuinely generic ambience untagged and global on purpose.** That untagged
> pool is the fallback the matcher needs so no character ever goes silent. Tag a line
> only when its content clearly implies a role/mood/area.

### How a line is chosen

For the speaking character, every candidate line is scored:

```
score = weight
      * roleFactor   (boost if char.role ∈ line.roles; 1.0 if untagged; a low floor on mismatch)
      * moodFactor   (boost if char.personality ∈ line.moods; 1.0 if untagged; low floor on mismatch)
      * areaFactor   (1.0 if untagged/global; per-area weight if char.area is listed; 0 = EXCLUDE otherwise)
      * timeFactor   (1.0 if untagged; per-bucket weight if ctx.timeKey is listed; 0 = EXCLUDE otherwise)
      * eventFactor  (1.0 if untagged; 1.0 when a tagged event applies — see eventWindow; 0 = EXCLUDE otherwise)
      * seasonFactor (1.0 if untagged; per-season weight if ctx.season is listed; 0 = EXCLUDE otherwise)
      * excludeFactor (1.0 normally; 0 = EXCLUDE when the CURRENT time/season/active-event is in the line's notTimes/notSeasons/notEvents)
      * recencyPenalty (0 within the line's cooldown, ramping back to 1)
```

The next line is a weighted-random pick over score > 0. Role/mood mismatches only
*lower* the odds (never zero); out-of-area, out-of-time, out-of-event, and
out-of-season tagged lines are hard-excluded.

`timeFactor` and `seasonFactor` mirror `areaFactor` exactly: an **untagged** line is
always `1.0` (global), a **graded match** is boosted by `timeMatchStrength` /
`seasonMatchStrength` (default `3.0`, like `areaMatchStrength`), and a line that *is*
tagged but doesn't match the current bucket/season is excluded. `eventFactor` is
**binary** — an event-tagged line is fundamentally *about* that event, so it either
applies (`1.0`) or is excluded (`0`), with no graded boost and no low floor. The
**fallback invariant** holds throughout: because untagged lines stay `1.0` on every
factor, a character always has eligible candidates even when every tagged line is out
of context — and if the in-game clock/event/season can't be read at all, the
corresponding factor stays `1.0` (no exclusion) rather than going silent. See
"Context-aware chatter" for how `ctx` (the live time/event/season) is sourced.

---

## Context-aware chatter

By default the chatter doesn't just read like Azeroth — it reads like Azeroth *right
now*. Night lines fire at night, festival lines fire during the actual festival, and
season/weather talk tracks the real game state instead of a coin flip. This is a
**selection-and-substitution refinement**, not a new subsystem: it reuses the line
scorer (three new factors alongside `areaFactor`) and the placeholder substitution
pass (the time/event/season tokens now resolve to *what's true*). Everything stays
inside the fiction — **no real-world clocks, no "server time" meta** — and degrades
gracefully: if a context source is unavailable, that dimension reverts to today's
random behaviour and nobody goes silent.

It's all behind the flags in "Context-aware chatter flags" above. Turn the master
flag (or any sub-flag) off and you get exactly the old random behaviour.

### The three new line tags

Authoring gains three optional tags, with the **same** list/map/hard-exclude
semantics the `area` tag already uses (see "Tagged authoring format"). Leave generic
ambience untagged — that global pool is the fallback the matcher needs.

| Field | Meaning |
|---|---|
| `times` | Time-of-day fit. **Omit** = any time. **List** (`{"night","dusk"}`) = uniform fit; unlisted buckets are hard-excluded. **Map** (`{night=3, dusk=1}`) = graded. Buckets: `dawn` / `morning` / `midday` / `afternoon` / `dusk` / `night` (hour-of-day from the in-game clock). |
| `events` | Event fit (**binary** — no graded form). **Omit** = fires regardless of events. A **list** of event display-names = fires **only while one of those events is active** (or, with `eventWindow`, in its approach/after window); otherwise hard-excluded. |
| `eventWindow` | Pairs with `events`. `"active"` (default) = only while live. `"approach"` = also fire in the **N-day run-up** (`eventApproachDays`, default `5`), keyed off `%nextevent%`. `"after"` = also fire in the **N-day wind-down** (`eventAfterDays`, default `3`), keyed off `%lastevent%`. |
| `seasons` | Season fit. Same list/map/hard-exclude semantics as `times`. Seasons: `winter` / `spring` / `summer` / `autumn`. |
| `notTimes` / `notSeasons` / `notEvents` | **Negative gate.** The mirror of the tags above: a line fires in **any** context **except** the ones listed. Unlike the positive tags this applies even to an otherwise-global line, so you can keep a line universal and carve out the single context it must never fire in. `notTimes={"night"}` = never at night; `notSeasons={"summer"}` = never in summer; `notEvents={"Brewfest"}` = never while Brewfest is live. |

```lua
-- night-only ambience (stays silent until evening, fires uniformly at dusk/night)
{ "The lamplighters are done; only the watch is awake now.",
  roles={"guard"}, times={"night","dusk"} },

-- fires ONLY while Hallow's End is the live game event; graded toward late hours
{ "Mind the Headless Horseman if you're out past dark for %event%.",
  events={"Hallow's End"}, times={night=3, dusk=2} },

-- anticipation: fires in the run-up to Winter Veil (not during it)
{ "Only a few days until %nextevent% -- have you hung the holly yet?",
  events={"Winter Veil"}, eventWindow="approach" },

-- aftermath: fires just after Brewfest ends
{ "Quiet now that %lastevent% is over. The kegs are all dry.",
  events={"Brewfest"}, eventWindow="after" },

-- graded by time, no hard exclude elsewhere
{ "%city% smells of bread already.", times={dawn=3, morning=2} },

-- harvest flavor, autumn only
{ "Good harvest this year -- the granaries are near full.",
  seasons={"autumn"}, roles={"farmer"} },

-- universal line, but the joke needs daylight: never fires at night or dusk
{ "The tavern's rowdy this %timeofday% -- two duels already, and it's not even dark.",
  notTimes={"night","dusk"} },
```

Event display-names must match the names in `context_map.lua` exactly (e.g.
`"the Harvest Festival"`, `"the Midsummer Fire Festival"` — articles included).

### The context tokens

`%timeofday%`, `%season%`, `%event%`, `%nextevent%`, and `%lastevent%` resolve to the
**current** state rather than a random pick:

- **`%timeofday%`** → a display phrase for the current in-game time bucket.
- **`%season%`** → the current in-game season.
- **`%event%`** → the most relevant *real* event, in priority order: (1) the line's
  own `events` tag if present (so token and tag always agree), else (2) something
  active now, else (3) the nearest event in time — soonest-upcoming preferred, then
  most-recently-ended, else (4) a neutral phrase ("the next festival"). It is **never**
  a random specific holiday — a character only ever names a holiday that is active,
  imminent, or just past.
- **`%nextevent%` / `%lastevent%`** → the soonest-upcoming / most-recently-ended event,
  for explicit anticipation/aftermath lines; both fall back to the neutral phrase pool
  when scheduling is unknown.

If a dimension is disabled or its source API is missing, the token falls back to its
original random helper — today's behaviour.

### How context is sourced (and what happens if it can't be)

Context is read into a cached `ctx` table on a slow cadence (TTL `contextRefreshMs`,
default 60s) — never recomputed per candidate line. Every source is **capability-
guarded**: if the API is absent, that field stays neutral, the matching factor stays
`1.0`, and the token goes random — never an error, never silence.

| Dimension | Source | Fallback if unavailable |
|---|---|---|
| Time of day | the in-game clock via `GetGameTime()` (on 3.3.5 the day/night cycle follows the server's local time-of-day, so this **matches what players see out the window** — no real-world time is surfaced). | `%timeofday%` random; `times` tags never exclude. |
| Active events | `GetActiveGameEvents()`, mapped to display names. | `%event%` falls through to nearest/neutral; `events` tags never exclude. |
| Nearest events | the `game_event` schedule via `WorldDBQuery` (read once at startup), projected around now within a ~30-day horizon. | `%nextevent%`/`%lastevent%` use the neutral phrase; `approach`/`after` windows simply don't widen eligibility. |
| Season | the in-game month, with a holiday cross-check (e.g. Winter Veil ⇒ winter regardless of month). | `%season%` random; `seasons` tags never exclude. |

The vocabulary and mappings live in a small author-editable data file,
**`ActiveChat/context_map.lua`** — same philosophy as `npc_name.lua`. It holds
`eventIdToName` (game-event ID → display name), `monthToSeason` (override for themed
or southern-hemisphere realms), `eventNeutral` (the neutral phrase pool), and
`eventBurst` (see below). Edit these without touching the engine.

### Optional event-activation burst

With `enableEventBurst = true` (default **off**), the engine fires one short
character↔character "the festival has begun" exchange when an event flips from
inactive to active — a two-line duo whose `%event%` resolves to the just-activated
holiday. It is rate-limited to **once per activation** (a still-active event never
re-fires), reuses the existing duo machinery, and is fully guarded — with the flag off
the whole path is dead code, zero behavioural change.

This is the first tie-in to the (separate) player-interaction roadmap: the same `ctx`
table is the shared "what's true right now" seam that a future interaction responder
will also read. See `docs/plans/PLAYER_INTERACTION_PLAN.md` and
`docs/plans/CONTEXT_AWARE_PLAN.md`.

---

## Config reference

Set these at the top of `ActiveChat/npcTalk.lua`.

```lua
local enableScript      = true   -- master on/off
local enableFactionChat = true   -- true = gate alliance/horde lines by faction
                                 -- false = legacy: broadcast everything to everyone

local talk_time         = {1000, 10000}   -- Alliance-driver interval (ms)
local faction_talk_time = {8000, 20000}   -- Horde-driver interval (ms)
```

| Var | Default | What it does |
|---|---|---|
| `enableScript` | `true` | Master on/off for the whole module. |
| `enableFactionChat` | `true` | `true` = gate alliance/horde lines by faction. `false` = legacy: merge everything and broadcast to everyone. |
| `talk_time` | `{1000, 10000}` | Interval (ms, min/max) for the **Alliance-driver** timer — carries shared (everyone) + Alliance-only chatter. |
| `faction_talk_time` | `{8000, 20000}` | Interval (ms) for the **Horde-driver** timer. |
| `maxCharacters` | `128` | Cap on the lazily-grown roster. |
| `maxCharactersPerFaction` | `nil` | Optional per-faction sub-cap (`nil` = share the global cap). |
| `newCharacterWeight` | `8` | Weight of the virtual "spawn a new character" slot vs. existing characters' summed chattiness — tunes how fast the roster fills. |
| `lineCooldownTicks` | `8` | Default per-line repeat cooldown (in ticks) used by the line scorer. |
| `homeCityBias` | `true` | Bias `%city%` toward the speaking character's own home city (see below). |
| `roleMoodMatchStrength` | `3.0` | How hard role/mood matching is weighted in line scoring (`1` = off). |
| `areaMatchStrength` | `3.0` | How hard area matching is weighted in line scoring (`1` = off). |

#### Context-aware chatter flags

These control the time/event/season awareness (see "Context-aware chatter" below).
Each dimension degrades gracefully: turning a flag off — or running on a build whose
game-time/event API is missing — reverts that dimension to today's random behaviour.
It is **safe to ship on any build**; nothing here can error or silence a character.

| Var | Default | What it does |
|---|---|---|
| `enableContextAware` | `true` | Master switch for the whole context feature. Off ⇒ all three dimensions revert to random. |
| `enableTimeContext` | `true` | In-game-clock-aware `times` tags + `%timeofday%`. |
| `enableEventContext` | `true` | Active-event gating (`events`/`eventWindow` tags) + `%event%`/`%nextevent%`/`%lastevent%`. |
| `enableSeasonContext` | `true` | In-game-month season (`seasons` tags) + `%season%`. |
| `timeMatchStrength` | `3.0` | How hard a graded `times` match is boosted (`1` = off), like `areaMatchStrength`. |
| `seasonMatchStrength` | `3.0` | How hard a graded `seasons` match is boosted (`1` = off). |
| `contextRefreshMs` | `60000` | TTL (ms) of the cached `ctx`. Context is re-read at most this often, never per line. |
| `eventApproachDays` | `5` | Length (days) of the `eventWindow="approach"` run-up window. |
| `eventAfterDays` | `3` | Length (days) of the `eventWindow="after"` wind-down window. |
| `enableEventBurst` | `false` | Optional one-shot "the festival has begun" exchange when an event flips active (see below). Off by default. |

There is also an `ns` string near the top: an optional `WorldDBQuery` to source extra
surnames from the world DB (blank = use only `npc_name.lua`).

### `homeCityBias` and `%city%`

With `homeCityBias = true`, the `%city%` token resolves to the **current speaker's own
`homeCity`**, so a line reads as self-reference (each cast member in a duo/group
references *their* home, not just the conversation's initiator). Because a character's
`homeCity` is drawn from **their own faction's** capital list, this is automatically
faction-correct — a Horde speaker biases to a Horde capital, an Alliance speaker to an
Alliance one. Neutral hubs (Dalaran, Shattrath, Booty Bay) are never home cities, so
they only appear via the random path. With `homeCityBias = false`, `%city%` is random
over all cities (capitals + neutral hubs), as before.

---

## Audience model (who hears each line)

Lines are routed to listeners by the **origin pool** of the chosen line, and the two
chat timers are mapped to **factions** (not to audiences):

- **Alliance-driver** (on `talk_time`): an **Alliance** character speaks, drawing from
  `shared ∪ alliance`. Each chosen line is routed by its origin:
  - a **shared** line ⇒ `SendWorldMessage` (everyone), and
  - an **alliance** line ⇒ Alliance players only.

  So everyone-visible chatter is always **Alliance-voiced** — a Horde character never
  voices an everyone-visible line.
- **Horde-driver** (on `faction_talk_time`): a **Horde** character speaks, drawing from
  `horde` only, emitted to Horde players only.

Two drivers cover every audience path with no duplication: Alliance-only lines are
already alliance-origin items inside the Alliance speaker's candidate set, so a
separate Alliance-only timer would double-voice that pool — hence it was dropped.

**Legacy `enableFactionChat = false`:** all three pools merge into one everyone-visible
set (tagged `shared`), so both timers broadcast everything to everyone — the original
behavior, now voiced by characters.

Both drivers gate on `GetPlayersInWorld(team)`: with no online listeners for an
audience, the message is simply skipped.

---

## Placeholders

Drop these tokens into any line and the engine swaps in a random, lore-appropriate
value each time the line is spoken. (A token used twice in one line resolves to the
**same** value both times — the pick is made once per line.)

| Token | Replaced with |
|---|---|
| `%zone%` | a random game zone (e.g. *Stranglethorn Vale*) |
| `%instance%` | a random dungeon or raid (e.g. *Blackrock Depths*) |
| `%class%` | a random player class (e.g. *Druid*) |
| `%bg%` | a random battleground (e.g. *AV*) |
| `%profession%` | a profession (e.g. *Jewelcrafting*, *Cooking*) |
| `%activity%` | a gathering/profession activity, gerund phrase (e.g. *collecting herbs*) |
| `%city%` | a capital or neutral hub (biased to the speaker's home city when `homeCityBias`) |
| `%race%` | a playable race (e.g. *Blood Elf*) |
| `%monster%` | a hostile native creature (e.g. *murloc*, *owlbeast*) |
| `%critter%` | a passive critter (e.g. *deer*, *rabbit*) |
| `%boss%` | a notable boss (e.g. *The Lich King*, *Ragnaros*) |
| `%consumable%` | a flask, potion, or food buff (e.g. *Fish Feast*) |
| `%item%` | a famous epic/legendary (e.g. *Shadowmourne*) |
| `%rep%` | a reputation faction (e.g. *Kirin Tor*) |
| `%mount%` | a notable mount (e.g. *Invincible*) |
| `%spell%` | a class spell/ability (e.g. *Bloodlust*) |
| `%rare%` | a rare spawn (e.g. *Time-Lost Proto-Drake*) |
| `%pvptitle%` | a PvP/achievement title (e.g. *the Kingslayer*) |
| `%emote%` | an emote action verb (e.g. *cheer*, *facepalm*) |
| `%gold%` | a random gold amount, suffixed `g` (e.g. *8500g*) |
| `%level%` | a random character level, 2–80 |
| `%event%` | the most relevant **real** holiday/world event — what's actually active now, else the nearest upcoming/just-past one, else a neutral phrase. **Context-aware** (no longer a random holiday). See "Context-aware chatter". |
| `%nextevent%` | the **soonest upcoming** holiday/world event (or a neutral phrase if none is known). For explicit anticipation lines. |
| `%lastevent%` | the **most recently ended** holiday/world event (or a neutral phrase if none is known). For explicit aftermath lines. |
| `%season%` | the **current** in-game season (e.g. *winter*, *spring*). **Context-aware** — resolves to what's actually true now, not random. |
| `%timeofday%` | the **current** in-game time of day (e.g. *dusk*, *the small hours before dawn*). **Context-aware** — resolves to the in-game clock, not random. |
| `%shop%` | a named tavern, inn, or shop (e.g. *the Pig and Whistle Tavern*) |
| `%route%` | a travel route or method (e.g. *the Deeprun Tram*) |
| `%tale%` | a famous legend or story (e.g. *the Culling of Stratholme*) |
| `%weather%` | a weather condition (e.g. *a blizzard*, *clear skies*) |
| `%herb%` | a gatherable herb (e.g. *Frost Lotus*, *Goldclover*) |
| `%ore%` | an ore or smeltable metal (e.g. *Saronite*, *Truesilver*) |
| `%gem%` | a cut or raw gem (e.g. *Cardinal Ruby*) |
| `%fish%` | a catchable fish (e.g. *Dragonfin Angelfish*) |
| `%npc%` | a famous lore figure (e.g. *Thrall*, *Jaina Proudmoore*) |
| `%currency%` | an earned currency/badge (e.g. *Emblem of Frost*) |
| `%food%` | a tavern food (e.g. *a Dalaran Brownie*) |
| `%drink%` | a tavern drink (e.g. *Thunder Ale*) |
| `%title%` | a non-PvP/PvE title (e.g. *the Loremaster*, *Chef*) |
| `%tradegood%` | a crafting material (e.g. *Frostweave Cloth*, *Eternal Fire*) |
| `%companion%` | a vanity companion pet (e.g. *an Onyxian Whelpling*) |
| `%enchant%` | a gear enchantment (e.g. *Mongoose*, *Crusader*) |
| `%toy%` | a novelty/fun item (e.g. *a Noggenfogger Elixir*) |

> **In-character rule for the context tokens.** `%timeofday%`, `%season%`, `%event%`,
> `%nextevent%`, and `%lastevent%` always resolve to **fiction words only** — a
> time-of-day phrase, a season name, or a holiday name. They **never** surface a real
> clock (`22:00`), "server time", or a printed date. The time/season come from a
> *mapping* over the in-game game-time, not a displayed value.

### Player-imitation tokens (use sparingly)

These exist for the occasional adventurer voice, but the chatter is meant to be
**civilian/guard/NPC flavor, not an imitation of real players.** Avoid LFG/LFM,
grouping requests, and gearscore/parse talk — that's the job of a playerbot module,
not this script.

| Token | Replaced with |
|---|---|
| `%role%` | *Tank*, *Healer*, or *DPS* |
| `%difficulty%` | a difficulty tag (e.g. *25-man Heroic*) |
| `%gearscore%` | a WotLK-era GearScore number, 2400–6000 |

The lists these tokens draw from live near the top of `npcTalk.lua` and can be edited
there. The numeric tokens (`%gold%`, `%level%`, `%gearscore%`) are generated by small
helper functions in the same file.

## Docs
Possible roadmap and additional docs can be found under `docs/`.
