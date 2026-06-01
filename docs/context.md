# Context-aware chatter

By default the chatter doesn't just read like Azeroth — it reads like Azeroth *right
now*. Night lines fire at night, festival lines fire during the actual festival, and
season talk tracks the real game state instead of a coin flip.

This is a **selection-and-substitution refinement**, not a new subsystem: it reuses the
line scorer (three new factors alongside `areaFactor`, see
[authoring.md → How a line is chosen](authoring.md#how-a-line-is-chosen)) and the
placeholder pass (the time/event/season tokens now resolve to *what's true*). Everything
stays inside the fiction — **no real-world clocks, no "server time" meta** — and
degrades gracefully: if a context source is unavailable, that dimension reverts to random
behaviour and nobody goes silent. Turn the master flag (or any sub-flag) in
[config.md → Context-aware flags](config.md#context-aware-chatter-flags) off and you get
exactly the old random behaviour.

## The line tags

Authoring gains optional tags with the **same** list/map/hard-exclude semantics the
`area` tag already uses. Leave generic ambience untagged — that global pool is the
fallback the matcher needs.

| Field | Meaning |
|---|---|
| `times` | Time-of-day fit. **Omit** = any time. **List** (`{"night","dusk"}`) = uniform; unlisted buckets hard-excluded. **Map** (`{night=3, dusk=1}`) = graded. Buckets: `dawn` / `morning` / `midday` / `afternoon` / `dusk` / `night`. |
| `events` | Event fit (**binary** — no graded form). **Omit** = fires regardless. A **list** of event display-names = fires **only while one is active** (or, with `eventWindow`, in its approach/after window); otherwise hard-excluded. |
| `eventWindow` | Pairs with `events`. `"active"` (default) = only while live. `"approach"` = also fire in the **N-day run-up** (`eventApproachDays`, default `5`), keyed off `%nextevent%`. `"after"` = also fire in the **N-day wind-down** (`eventAfterDays`, default `3`), keyed off `%lastevent%`. |
| `seasons` | Season fit. Same semantics as `times`. Seasons: `winter` / `spring` / `summer` / `autumn`. |
| `notTimes` / `notSeasons` / `notEvents` | **Negative gate** — the mirror of the tags above: a line fires in **any** context **except** the ones listed. Unlike the positive tags this applies even to an otherwise-global line, so you can keep a line universal and carve out the single context it must never fire in. |

```lua
-- night-only ambience (silent until evening, uniform at dusk/night)
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

-- universal line, but the joke needs daylight: never at night or dusk
{ "The tavern's rowdy this %timeofday% -- two duels already, and it's not even dark.",
  notTimes={"night","dusk"} },
```

Event display-names must match the names in `data/context.lua` exactly (e.g.
`"the Harvest Festival"`, `"the Midsummer Fire Festival"` — articles included).

## The context tokens

`%timeofday%`, `%season%`, `%event%`, `%nextevent%`, and `%lastevent%` resolve to the
**current** state rather than a random pick:

- **`%timeofday%`** → a display phrase for the current in-game time bucket.
- **`%season%`** → the current in-game season.
- **`%event%`** → the most relevant *real* event, in priority order: (1) the line's own
  `events` tag if present (so token and tag always agree), else (2) something active now,
  else (3) the nearest event in time — soonest-upcoming preferred, then most-recently-
  ended, else (4) a neutral phrase ("the next festival"). It is **never** a random
  specific holiday — a character only ever names one that is active, imminent, or just
  past.
- **`%nextevent%` / `%lastevent%`** → the soonest-upcoming / most-recently-ended event,
  for explicit anticipation/aftermath lines; both fall back to the neutral phrase pool
  when scheduling is unknown.

If a dimension is disabled or its source API is missing, the token falls back to its
original random helper.

> **In-character rule.** These five tokens always resolve to **fiction words only** — a
> time-of-day phrase, a season name, or a holiday name. They **never** surface a real
> clock (`22:00`), "server time", or a printed date. Time/season come from a *mapping*
> over the in-game game-time, not a displayed value.

## Context-aware token *values*

Context-awareness also reaches the **value a token resolves to**, not just which line is
chosen. A few pools where context clearly matters — `%food%`, `%drink%`, `%weather%`,
`%activity%`, `%critter%` — carry the **same** `times`/`seasons`/`events` tags as lines,
on their individual entries (`data/tokens.lua`). A shared `selectTagged` biases the pick
toward what fits the live `ctx` (hard-excluding off-context entries, untagged entries
always eligible), reusing the very same `timeFactor`/`seasonFactor`/`eventFactor` the
line scorer uses. So *porridge* surfaces in the morning and *Pilgrim's pie* only during
Pilgrim's Bounty. With context off/unavailable every value scores equally — the old
uniform random pick (the same fallback invariant as the line scorer). Abstract pools
stay untagged. Authoring details and the related `%a…%` article tokens are in
[placeholders.md](placeholders.md#context-aware-token-values).

## How context is sourced (and what happens if it can't be)

The whole context subsystem — the cache, its refresh, and the token resolvers — lives in
`AzerothChatter/logic/context.lua` (`require("logic.context")`, aliased to `context`; the engine captures `context.ctx` once
and reads it live). Context is read into the cached `ctx` table on a slow cadence (TTL
`contextRefreshMs`, default 60s) — never recomputed per candidate line. Every source is
**capability-guarded**: if the API is absent, that field stays neutral, the matching
factor stays `1.0`, and the token goes random — never an error, never silence.

| Dimension | Source | Fallback if unavailable |
|---|---|---|
| Time of day | the in-game clock via `GetGameTime()` (on 3.3.5 the day/night cycle follows the server's local time-of-day, so this **matches what players see out the window** — no real-world time is surfaced). | `%timeofday%` random; `times` tags never exclude. |
| Active events | `GetActiveGameEvents()`, mapped to display names. | `%event%` falls through to nearest/neutral; `events` tags never exclude. |
| Nearest events | the `game_event` schedule via `WorldDBQuery` (read once at startup), projected around now within a ~30-day horizon. | `%nextevent%`/`%lastevent%` use the neutral phrase; `approach`/`after` windows don't widen eligibility. |
| Season | the in-game month, with a holiday cross-check (e.g. Winter Veil ⇒ winter regardless of month). | `%season%` random; `seasons` tags never exclude. |

The vocabulary and mappings live in a small author-editable data file,
**`AzerothChatter/data/context.lua`** — same philosophy as `data/names.lua`. It holds
`eventIdToName` (game-event ID → display name), `monthToSeason` (override for themed or
southern-hemisphere realms), `eventNeutral` (the neutral phrase pool), and `eventBurst`
(below). Edit these without touching the engine.

## Optional event-activation burst

With `enableEventBurst = true` (default **off**), the engine fires one short
character↔character "the festival has begun" exchange when an event flips from inactive
to active — a two-line duo whose `%event%` resolves to the just-activated holiday. It is
rate-limited to **once per activation** (a still-active event never re-fires), reuses the
existing duo machinery, and is fully guarded — with the flag off the whole path is dead
code, zero behavioural change.

This is the first tie-in to the (separate) player-interaction roadmap: the same `ctx`
table is the shared "what's true right now" seam that a future interaction responder will
also read. See [`plans/PLAYER_INTERACTION_PLAN.md`](plans/PLAYER_INTERACTION_PLAN.md) and
[`plans/CONTEXT_AWARE_PLAN.md`](plans/CONTEXT_AWARE_PLAN.md).
