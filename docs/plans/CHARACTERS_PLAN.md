# Plan: In-Memory Characters for ActiveChat

> **Scope note.** This introduces a roster of **persistent-for-the-session, in-world
> personas** that speak the ambient World/Guild chatter. They are generated at
> startup, live entirely in Lua memory, and are discarded on every server reset —
> **no DB, no creatures, no per-character persistence** (consistent with the
> philosophy already established in `PLAYER_INTERACTION_PLAN.md`). The point is to
> make the city feel populated by *recurring* voices with consistent identity and
> mood, rather than an endless stream of one-off random names.

## Decisions locked (from review)

**Round 1**

1. **`role` = civic/occupation archetype** — guard, vendor, innkeeper, adventurer,
   mage, citizen, soldier, etc. Not WoW Tank/Healer/DPS. Drives line flavor.
2. **Full retag now** — every existing line in `talk_text/` is converted to the new
   tagged object form up front (see migration section).
3. **Weighted preference + fallback** — a character prefers lines tagged for their
   role/personality/area but falls back to generic/untagged lines, so no character
   ever goes silent on thin content.
4. **Roster becomes the speaker pool** — ambient `lines`/`duos`/`groups` are now
   spoken *by* roster characters. Replaces the per-line `nameFrom()` random draw.

**Round 2**

5. **`shared` lines are voiced by Alliance characters.** A Horde character never
   voices an everyone-visible line. Mechanically: an Alliance character's candidate
   set is `shared ∪ alliance`; a Horde character's is `horde` only. Audience follows
   the pool the chosen line came from (shared → everyone, alliance → Alliance, horde
   → Horde).
6. **Per-character cadence.** Each character carries its own jittered timer scaled by
   `chattiness`, rather than one global tick selecting an initiator. Chatter density
   emerges from the roster.
7. **All toggles stay configurable**; content depth grows later (so the engine must
   behave sanely from sparse → rich content without code changes).
8. **Traits stay internal** for now. No player-facing surfacing; a debug/admin
   readout is a possible later add.
9. **Shared responder seam for player interaction.** The roster query used to pick
   ambient speakers is designed as a single reusable function so a future
   player-interaction responder (`PLAYER_INTERACTION_PLAN.md`) draws a *known
   recurring resident* from this same roster, not a fresh random name.

**New tag: `area`** — `city`, `rural`, `battlefield` (extensible). Both characters
and lines carry area information so setting-specific chatter lands where it fits: an
orc-ambush line is very likely on a `battlefield`, somewhat likely `rural`, and
absent in `city`. Untagged lines are **global** (fit any area); tagged lines are
zone-specific and weighted per area.

## Current architecture (what we build on)

`ActiveChat/npcTalk.lua` (single script under `if enableScript then … end`):

- **Names** are drawn fresh-random per line via `nameFrom(faction)` /
  `twoNames(faction)` / `manyNames(faction, n)` from the `{neutral, alliance, horde}`
  pools in `npc_name.lua`. **This is what the roster replaces.**
- **Content** loads from `talk_text/npc_text.lua` and `npc_text_guild.lua`, each
  returning `{ shared, alliance, horde }`, every faction pool being
  `{ lines, duos, groups }`. `buildItems(...)` flattens these into a cursored,
  kind-tagged item list (`kind = "line" | "duo" | "group"`).
- **Rendering** (`t.fg` / `t.dt`) walks the cursor, assigns a cast via `castFor`,
  picks speakers via `speakerFor` (A/B alternation for duos, non-repeating rotation
  for groups), then runs ~44 `%token%` substitutions.
- **Emission** via `CreateLuaEvent(fn, {min,max}, 0)` repeating timers;
  `GetPlayersInWorld(team)` for faction scoping; `formatWorld` / `formatGuild` apply
  the colored `[World]`/`[Guild]` name prefix.

The renderer, substitution, formatting, and faction scoping all stay. What changes is
**who speaks** (roster, not random names), **how each character is scheduled**
(per-character cadence, not one global tick), and **how a line is chosen for that
speaker** (trait + area weighting, not a random index).

## The character model

Generated at startup, held in a module-level table, never persisted:

```lua
local character = {
  name        = "Innkeep Hellena",  -- final display string (see name generation)
  faction     = "alliance",          -- "alliance" | "horde"
  role        = "innkeeper",         -- civic archetype (one of ROLES)
  personality = "warm",              -- 1-3 word descriptor (one of PERSONALITIES)
  area        = "city",              -- locale affinity (one of AREAS)
  homeCity    = "Stormwind",         -- a capital matching their faction
  chattiness  = 0.72,                -- 0..1 — drives this character's timer frequency
  friendliness= 0.55,                -- 0..1 — likelihood to join a duo/group
  color       = "C79C6E",            -- stable name color (picked once, from t.cc)
}
```

