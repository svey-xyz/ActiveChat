# Authoring content

World chatter lives in `AzerothChatter/data/chatter.lua`. It returns three pools:

```lua
return {
  shared   = { lines = {...}, duos = {...}, groups = {...} },  -- seen by everyone
  alliance = { lines = {...}, duos = {...}, groups = {...} },  -- Alliance only
  horde    = { lines = {...}, duos = {...}, groups = {...} },  -- Horde only
}
```

Each pool has three lists — the **three conversation shapes**:

- **`lines`** — standalone one-liners, spoken by a single character.
- **`duos`** — two-person back-and-forth; two fixed speakers alternate A / B / A / B.
- **`groups`** — group discussions; a rotating cast of 4–6 voices, one line each, no
  voice speaking twice in a row.

The header comment block at the top of `data/chatter.lua` is the canonical authoring
reference. Keep new lines **in-character** — no real-world references, no fourth-wall
jokes; Azeroth is real to these voices.

## Tagged authoring format (string-first)

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

(Legacy bare `{"a","b"}` arrays still parse as untagged chains, but new content should
use the `chain=` form.)

### Tag fields (all optional)

| Field | Meaning |
|---|---|
| `roles` | List of role archetypes the line suits. **Omit = any role.** |
| `moods` | List of personalities the line suits. **Omit = any personality.** |
| `areas` | Area fit: **omit** = global; **list** = uniform; **map** = graded (unlisted areas hard-excluded). See [The area tag](#the-area-tag). |
| `times` | Time-of-day fit. See [context.md](context.md). |
| `events` | Event fit (binary). See [context.md](context.md). |
| `eventWindow` | Pairs with `events`: `"active"` (default) / `"approach"` / `"after"`. See [context.md](context.md). |
| `seasons` | Season fit; same semantics as `times`. See [context.md](context.md). |
| `notTimes` / `notSeasons` / `notEvents` | **Negative gate** — fires in any context **except** the ones listed (e.g. `notTimes={"night"}`), even on an otherwise-global line. See [context.md](context.md). |
| `weight` | Relative pick frequency (default `1`). Bump good generic lines up. |
| `cooldown` | Min ticks before this exact line repeats (default `lineCooldownTicks`). Raise for distinctive lines. |

> **Leave genuinely generic ambience untagged and global on purpose.** That untagged
> pool is the fallback the matcher needs so no character ever goes silent. Tag a line
> only when its content clearly implies a role/mood/area/context.

## The area tag

`area` makes setting-specific chatter land where it fits. Both characters (affinity, see
[characters.md](characters.md#roles-personalities-areas)) and lines (tags) carry area
information, and selection compares them:

- **Untagged line ⇒ global wildcard.** No `areas` tag fits **any** area and any
  character — the universal fallback pool.
- **`areas` as a list ⇒ uniform fit.** `areas={"city","rural"}` is equally at home in
  those areas (excluded elsewhere).
- **`areas` as a map ⇒ graded fit.** `areas={battlefield=3, rural=1}` is three times as
  likely on a battlefield as in the countryside.
- **Hard-exclude.** With a tagged line, an area **not listed** is hard-excluded: a city
  character will *never* draw a battlefield-only line. Area (along with the context
  tags) is the only kind of factor that can hard-exclude — role/mood mismatches merely
  lower the odds, so a character always has eligible fallback lines and never goes
  silent.

## How a line is chosen

For the speaking character, every candidate line is scored:

```
score = weight
      * roleFactor    (boost if char.role ∈ line.roles; 1.0 if untagged; low floor on mismatch)
      * moodFactor    (boost if char.personality ∈ line.moods; 1.0 if untagged; low floor on mismatch)
      * areaFactor    (1.0 if untagged; per-area weight if char.area is listed; 0 = EXCLUDE otherwise)
      * timeFactor    (1.0 if untagged; per-bucket weight if ctx.timeKey is listed; 0 = EXCLUDE otherwise)
      * eventFactor   (1.0 if untagged; 1.0 when a tagged event applies — see eventWindow; 0 = EXCLUDE otherwise)
      * seasonFactor  (1.0 if untagged; per-season weight if ctx.season is listed; 0 = EXCLUDE otherwise)
      * excludeFactor (1.0 normally; 0 = EXCLUDE when the current time/season/active-event is in notTimes/notSeasons/notEvents)
      * recencyPenalty (0 within the line's cooldown, ramping back to 1)
```

The next line is a weighted-random pick over `score > 0`. Role/mood mismatches only
*lower* the odds (never zero); out-of-area, out-of-time, out-of-event, and out-of-season
tagged lines are hard-excluded.

`timeFactor` and `seasonFactor` mirror `areaFactor` exactly (graded matches boosted by
`timeMatchStrength` / `seasonMatchStrength`, default `3.0`). `eventFactor` is **binary**
— an event-tagged line is fundamentally *about* that event, so it either applies (`1.0`)
or is excluded (`0`), with no graded boost. The **fallback invariant** holds throughout:
because untagged lines stay `1.0` on every factor, a character always has eligible
candidates even when every tagged line is out of context — and if the in-game
clock/event/season can't be read at all, the corresponding factor stays `1.0` rather
than going silent. See [context.md](context.md) for how the live `ctx` is sourced.