Notes:

- **Faction is intrinsic.** Characters are Alliance or Horde. Per decision 5, the
  everyone-visible `shared` pool is voiced only by Alliance characters.
- **`chattiness` vs `friendliness` are distinct levers.** Chattiness sets how *short*
  this character's own timer interval is (how often they speak at all). Friendliness
  sets how likely they are to be pulled in as a *co-speaker* when someone else starts
  a duo/group. A gruff hermit can be chatty but unfriendly, and vice versa.
- **`area` is a locale affinity**, assigned at generation with a bias from `role`
  (guard/vendor/innkeeper → `city`; soldier/adventurer → `battlefield`; farmer/sailor
  → `rural`) plus randomness so the roster isn't rigidly typed. It governs which
  area-tagged lines the character will draw (see selection engine). This is the
  static seed of "zone-specific chatter"; a later extension can derive a character's
  effective area from a real player zone.

### Roles (civic archetypes)

Starter set (extensible in one table): `guard`, `citizen`, `vendor`, `innkeeper`,
`adventurer`, `soldier`, `mage`, `priest`, `craftsman`, `farmer`, `sailor`, `noble`,
`drunkard`, `urchin`. Each role carries name prefixes, a roster-frequency weight, and
a default area affinity:

```lua
ROLES.innkeeper = { prefixes = {"Innkeep", "Barkeep", "Host"}, weight = 6, area = "city" }
ROLES.soldier   = { prefixes = {"Sergeant", "Private", "Trooper"}, weight = 5, area = "battlefield" }
ROLES.farmer    = { prefixes = {"Farmer", "Goodman", "Goodwife"}, weight = 4, area = "rural" }
```

### Personalities

1–3 word descriptors, each mapping to an **epithet pool** (for the
"{Name}, the {adjective}" name pattern) and serving as a line-selection tag:
`warm`, `gruff`, `cheerful`, `weary`, `wry`, `boastful`, `nervous`, `solemn`,
`greedy`, `kindly`, `bitter`, `dreamy`, `brave`, `cowardly`, `gossipy`.

```lua
PERSONALITIES.brave = { epithets = {"the Brave", "the Bold", "the Fearless"} }
PERSONALITIES.wry   = { epithets = {"the Sly", "the Quick-Tongued"} }
```

### Areas

```lua
AREAS = { "city", "rural", "battlefield" }   -- extensible (e.g. coast, wilderness)
```

## Name generation (semi-randomized)

`generateName(faction, role, personality)` builds a display string from one pattern,
weighted:

| Pattern | Weight | Example | Source data |
|---|---|---|---|
| `{first} {last}` | ~55% | *Aldric Stormbringer* | faction first-name pool + surname pool |
| `{Role} {first}` | ~20% | *Innkeep Hellena*, *Sergeant Brom* | `ROLES[role].prefixes` + first name |
| `{first}, {epithet}` | ~15% | *Actal, the Brave* | first name + `PERSONALITIES[p].epithets` |
| `{first}` (bare) | ~10% | *Maelara* | first name only |

Data sourcing (reuse + extend `npc_name.lua`):

- **First names** — the existing `alliance` / `horde` pools are already first-name
  style → use as the per-faction first-name source.
- **Surnames** — the existing `neutral` pool is surname-style (*Stormbringer*,
  *Frostguard*) → repurpose as a faction-agnostic surname pool.
- **New** small tables: role prefixes (in `ROLES`), epithets (in `PERSONALITIES`).

`npc_name.lua` restructures to `{ alliance=<first>, horde=<first>, surnames=<list> }`.
Generated names are deduped against the roster at build time (bounded retry).

## Content overhaul: tagged chat data (full retag)

Every entry gains optional metadata. Untagged entries remain valid universal
wildcards. New per-line fields:

- `roles` — list of role archetypes this line suits (omit = any role).
- `moods` — list of personalities this line suits (omit = any personality).
- `areas` — area fit. **Omit = global** (any area). A **list** = uniform weight
  across those areas. A **map** = graded likelihood, e.g. `{battlefield=3, rural=1}`
  (areas not listed are excluded). This is what makes the ambush line common on a
  battlefield, occasional in the countryside, and absent in the city.
- `weight` — relative pick frequency / "how often it can be used" (default 1).
- `cooldown` — min ticks before this exact line may repeat (default from config).

### Authoring shape (string-first, contributor-friendly)

An entry is either a bare string (untagged wildcard / global) or a table whose `[1]`
is the text and whose named keys are metadata.

```lua
-- one-liners (lines)
"The Cathedral bells are early today. A wedding, or a burial.",            -- global wildcard
{ "Three coppers a loaf and not a copper less.", roles={"vendor"}, moods={"gruff","greedy"}, areas={"city"} },
{ "Orcs in the treeline — to arms!", roles={"soldier","guard"}, moods={"nervous","brave"},
  areas={battlefield=3, rural=1} },                                        -- graded, never in city
{ "Rooms upstairs, warm fire, %drink% on the house tonight.", roles={"innkeeper"}, moods={"warm"},
  areas={"city","rural"}, weight=2 },

-- duos: declare cast roles/areas so the two speakers read as the right archetypes
{ chain={"Quiet on the wall tonight.", "Too quiet. I don't like it."},
  roles={"guard","soldier"}, moods={"solemn"}, areas={"city","battlefield"} },

-- groups
{ chain={"Which capital's the finest?", "Ironforge, no contest.", "Stormwind, surely.",
         "You've all forgotten Thunder Bluff.", "...this never ends, does it."},
  moods={"wry","boastful"}, areas={"city"} },
```

`buildItems` is updated to accept: a string → untagged item; a table with `chain` →
duo/group with optional tags; a table with `[1]` and no `chain` → a tagged one-liner.
It stays backward compatible with the current `{"a","b","c"}` duo/group arrays
(treated as untagged chains) so the retag proceeds file-by-file without breaking.

### Migration mechanics

The retag is mechanical but large (~600 lines across two files):

1. Land the new `buildItems` parser first (accepts old + new shapes) so nothing
   breaks mid-migration.
2. Convert `duos`/`groups` arrays to `{ chain={...} }` objects (text unchanged).
3. Tag the **obvious** lines by role/mood/area. Leave genuinely generic ambience
   **untagged & global** on purpose — that's the universal fallback the matcher needs.
4. A throwaway script can bulk-wrap steps 2–3; humans do the tagging. Document the
   new fields in `README.md`.

## Selection engine (how traits + area choose chatter)

Replaces "random index + random name." Built around per-character cadence
(decision 6) and a single reusable roster-query seam (decision 9).

### Per-character scheduling

At startup, after the roster is built, schedule **one recurring timer per character**
for world chat, with the interval scaled by `chattiness`:

```
interval = lerp(worldCadence.max, worldCadence.min, chattiness) ± jitter
CreateLuaEvent(fireFor(char, "world"), {interval_lo, interval_hi}, 0)
```

Guild chat reuses the same mechanism at a longer multiplier
(`guildCadenceMultiplier`) so guild stays sparser, per existing behavior. When a
character's timer fires, it gates on `GetPlayersInWorld(team)` for the relevant
audience — no online listeners of that audience ⇒ skip silently (no cursor churn).

### Candidate set & audience (decision 5)

- **Alliance character** → candidate lines = `shared ∪ alliance`. If the chosen line
  came from `shared`, emit via `SendWorldMessage` (everyone); if from `alliance`,
  emit to Alliance only.
- **Horde character** → candidate lines = `horde` only, emitted to Horde only.
- Honors the existing `enableFactionChat=false` legacy path (everything merged to
  everyone), in which case all characters draw from the merged pool.

### Line scoring (weighted preference + fallback)

For the firing character, score each candidate line:

```
score(line, char) = base(line.weight)
                  * roleFactor   (boost if char.role  ∈ line.roles; 1.0 if untagged; low if mismatch)
                  * moodFactor   (boost if char.personality ∈ line.moods; 1.0 if untagged; low if mismatch)
                  * areaFactor   (untagged → 1.0 global; tagged → per-area weight for char.area,
                                  EXCLUDE (≈0) if char.area not in the line's areas)
                  * recencyPenalty (≈0 within line.cooldown, ramps back to 1)
```

Weighted-random pick over scores. Untagged role/mood score `1.0` (neutral) and
untagged area is global, so a character always has eligible fallback lines and never
goes silent. `areaFactor` is the only factor that can hard-exclude (a city character
won't draw a battlefield-only line), which is the intended "wouldn't make sense in
Stormwind" guard.

### Cast assembly (duos/groups)

Initiator is speaker A / first voice. Co-speakers are drawn from the same-faction
roster (for `shared` lines, the Alliance roster) weighted by `friendliness`,
preferring `role`/`mood`/`area` compatibility with the chosen line, deduped against
the initiator. Reuses the existing distinct-speaker guard logic over *characters*.

### Reusable roster-query seam (decision 9)

All speaker selection funnels through one function so player-interaction can reuse it:

```lua
-- weightField: "chattiness" (initiator) or "friendliness" (co-speaker / responder)
-- filters (all optional): faction, role, mood, area, excludeGuid/excludeName
pickCharacter(weightField, filters) -> character | nil
```

The ambient initiator pick is `pickCharacter("chattiness", {faction=…})`; cast
assembly is repeated `pickCharacter("friendliness", {faction=…, role/mood/area=…})`.
A future player responder is just `pickCharacter("friendliness", {faction=playerTeam,
role=…, mood=…})` — a recurring resident answers, not a stranger.

### Rendering & emit

Hand the chosen character(s) to the existing `formatWorld` / `formatGuild`
(`char.name`, `char.color`), then run the existing `%token%` substitution. With
`homeCityBias`, `%city%` defaults to the speaker's `homeCity` for self-reference
consistency; otherwise random as today.

## Config additions (top of `npcTalk.lua`)

All configurable, sensible defaults (decision 7):

```lua
local characterCount        = 24      -- roster size generated at startup (the conf var)
local factionSplit          = 0.5     -- fraction of roster that is Alliance (rest Horde)
local worldCadence          = {30000, 120000}  -- ms interval bounds; chattiness maps within
local guildCadenceMultiplier= 3       -- guild timers run this much slower than world
local cadenceJitter         = 0.25    -- ± fraction applied to each character's interval
local lineCooldownTicks     = 8       -- default per-line repeat cooldown
local homeCityBias          = true    -- bias %city% toward a speaker's home city
local roleMoodMatchStrength = 3.0     -- how hard role/mood matching is weighted (1 = off)
local areaMatchStrength     = 3.0     -- how hard area matching is weighted (1 = off)
```

`characterCount` is the requested startup conf variable. Generation runs once in
`t.init`, after name data loads.

## Phased implementation

1. **Data tables** — add `ROLES` (with area affinity), `PERSONALITIES`, `AREAS`;
   restructure `npc_name.lua` to `{alliance, horde, surnames}`; add epithet/prefix
   pools. Pure data.
2. **Roster generation** — `generateName`, `buildRoster(characterCount)` (assigns
   faction/role/personality/area/home/traits), wire into `t.init`. Verify offline.
3. **`pickCharacter` seam + tagged parser** — the reusable roster query, and extend
   `buildItems` for the new shapes (back-compatible). Load-test both content files.
4. **Selection engine** — line scoring (role/mood/area/weight/recency), cast assembly
   by friendliness, Alliance-voices-`shared` candidate/audience rule.
5. **Per-character cadence** — replace global ambient timers with per-character world
   (+ guild-multiplier) timers; online-audience gating.
6. **Content retag** — duos/groups → `{chain=…}`; tag obvious lines by
   role/mood/area; leave generic ones untagged & global. Bulk-wrap via script, hand-
   tag the rest.
7. **Polish & docs** — `homeCity` bias, color stability; README for the character
   model, the `area` tag (global vs zone-specific), and the new authoring format.

Phases 1–5 can ship with content still mostly untagged (everything falls back to
global wildcard), so the roster + cadence go live before the retag finishes.

## Verification

- **Load/syntax:** `luac -p` (or `load`) every touched file after each phase.
- **Offline roster harness:** generate N; assert names unique, faction split ≈
  `factionSplit`, every character has valid role/personality/area/home, name patterns
  appear ≈ target proportions, area affinity correlates with role.
- **Selection harness (seeded RNG):** over K ticks assert (a) chattier characters
  fire more often, (b) a vendor/city character draws vendor/city lines above chance
  while still occasionally drawing globals, (c) a city character **never** draws a
  battlefield-only line, (d) graded areas resolve in the right proportion
  (battlefield ≫ rural for the ambush line), (e) cooldowns are respected, (f) no
  character ever fails to find a line, (g) `shared` lines are only ever voiced by
  Alliance characters.
- **`pickCharacter` unit test:** filters compose correctly; weight field switches
  between chattiness/friendliness; returns `nil` gracefully when no online faction.
- **In-game:** World/Guild still flow; names recur with stable color; toggle
  `characterCount` (1, 24, 100) without error; faction-scoped lines reach only the
  right faction; Alliance-only vs everyone audiences land correctly.
- **Tone check:** read tagged lines beside their role/area — a "vendor/gruff/city"
  line should sound like a gruff city vendor; mismatches get retagged or untagged.
- **Regression:** faction gating and the legacy `enableFactionChat=false` path still
  work.

## Open decisions for you

1. **Roster size vs. content depth.** With ~600 lines and 24 characters, recurrence
   feels populated but lines repeat. Bump default `characterCount`, lower per-line
   `cooldown`, or just grow content later (decision 7 leans here)?
2. **Area granularity.** Start with `city / rural / battlefield`, or seed a couple
   more now (`coast`, `wilderness`, `road`) so early content can tag richer settings
   before the migration locks in conventions?
3. **Character area drift.** Static per-character area affinity is the v1. Want a
   future hook noted for deriving a character's *effective* area from a real player's
   zone (true zone-specific chatter), or keep that out of scope entirely?
4. **Guild voicing.** Should guild chatter use the same per-character roster + cadence
   (a guild reads like a recurring cast), or stay a lighter shared stream? Currently
   planned as same roster, slower multiplier.
