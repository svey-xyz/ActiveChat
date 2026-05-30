# Plan: In-Memory Characters for ActiveChat

> **Scope note.** This introduces a roster of **persistent-for-the-session, in-world
> personas** that speak the ambient World chatter. They are generated
> **lazily** — created on demand as chatter is emitted, up to a configurable
> `maxCharacters` cap — live entirely in Lua memory, and are discarded on every
> server reset — **no DB, no creatures, no per-character persistence** (consistent
> with the philosophy already established in `PLAYER_INTERACTION_PLAN.md`). The point
> is to make the city feel populated by *recurring* voices with consistent identity
> and mood, rather than an endless stream of one-off random names.

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
6. **Single global timer + lazy incremental generation.** Keep the original
   per-channel global-tick model (one timer each for shared-world, alliance-world,
   horde-world) — **not** one timer per character. On each
   tick the speaker is resolved: pick an existing character (weighted by
   `chattiness`) **or**, if none is picked and the roster is below `maxCharacters`,
   generate a fresh character on the spot. The roster therefore accretes from empty
   as chatter happens and stabilizes at the cap. `chattiness` is now a *selection
   weight*, not a personal timer frequency. (Total chatter volume stays fixed by the
   timer intervals and is decoupled from roster size.)
7. **All toggles stay configurable**; content depth grows later (so the engine must
   behave sanely from sparse → rich content without code changes).
8. **Traits stay internal** for now. No player-facing surfacing; a debug/admin
   readout is a possible later add.
9. **Shared responder seam for player interaction.** The roster query used to pick
   ambient speakers is designed as a single reusable function so a future
   player-interaction responder (`PLAYER_INTERACTION_PLAN.md`) draws a *known
   recurring resident* from this same roster, not a fresh random name.
10. **Drop Guild chat entirely.** A guild is a player-organization construct that
    doesn't fit the civilian/guard/NPC scope. As part of this work, remove guild
    emission outright: delete `talk_text/npc_text_guild.lua`, the `enableGuildChat`
    flag, the `guild_talk_time` / `guild_faction_time` intervals, the `formatGuild`
    helper, and the guild `CreateLuaEvent` blocks in `npcTalk.lua`. The module
    becomes World-chat-only.

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
- **Content** loads from `talk_text/npc_text.lua` (the guild file
  `npc_text_guild.lua` is **removed** — decision 10), returning
  `{ shared, alliance, horde }`, every faction pool being `{ lines, duos, groups }`.
  `buildItems(...)` flattens these into a cursored, kind-tagged item list
  (`kind = "line" | "duo" | "group"`).
- **Rendering** (`t.fg` / `t.dt`) walks the cursor, assigns a cast via `castFor`,
  picks speakers via `speakerFor` (A/B alternation for duos, non-repeating rotation
  for groups), then runs ~44 `%token%` substitutions.
- **Emission** via `CreateLuaEvent(fn, {min,max}, 0)` repeating timers;
  `GetPlayersInWorld(team)` for faction scoping; `formatWorld` applies the colored
  `[World]` name prefix. (`formatGuild` and the `[Guild]` path are removed —
  decision 10.)

The renderer, substitution, formatting, faction scoping, **and the per-channel global
timers all stay**. What changes is **who speaks** (a lazily-grown roster, not a fresh
random name each line) and **how a line is chosen for that speaker** (trait + area
weighting, not a random index). The roster is built incrementally at tick time rather
than at startup.

## The character model

Generated lazily at tick time (see selection engine), held in a module-level table,
never persisted:

```lua
local character = {
  name        = "Innkeep Hellena",  -- final display string (see name generation)
  faction     = "alliance",          -- "alliance" | "horde"
  role        = "innkeeper",         -- civic archetype (one of ROLES)
  personality = "warm",              -- 1-3 word descriptor (one of PERSONALITIES)
  area        = "city",              -- locale affinity (one of AREAS)
  homeCity    = "Stormwind",         -- a capital matching their faction
  chattiness  = 0.72,                -- 0..1 — selection weight when a tick resolves a speaker
  friendliness= 0.55,                -- 0..1 — likelihood to join a duo/group
  color       = "C79C6E",            -- stable name color (picked once, from t.cc)
}
```

Notes:

- **Faction is intrinsic.** Characters are Alliance or Horde. Per decision 5, the
  everyone-visible `shared` pool is voiced only by Alliance characters.
- **`chattiness` vs `friendliness` are distinct levers.** Chattiness is the weight a
  character carries when a global tick resolves who speaks — higher chattiness ⇒
  chosen more often across ticks. Friendliness sets how likely they are to be pulled
  in as a *co-speaker* when someone else starts a duo/group. A gruff hermit can be
  chatty but unfriendly, and vice versa.
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

Replaces "random index + random name." Built around the original per-channel global
timers (decision 6) and a single reusable roster-query seam (decision 9).

### Speaker resolution with lazy generation (decision 6)

The existing per-channel timers are kept as-is. When one fires, it gates on
`GetPlayersInWorld(team)` for its audience (no online listeners ⇒ skip silently, no
cursor churn), then resolves a speaker for the target faction:

```
resolveSpeaker(faction) ->
  candidates = rosterByFaction[faction]              -- may be empty early on
  -- weighted roulette over: each existing character (weight = chattiness)
  --                         + one VIRTUAL "new character" slot (weight = newCharacterWeight)
  pick = weightedPick(candidates by chattiness, plus virtualNew = newCharacterWeight)
  if pick == virtualNew and #roster < maxCharacters then
      return generateCharacter(faction)              -- spawn, register, speak this tick
  elseif pick == virtualNew then
      return weightedPick(candidates by chattiness)  -- at cap: fall back to reuse
  else
      return pick
```

This makes spawning **self-balancing**: when the faction roster is empty or small its
summed chattiness weight is low, so the virtual slot usually wins and the population
grows; as it fills, existing weight dominates and spawning tapers, halting at
`maxCharacters`. Cold start (empty roster) always spawns, since the virtual slot is
the only candidate. `newCharacterWeight` tunes how eagerly the world populates.

`generateCharacter(faction)` runs the same assignment logic the startup builder would
have (role → area bias, personality, home city, traits, `generateName`), registers
the character in `roster` / `rosterByFaction`, and returns it to speak immediately.

For `shared` (everyone-visible) ticks, `resolveSpeaker("alliance")` is used so the
voice is always Alliance (decision 5).

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

The resolved initiator is speaker A / first voice. Co-speakers are drawn from the
same-faction roster (for `shared` lines, the Alliance roster) weighted by
`friendliness`, preferring `role`/`mood`/`area` compatibility with the chosen line,
deduped against the initiator. If the faction roster is too small to fill the cast,
co-speakers are lazily generated the same way (subject to `maxCharacters`). Reuses the
existing distinct-speaker guard logic over *characters*.

### Reusable roster-query seam (decision 9)

Speaker selection funnels through two thin functions so player-interaction can reuse
them:

```lua
-- resolveSpeaker(faction) — weighted pick over existing (by chattiness) + virtual
--   new-character slot; lazily spawns under maxCharacters (see above).
-- pickCharacter(weightField, filters) — pick an EXISTING character only.
--   weightField: "chattiness" | "friendliness"
--   filters (all optional): faction, role, mood, area, excludeName, allowSpawn
pickCharacter(weightField, filters) -> character | nil
```

Ambient initiator = `resolveSpeaker(faction)`; cast assembly = repeated
`pickCharacter("friendliness", {faction=…, role/mood/area=…, allowSpawn=true})`. A
future player responder is `pickCharacter("friendliness", {faction=playerTeam,
role=…, mood=…})` — a recurring resident answers, not a stranger (and may spawn one if
the roster is thin and `allowSpawn` is set).

### Rendering & emit

Hand the chosen character(s) to the existing `formatWorld`
(`char.name`, `char.color`), then run the existing `%token%` substitution. With
`homeCityBias`, `%city%` defaults to the speaker's `homeCity` for self-reference
consistency; otherwise random as today.

## Config additions (top of `npcTalk.lua`)

All configurable, sensible defaults (decision 7):

```lua
local maxCharacters         = 24      -- cap on the lazily-grown roster (the conf var)
local maxCharactersPerFaction = nil   -- optional per-faction sub-cap (nil = share maxCharacters)
local newCharacterWeight    = 8       -- virtual "spawn a new character" weight vs existing chattiness
local lineCooldownTicks     = 8       -- default per-line repeat cooldown
local homeCityBias          = true    -- bias %city% toward a speaker's home city
local roleMoodMatchStrength = 3.0     -- how hard role/mood matching is weighted (1 = off)
local areaMatchStrength     = 3.0     -- how hard area matching is weighted (1 = off)
```

The retained interval config (`talk_time`, `faction_talk_time`) is unchanged — those
drive the World per-channel timers as before. The guild intervals
(`guild_talk_time`, `guild_faction_time`) and the `enableGuildChat` flag are
**removed** (decision 10). `maxCharacters` is the requested conf variable; the roster
starts empty and grows on demand. `newCharacterWeight` tunes how fast it populates
relative to reuse.

## Phased implementation

0. **Drop Guild chat** — delete `talk_text/npc_text_guild.lua`; remove the
   `enableGuildChat` flag, `guild_talk_time` / `guild_faction_time`, `formatGuild`,
   and the guild `CreateLuaEvent` blocks from `npcTalk.lua`. Standalone, mechanical
   cleanup; do it first so later phases touch a World-only engine.
1. **Data tables** — add `ROLES` (with area affinity), `PERSONALITIES`, `AREAS`;
   restructure `npc_name.lua` to `{alliance, horde, surnames}`; add epithet/prefix
   pools. Pure data.
2. **Lazy generation** — `generateName`, `generateCharacter(faction)` (assigns
   role/personality/area/home/traits, registers in the roster), and the empty-roster
   scaffolding in `t.init`. Verify offline by repeatedly generating and printing.
3. **`resolveSpeaker` / `pickCharacter` seam + tagged parser** — the weighted pick
   with the virtual new-character slot and `maxCharacters` cap, plus extend
   `buildItems` for the new tagged shapes (back-compatible). Load-test both files.
4. **Selection engine** — line scoring (role/mood/area/weight/recency), cast assembly
   by friendliness, Alliance-voices-`shared` candidate/audience rule. Keep the
   existing per-channel timers; swap their speaker source to `resolveSpeaker`.
5. **Content retag** — duos/groups → `{chain=…}`; tag obvious lines by
   role/mood/area; leave generic ones untagged & global. Bulk-wrap via script, hand-
   tag the rest.
6. **Polish & docs** — `homeCity` bias, color stability; README for the character
   model, the `area` tag (global vs zone-specific), and the new authoring format.

Phases 1–4 can ship with content still mostly untagged (everything falls back to
global wildcard), so the roster goes live before the retag finishes.

## Verification

- **Load/syntax:** `luac -p` (or `load`) every touched file after each phase.
- **Offline generation harness:** generate many characters; assert names unique,
  every character has valid role/personality/area/home, name patterns appear ≈ target
  proportions, area affinity correlates with role.
- **Lazy-growth harness (seeded RNG):** drive K ticks from an empty roster and assert
  (a) the first tick spawns (cold start), (b) the roster grows then plateaus exactly
  at `maxCharacters` (never exceeds it), (c) spawn rate tapers as the roster fills
  (higher `newCharacterWeight` ⇒ faster fill), (d) once at cap it's pure reuse.
- **Selection harness (seeded RNG):** over K ticks assert (a) chattier characters are
  picked more often, (b) a vendor/city character draws vendor/city lines above chance
  while still occasionally drawing globals, (c) a city character **never** draws a
  battlefield-only line, (d) graded areas resolve in the right proportion
  (battlefield ≫ rural for the ambush line), (e) cooldowns are respected, (f) no
  character ever fails to find a line, (g) `shared` lines are only ever voiced by
  Alliance characters.
- **`pickCharacter` unit test:** filters compose correctly; weight field switches
  between chattiness/friendliness; returns `nil` gracefully when no online faction.
- **In-game:** World chat still flows (and **no** Guild chat is emitted); names recur
  with stable color; the roster
  visibly populates over the first minutes then settles; toggle `maxCharacters`
  (1, 24, 100) without error; faction-scoped lines reach only the right faction;
  Alliance-only vs everyone audiences land correctly.
- **Tone check:** read tagged lines beside their role/area — a "vendor/gruff/city"
  line should sound like a gruff city vendor; mismatches get retagged or untagged.
- **Regression:** faction gating and the legacy `enableFactionChat=false` path still
  work.

## Open decisions — RESOLVED (2026-05-30)

1. **Roster size vs. content depth.** RESOLVED: default `maxCharacters = 128`. A
   larger roster gives a solid mix of both factions and character types; pair it with
   the expanded content from the final content pass so lines spread well.
2. **Area granularity.** RESOLVED: seed **six** areas now —
   `city`, `rural`, `battlefield`, `coast`, `wilderness`, `road`. Lock these
   conventions before the content retag so early tagging uses the full set.
3. **Character area drift.** RESOLVED: keep static per-character area affinity for v1,
   but **note a documented future hook** (a clearly-commented seam) for deriving a
   character's *effective* area from a real player's zone, enabling true
   zone-specific chatter later.

## Implementation progress log

> Each phase's sub-agent appends a short note here on completion (what changed,
> files touched, verification done) so state is preserved across sessions.

- **2026-05-30 — Phase 0 (Drop Guild chat) complete.** Removed Guild chat entirely,
  leaving a World-chat-only engine. Deleted `ActiveChat/talk_text/npc_text_guild.lua`.
  In `ActiveChat/npcTalk.lua` removed: the top-comment Guild description (retitled
  "Lively World Chat"), the `enableGuildChat` flag, the `guild_talk_time` /
  `guild_faction_time` interval tables, the `local guild = require("npc_text_guild")`
  load line, the `formatGuild` helper, the shared-guild `CreateLuaEvent`, the
  Alliance/Horde guild `CreateLuaEvent` blocks inside `enableFactionChat`, and the
  `guild_talk`/`guild_alli`/`guild_horde` `buildItems` entries in `t.t` (both the
  faction branch and the legacy `else` branch). World timers, faction gating, the
  legacy path, renderer, token substitution, and name pools left untouched.
  Verification: `python3 docs/plans/_luacheck.py ActiveChat/npcTalk.lua
  ActiveChat/talk_text/npc_text.lua` reports `OK` for both; case-insensitive grep for
  `guild`/`formatGuild`/`enableGuildChat` in `npcTalk.lua` returns nothing; the guild
  text file is confirmed gone.
- **2026-05-30 — Phase 1 (Data tables) complete.** Pure data only; nothing wired
  into generation/selection yet. In `ActiveChat/npcTalk.lua` added a clearly
  commented "Character system data tables (Phase 1)" block (inside `if enableScript
  then`, just above `t.cc`): `local AREAS` = the six locked areas
  (`city, rural, battlefield, coast, wilderness, road`); `local ROLES` (14 entries,
  each `{prefixes, weight, area}`) with role->area mapping — city: guard, citizen,
  vendor, innkeeper, mage, priest, craftsman, noble, drunkard, urchin;
  wilderness: adventurer; battlefield: soldier; rural: farmer; coast: sailor;
  `local PERSONALITIES` (15 moods, each `{epithets}` with 2-3 "the X" epithets).
  Added a comment noting all three tables are extensible in one place.
  Restructured `ActiveChat/npc_name.lua` to `{alliance, horde, surnames}`:
  renamed the old surname-style `neutral` pool to `surnames`, kept `alliance`/`horde`
  first-name pools unchanged, rewrote the header comment, and added a Phase-1
  BACKWARD-COMPAT alias `names.neutral = names.surnames` (same reference) so the
  still-live `nameFrom`/`twoNames`/`manyNames` and `t.init` DB-append path keep
  working until Phase 2 (flagged in a comment for Phase 2 cleanup). No
  generateName/generateCharacter, timers, or renderer changes (Phase 2+).
  Verification: `python3 docs/plans/_luacheck.py ActiveChat/npcTalk.lua
  ActiveChat/npc_name.lua` reports `OK` for both; a lupa snippet `dofile`d
  `npc_name.lua` (from the ActiveChat dir) confirming `alliance=88`, `horde=86`,
  `surnames=233`, all non-empty, and `neutral` referencing the same list as
  `surnames`; a standalone Lua loop asserted all 14 `ROLES[*].area` values are
  members of `AREAS` (6 areas) — reported OK.
- **2026-05-30 — Phase 2 (Lazy character generation) complete.** Added the
  character-generation layer to `ActiveChat/npcTalk.lua` (selection engine /
  timer rewiring intentionally NOT done — that's Phase 3+). New code, all inside
  `if enableScript then`, placed just below the PERSONALITIES table:
  • **Roster state** — `local roster = {}`, `local rosterByFaction =
  {alliance={}, horde={}}`, `local usedNames = {}`, with a clear comment that
  these live in Lua memory only, are never persisted, and reset on restart.
  • **Home-city pools** — `local allianceCities =
  {"Stormwind","Ironforge","Darnassus","The Exodar"}` and `local hordeCities =
  {"Orgrimmar","Thunder Bluff","Undercity","Silvermoon City"}` — neutral hubs
  (Dalaran/Shattrath/Booty Bay) deliberately excluded as home cities.
  • **`generateName(faction, role, personality)`** — weighted pattern table:
  `{first last}` ≤55, `{Role first}` ≤75 (uses `ROLES[role].prefixes`),
  `{first, epithet}` ≤90 (uses `PERSONALITIES[p].epithets`), `{first}` bare
  otherwise; first names from `t.d[faction]`, surnames from `t.d.surnames`;
  bounded 12-try dedup against `usedNames` then accept. Defensive fallbacks if a
  prefix/epithet pool is ever empty.
  • **`generateCharacter(faction)`** — assembles the full model from the plan
  (name, faction, role, personality, area, homeCity, chattiness, friendliness,
  color); role picked by `ROLES[*].weight` roulette; **area bias = 65%** toward
  `ROLES[role].area` else uniform `AREAS`; personality uniform over
  PERSONALITIES keys; homeCity from the faction's capital list; chattiness /
  friendliness `math.random()` floats in [0,1]; color picked once from `t.cc`
  (stable per character). Registers into `roster` + `rosterByFaction[faction]`,
  marks the name used, returns the character. **Cap NOT enforced here** — a
  `-- Phase 3: cap enforced in resolveSpeaker` note marks the seam.
  • **FUTURE HOOK comment** (locked decision 3) at the `area` assignment, noting
  v1 uses static affinity and a later version can derive effective area from a
  real player's zone.
  • Left the legacy `nameFrom`/`twoNames`/`manyNames`/`castFor` random-name path
  and all timers UNTOUCHED (still drive live World chat between phases); added a
  block comment flagging that Phase 4 removes that path and the `neutral`
  alias / DB-append-into-neutral block once `resolveSpeaker` drives the timers.
  `t.init` unchanged (still seeds RNG once and loads `t.d`); roster starts empty.
  Design choices: area bias 0.65; chattiness/friendliness uniform `math.random()`;
  4-capital home-city lists per faction; dedup retry bound 12.
  Verification: `python3 docs/plans/_luacheck.py ActiveChat/npcTalk.lua
  ActiveChat/npc_name.lua` → `OK` for both. Offline harness
  (`outputs/phase2_harness.py`, lupa + dofile of `npc_name.lua`, seeded RNG)
  generated 2000 characters across both factions: 0 validation errors (every
  char has valid role∈ROLES, personality∈PERSONALITIES, area∈AREAS, correct
  faction-capital homeCity, chattiness/friendliness∈[0,1], non-empty name+color,
  zero neutral-hub home cities); 2000/2000 unique names (dedup working).
  Name-pattern proportions at realistic roster size 128: first_last 53.1%
  (target 55), role_first 22.7% (20), first_epithet 14.1% (15), bare 10.2% (10)
  — all within ~3%. (At 2000 chars bare dips to 6.2% purely because the
  ~350-name first-name pool exhausts and the dedup retry re-rolls away from the
  low-entropy bare pattern — a harness artifact, not a logic bug; irrelevant at
  the default `maxCharacters=128`.) Role→area affinity observable but not
  absolute: sailor→coast 69%, soldier→battlefield 69%, farmer→rural 68%,
  adventurer→wilderness 73%, guard→city 71%, vendor→city 69% — matching the
  0.65 bias plus randomness. Harness left in `outputs/`, not committed to repo.
- **2026-05-30 — Phase 3 (resolveSpeaker / pickCharacter seam + tagged parser)
  complete.** Scoring + timer rewiring intentionally NOT done (Phase 4). All new
  code in `ActiveChat/npcTalk.lua`, inside `if enableScript then`.
  **Config (Part A)** — added near the interval config: `maxCharacters=128`
  (locked), `maxCharactersPerFaction=nil` (optional per-faction sub-cap; nil =
  share the global cap), `newCharacterWeight=8`, `lineCooldownTicks=8`,
  `homeCityBias=true`, `roleMoodMatchStrength=3.0`, `areaMatchStrength=3.0`
  (the last four are read by Phase 4).
  **Functions (Part B)** — `pickCharacter(weightField, filters)`: EXISTING-only
  weighted-random pick (weightField "chattiness"|"friendliness"; optional
  filters faction/role/mood/area/excludeName/allowSpawn — `allowSpawn` is
  documented as ignored here, consumed by callers/resolveSpeaker; never spawns;
  returns nil when no candidate). `resolveSpeaker(faction)`: weighted roulette
  over existing same-faction chars (weight=chattiness) PLUS one virtual
  new-character slot (weight=newCharacterWeight) — virtualNew + under cap →
  `generateCharacter`; virtualNew at cap → fall back to
  `pickCharacter("chattiness",{faction})`; else return the picked char. Helper
  `rosterAtCap(faction)` enforces the global `maxCharacters` and, when set, the
  per-faction sub-cap. Cold start always spawns (virtual slot is the only
  candidate). Comment notes `shared` ticks call `resolveSpeaker("alliance")`
  (decision 5); actual timer wiring is Phase 4.
  **Tagged parser (Part B.3)** — extended `buildItems` via two helpers,
  `normalizeAreas` and `makeItem(kind, entry, forceChain)`, back-compatibly
  accepting: bare string → untagged line; table `[1]` + no chain → tagged
  one-liner; table `chain={...}` → tagged duo/group (data = chain array); legacy
  `{"a","b",...}` array from duos/groups (forceChain + `[1]` is a string) →
  untagged chain. Cursor `[0]` behavior preserved; live emission path still
  reads `item.kind`/`item.data` unchanged (line → string data; duo/group →
  array data).
  **NORMALIZED `areas` INTERNAL SHAPE (relied on by Phase 4 + Phase 5):** every
  parsed item carries `areaGlobal` (bool) and `areas` (ALWAYS a map area→weight,
  never a list). Omitted areas → `areaGlobal=true, areas={}` (fits any area; the
  empty map is ignored). List `{"city","rural"}` → `areaGlobal=false,
  areas={city=1, rural=1}` (uniform weight 1 per listed area). Map
  `{battlefield=3, rural=1}` → `areaGlobal=false, areas` copied as-is (graded;
  areas absent from the map are EXCLUDED). Phase 4 reads it uniformly: global →
  areaFactor 1.0; otherwise `areas[char.area]` or hard-exclude when absent. Each
  item also has `roles`/`moods` (arrays or nil = any), `weight` (default 1),
  `cooldown` (default `lineCooldownTicks`). The full normalized item shape is
  documented in a comment block above `normalizeAreas` in `npcTalk.lua`.
  **Verification:** `python3 docs/plans/_luacheck.py ActiveChat/npcTalk.lua
  ActiveChat/talk_text/npc_text.lua` → `OK` for both. Lazy-growth harness
  (`outputs/phase3_growth_harness.lua` + `phase3_run_growth.py`, lupa, seeded
  RNG, K=3000 from empty roster): (a) first tick spawns (cold start);
  (b) roster grows then plateaus EXACTLY at maxCharacters=128, maxSeen=128,
  final=128, never exceeds; (c) spawn rate tapers (all 128 spawns land in the
  early fill window) and higher newCharacterWeight fills faster — ticks-to-cap
  w=8 → 671, w=32 → 240; (d) spawns-after-cap = 0 (pure reuse at cap). Per-faction
  sub-cap run (maxCharactersPerFaction=10): final=10, maxSeen=10, spawns-after-cap
  = 0 — sub-cap honored. Parser unit test
  (`outputs/phase3_parser_harness.lua` + `phase3_run_parser.py`): 8/8 items
  normalized to the expected shape — bare string, tagged line with LIST areas
  (`city=1`), tagged line with MAP areas (`battlefield=3;rural=1`, weight=2),
  tagged line with OMITTED areas (`areaGlobal=true`, cooldown override honored),
  `chain=` duo & group, and legacy `{"a","b"}` / `{"a","b","c"}` arrays — all
  PASS (kind, data shape, roles/moods, areaGlobal flag + area map, weight,
  cooldown defaults). Harness scripts left in `outputs/`, not committed.
- **2026-05-30 — Phase 4 (Selection engine + timer rewiring) complete.** Made
  characters speak, scored by traits/area, and rewired the timers. All changes
  in `ActiveChat/npcTalk.lua` (+ cleanup in `npc_name.lua`).
  **Candidate lists (decision 5):** replaced the channel-keyed `t.t`
  (talk/talk_alli/talk_horde) with per-SPEAKER-FACTION candidate lists built once
  at startup — `allianceCandidates = shared ∪ alliance`, `hordeCandidates =
  horde`. Each item is stamped with an `audience` ORIGIN tag
  ("shared"|"alliance"|"horde") via helpers `taggedItems`/`mergeCandidates`
  (which flatten buildItems output and drop its `[0]` cursor). Emission routes by
  that tag, so an Alliance speaker can voice a shared (everyone) line OR an
  alliance-only line from the same set. Legacy `enableFactionChat=false`:
  shared+alliance+horde merged, all tagged audience="shared", and
  `hordeCandidates == allianceCandidates` → everything to everyone.
  **TIMER-MAPPING DESIGN (and WHY):** kept TWO drivers, mapped to FACTIONS not
  audiences. (1) **alliance-driver** (on the faster `talk_time` interval) →
  `resolveSpeaker("alliance")` over `allianceCandidates`; each chosen line routes
  by its own audience tag (shared→`SendWorldMessage` everyone; alliance→Alliance
  only). This ONE timer carries BOTH the everyone-visible chatter and the
  Alliance-only chatter. (2) **horde-driver** (on `faction_talk_time`) →
  `resolveSpeaker("horde")` over `hordeCandidates` (Horde-only). The old separate
  alliance-only timer was DROPPED because, in the per-faction candidate model,
  Alliance-only lines are alliance-origin items already inside the Alliance
  speaker's set — a third timer would double-voice the alliance pool. Two drivers
  cover every audience path with zero duplication and satisfy decision 5 (shared
  is always Alliance-voiced). Legacy mode keeps a second driver as a redundant
  everyone-visible feed (Alliance-voiced, audience="shared") to preserve the
  original two-timer cadence.
  **Scoring formula specifics:** `scoreLine = weight(default 1) * roleFactor *
  moodFactor * areaFactor * recencyPenalty`. roleFactor/moodFactor:
  match→`roleMoodMatchStrength`(3.0), untagged(nil)→1.0, mismatch→`1/3.0≈0.333`
  (a low FLOOR, not zero — never silent). areaFactor: global→1.0; else
  `areas[char.area] * areaMatchStrength`(3.0); area-not-in-map → 0 = the ONLY
  hard-exclude. recencyPenalty: 0 within `cooldown` ticks of last use, ramps
  linearly 0→1 across the next `cooldown` ticks, fully recovered at `2*cooldown`.
  Per-item recency tracked on the item itself (`item.lastTick`); a module-level
  `globalTick` increments once per started conversation item. `pickLine` does a
  weighted-random pick over score>0 items, with an any-global-item fallback if
  ALL candidates are excluded (never silent). Cast assembly (`assembleCast`)
  draws co-speakers from the same-faction roster by `friendliness`, progressively
  looser filters (role+mood+area → faction-only → lazy spawn under cap), deduped
  by name; `speakerForLine` alternates duos A/B and rotates groups with a
  no-immediate-repeat guard — all over CHARACTERS now. `formatWorld` takes the
  speaking character and uses its STABLE `color` (was a random color per line).
  `%city%` biases to the current speaker's `homeCity` when `homeCityBias` is on
  (`cityFor`). A new per-channel `t.conv` conversation state machine (`nextLine`)
  finishes a started duo/group line-by-line with its fixed cast before starting a
  fresh item; `renderTokens` holds the unchanged ~44 `%token%` gsubs.
  **Legacy code REMOVED:** the entire random-name path — `nameFrom`, `twoNames`,
  `manyNames`, `castFor`, the old name-based `speakerFor`, `lastSpeaker`, the
  `broadcastFaction` helper, and `t.fg`/`t.dt` (replaced by `nextLine`/
  `renderTokens`/`speak`/`emit`). In `npc_name.lua` removed the `neutral`
  back-compat alias and updated the header. In `t.init`, the flat-list fallback
  now maps to `surnames` and the optional DB-name source (`ns`) appends into
  `surnames` (was the removed `neutral` pool).
  **Verification:** `python3 docs/plans/_luacheck.py` → `OK` for npcTalk.lua,
  npc_name.lua, npc_text.lua. Full live-load test (lupa, stubbed Eluna globals):
  script loads, registers exactly 2 timers, and fired 600 emissions (both
  drivers) with no error; legacy `enableFactionChat=false` also loads, 2 timers,
  600 emissions all via SendWorldMessage. Selection harness
  (`outputs/phase4_harness.lua`, seeded RNG 20260530): (a) chattier picked more —
  Hi(0.9)=18018 vs Lo(0.1)=1982 over 20k (≈9:1, matches the chattiness ratio);
  (b) vendor/gruff/city char over 20k draws vendorCity=16851 (its role+mood+city
  match) while still drawing globals 658+631 and cityAny 1860, battleOnly/ambush=0;
  (c) city citizen NEVER drew battleOnly or ambush (both 0) and never failed
  (nil=0); (d) graded ambush `{battlefield=3,rural=1}` — over 20k a battlefield
  soldier drew ambush=14162 vs battleOnly=4702 (≈3:1); direct score check
  battlefield=27.0, rural=9.0 (exactly 3:1), city=0 (hard-excluded); (e) cooldowns
  respected — 0 violations over 5000 ticks (cdLine never re-picked within its
  8-tick window given non-cooled alternates); (f) no character ever silent — 0
  fails over 5000 random (faction×role×mood×area) speakers; (g) shared/alliance
  lines only Alliance-voiced — over 8000 drives, 0 shared/alliance lines voiced
  by a non-Alliance speaker and 0 shared/alliance lines emitted by the Horde
  driver. Harness in `outputs/`, not committed.
  **Phase 5 (content retag) notes:** the engine ships now with content still
  mostly untagged (everything falls back to global, which is exactly why every
  test character always finds a line). Retag should add `roles`/`moods`/`areas`
  to obvious lines and CONVERT duos/groups to `{chain=…}` objects; the parser
  already accepts both shapes. The `areas` MAP form (e.g. `{battlefield=3,
  rural=1}`) is what drives graded weighting — list form gives uniform weight 1.
  Leaving genuinely generic ambience untagged & global is REQUIRED (it's the
  universal fallback). **Phase 6 (polish/docs) notes:** `homeCity` `%city%` bias
  is implemented minimally (per current speaker) — Phase 6 can refine; color
  stability is done; README still needs the character-model / `area`-tag /
  authoring-format docs and an explanation of the two-driver timer design.
- **2026-05-30 — Phase 5 (Content retag) complete.** Retagged the EXISTING content
  in `ActiveChat/talk_text/npc_text.lua` (no new content written). Updated the
  header comment block to document the tagged authoring format (string-first;
  list vs map `areas`; valid role/mood/area lists; the "leave generic ambience
  global" rule) with inline examples. **Conversions:** ALL duos/groups across all
  three pools converted from legacy `{"a","b",...}` arrays to `{ chain={...} }`
  objects (text unchanged) — shared 46 duos + 6 groups, alliance 11 + 4,
  horde 10 + 4 (35 duos + 14 groups total). Tagged the obvious lines/duos/groups
  by role/mood/area per content; left genuinely generic ambience UNTAGGED &
  GLOBAL on purpose as the universal fallback. **Tagged-vs-global per pool (over
  parsed items):** shared 143 tagged / 99 global (59%), alliance 52 / 11 (82%),
  horde 58 / 5 (92%). The faction pools skew higher because their content is
  almost entirely capital-city ambiance (genuinely `areas={"city"}`); fallback
  safety still holds — area-UNRESTRICTED items number 99 (shared), 18 (alliance),
  11 (horde) plus rural/road horde items, and role/mood never hard-exclude
  (only a non-listed area does), so no character goes silent (Alliance also draws
  shared; Horde has its 11 area-global + rural/road lines). **Judgment calls:**
  vendor-price/haggle lines → `vendor` + `gruff`/`greedy`; guard cries/ordinance
  → `guard` + `gruff`, `city`; tavern/inn → `innkeeper` + `warm`/`cheerful`;
  Booty Bay/docks/harbor/sailor → `sailor`, `coast`; Thunder Bluff/Mulgore/plains
  → `rural`; rumor/"they say"/half-overheard → `gossipy`; war/grief/cathedral
  → `solemn`/`weary`, priest where faith-flavored; graded `areas` maps used for
  contested-town (`{battlefield=2, rural=1}`), barrens caravan (`{road=2,
  rural=1}`), front-news (`{battlefield=2, city=1}`); a couple of warm generic
  closers given `weight=2`, the cemetery-flowers line `cooldown=20` (distinctive).
  Preserved ALL line text exactly and the shared/alliance/horde structure.
  **Verification:** `python3 docs/plans/_luacheck.py
  ActiveChat/talk_text/npc_text.lua` → `OK`. Standalone parse harness
  (`outputs/phase5_verify.py`, lupa + dofile, Phase-3 buildItems/normalizeAreas/
  makeItem extracted verbatim, seeded RNG): all 368 parsed items normalize to a
  valid shape (kind ∈ line/duo/group; line data string; duo/group data array);
  **ZERO invalid role/mood/area identifiers** across all pools; tone spot-check
  of 15 random tagged lines eyeballed correct (vendor/gruff/city reads as a gruff
  city vendor, sailor/coast as dockside, etc.). Harness left in `outputs/`, not
  committed. **THIN areas/roles/moods for the Phase-6/expansion content pass to
  target:** AREAS — `battlefield` and `wilderness` are very under-represented
  (only a few graded-map references; no front-line/ambush one-liners exist yet),
  and `road` is thin; the faction pools are almost entirely `city`, so `rural`/
  `coast` content is sparse there. ROLES — `farmer`, `sailor`, `noble`, `urchin`,
  and `cowardly`-flavored `soldier` content is thin (few dedicated lines); most
  tags cluster on guard/vendor/innkeeper/adventurer/mage/priest. MOODS —
  `cowardly`, `brave`, and `greedy` are barely used; `gruff`/`solemn`/`wry`/`warm`
  dominate. The expansion pass should add battlefield/wilderness/coast/rural
  ambience and farmer/sailor/noble/urchin voices to balance the pools.
- **2026-05-30 — Phase 6 (Polish & docs) complete.** Final code phase.
  **Polish (`ActiveChat/npcTalk.lua`):**
  • *Color stability* — removed the dead random-color fallback in `formatWorld`
  (was `speaker.color or t.cc[math.random(#t.cc)]`); it now uses `speaker.color`
  directly. The ONLY `t.cc[math.random]` left is the once-per-character
  assignment in `generateCharacter` (line ~816), so every line a character
  speaks uses its stable generation-time color. Verified by grep.
  • *`homeCity` bias for `%city%`* — confirmed already correct and finished the
  intent: `cityFor(speaker)` resolves `%city%` to the CURRENT speaker's own
  `homeCity` (the renderer is called per-line with that line's speaker, so each
  duo/group cast member self-references their own home, not just the initiator).
  Because `homeCity` is drawn at generation from the speaker's OWN faction
  capital list, it is automatically faction-correct (Horde→Horde capital,
  Alliance→Alliance); neutral hubs only appear via the random (`homeCityBias=false`)
  path. Strengthened the `cityFor` comment to document this.
  • *Cleanup* — confirmed every config var is consumed; tidied the config block
  comments (dropped per-var "(Phase N)" markers, point to README "Config
  reference"); fixed the now-false "(Phase 1) PURE DATA, not yet wired in"
  data-table header and the "Phase 2 only fills them" roster-state comment to
  describe the live state; reworded the conversation-state-machine header,
  `t.init`, and `resolveSpeaker`/`generateCharacter` comments that referenced
  removed symbols (nameFrom/twoNames/manyNames/neutral) or future-tense
  already-done work; cleaned the `npc_name.lua` header + removed its stale
  Phase-1/Phase-4 `neutral`-alias notes. No behavior change beyond removing the
  dead color fallback. (Remaining "(Phase N)" mentions are accurate section/
  cross-reference provenance, left intact.)
  **README.md — full rewrite to match the current code.** Retitled to "Lively
  World Chat" and added an explicit note that **Guild chat is GONE** (World-only
  now). New/updated sections: *The character roster* (lazy/in-memory/never-
  persisted/reset-on-restart; the field table name/faction/role/personality/
  area/homeCity/chattiness/friendliness/color; chattiness-vs-friendliness;
  stable color; lazy growth + self-balancing to `maxCharacters` via
  `newCharacterWeight`; name generation patterns); *Roles, personalities, areas*
  (the full valid identifier lists; note they're extensible in the one ROLES/
  PERSONALITIES/AREAS table each); *The `area` tag* (untagged=global, list=
  uniform, map=graded, area-only hard-exclude; the documented FUTURE HOOK for
  deriving effective area from a player's zone, decision 3); *Authoring content*
  (string-first tagged shape with bare-string / list-areas / graded-map-areas /
  tagged-duo examples, the tag-fields table, the scoring summary, pointer to the
  npc_text.lua header); *Config reference* (every var: maxCharacters=128,
  maxCharactersPerFaction, newCharacterWeight, lineCooldownTicks, homeCityBias,
  roleMoodMatchStrength, areaMatchStrength, talk_time, faction_talk_time,
  enableScript, enableFactionChat, plus `ns`); *Audience model* (the two-driver
  decision-5 design: Alliance speakers voice shared∪alliance routed per origin,
  Horde voices horde-only, legacy merges to everyone). Verified the placeholder
  token table against `renderTokens` — all 44 real tokens documented, none
  invented; dropped the obsolete Guild "Content structure" / guild-interval
  references.
  **Verification:** `python3 docs/plans/_luacheck.py ActiveChat/npcTalk.lua
  ActiveChat/npc_name.lua ActiveChat/talk_text/npc_text.lua` → `OK` for all
  three. Live-load smoke test (`outputs/phase6_smoke.py`, lupa, stubbed Eluna
  globals — CreateLuaEvent/SendWorldMessage/GetPlayersInWorld/WorldDBQuery/
  SendBroadcastMessage): script `dofile`d clean, registered EXACTLY 2 timers;
  fired both drivers 400 ticks (800 emissions) with 0 errors; 126 distinct
  speakers, 110 spoke 2+ times, EVERY name rendered exactly ONE color (color
  stable). homeCity check via a `%city%`-only content shim over 500 ticks: all
  128 speakers each render exactly ONE valid faction capital (0 multi-city,
  0 non-capital), and all 62 Horde-audience speakers biased to a Horde capital
  with 0 capital/faction mismatches. Grep confirms NO remaining references to
  removed symbols (nameFrom/twoNames/manyNames/formatGuild/enableGuildChat/guild)
  in npcTalk.lua and NO `t.cc[math.random` in the per-character emit path (only
  the generation-time assignment). Harness left in `outputs/`, not committed.
  **Remaining rough edges (follow-up):** (1) the content pools are still thin in
  `battlefield`/`wilderness`/`coast`/`rural` and in farmer/sailor/noble/urchin
  and cowardly/brave/greedy voices (carried over from Phase 5) — a content
  EXPANSION pass would let the 128-character roster and area weighting spread
  better. (2) The zone-derived effective-area FUTURE HOOK is documented but not
  implemented (intentional, decision 3 v1 scope). (3) The reusable
  `pickCharacter` seam for a future player-interaction responder (decision 9)
  exists and is tested but has no live caller yet — that's the
  PLAYER_INTERACTION_PLAN follow-on.

- **2026-05-30 — Final content pass 1/3 (tokenization).** Tasteful tokenization
  review of the entire `ActiveChat/talk_text/npc_text.lua` (no lines added/removed;
  tags from Phase 5 untouched; only TEXT edited). **Tokenized (rough counts):**
  *shared* ~5 — "a paladin help an old woman" → `%class%`; "Bought a meat pie from
  a street cart" → `%food%`; "bought them both a drink" → `%drink%` (drink pool is
  article-mixed so no leading article needed); "a song about my last dungeon run" →
  "my last `%instance%` run"; (also reverted one trial: "Heard the Argent Crusade is
  recruiting" was NOT tokenized to `%rep%` — see below). *alliance* ~1 — cat-naming
  line "Named him Bolvar. He judges everyone." → "Named it `%npc%`. It judges
  everyone." (switched him→it to stay gender-safe across the female `%npc%` members).
  *horde* 0 new (content is almost entirely faction-internal proper nouns —
  Valley of Strength, the Drag, Cleft of Shadow, Apothecarium, Murder Row — which
  carry no token and would break faction/locale flavor if forced). **Also FIXED a
  pre-existing grammar artifact** (not introduced this pass): alliance group line
  "who knows the `%boss%` fight" produced "the The Lich King fight" when `%boss%`
  resolves to a "The…"-prefixed boss → reworded to "who knows the fight against
  `%boss%`." **Deliberately LEFT untokenized (judgment calls):** all 11 festival
  one-liners (each names a holiday AND its specific custom — bonfire/eggs/marigolds —
  so the holiday IS the joke; `%event%`/`%season%` would gut them); the Onyxia
  "her head's hanging in the city gate" line (gendered + iconic capital-gate lore is
  the point; `%boss%` would break "her"); the race-rubbing-shoulders block (dwarf
  beard / big tauren-small gnome jokes are race-specific); "pet sporebat loose in the
  auction house" and similar `%companion%` candidates (the companion pool bakes
  leading articles → "Someone's a Mechanical Squirrel is loose" doubles articles);
  "pet my war mount … lives for ear scratches" (`%mount%` members like "Reins of…"/
  "Mimiron's Head"/"X-51 Nether-Rocket" break the ear-scratches beast joke); the
  Argent-Crusade-recruiting line (several `%rep%` members — Kirin Tor, Cenarion
  Circle, Timbermaw furbolgs — wouldn't "recruit soldiers at the city gates");
  "flute carved from a raptor bone" (`%monster%` contains "troll", and the troll/
  raptor pairing is intentional flavor); all neutral-hub lines (Dalaran floating /
  Aldor-Scryers grudge / Sha'tar refugees / Salty Sailor Tavern) and Alliance/Horde
  district lines (faction-correct, location-locked); the "Pig and Whistle" Stormwind
  veteran line (`%shop%` would bleed Horde-side taverns into an Alliance line); the
  Duskwood solemn grave line (Duskwood's gothic mood is load-bearing). Kept density
  low on purpose per the "don't mad-libs it" rule. **Verification:** luacheck →
  `OK`; Phase-5 parse harness (`outputs/phase5_verify.py`) → all 242/63/63 items
  still normalize, **0 invalid role/mood/area identifiers**, counts unchanged (no
  add/remove); renderer artifact scan (`outputs/pass1_render_check.py`, ~44 token
  pools stubbed with article-mixed sample values, 40 renders × 647 text strings
  across every line/duo/group chain entry) → **0 artifacts** (no "a a"/"an an"/
  "the the"/"a an", no stray `%`, no double spaces, no unknown/typo'd tokens; all
  tokens used in content are known). Harness left in `outputs/`, not committed.

## All phases complete

All six phases (0 Drop Guild chat, 1 Data tables, 2 Lazy generation, 3
resolveSpeaker/pickCharacter + tagged parser, 4 Selection engine + timer
rewiring, 5 Content retag, 6 Polish & docs) are done. The module is a
World-chat-only engine voiced by a lazily-grown, in-memory, never-persisted
character roster with trait/area-weighted line selection, stable per-character
name colors, faction-correct `%city%` home-city bias, the two-driver
(Alliance/Horde) decision-5 audience model, and a fully documented README +
authoring format. All touched files pass luacheck; the live-load smoke test
passes. Future work: content expansion for thin areas/roles/moods, the
zone-derived effective-area hook, and the player-interaction responder reusing
the `pickCharacter` seam.

- **2026-05-30 — Final content pass 2b/3 (shared duos+groups) complete.** Expanded
  ONLY `shared.duos` and `shared.groups` in `ActiveChat/talk_text/npc_text.lua`
  (no touch to `shared.lines`, `alliance`, or `horde`). Added **31 new duos** and
  **10 new groups** with commented subsection headers, deliberately filling the
  thin non-city buckets. Per-bucket coverage — duos: coast 7, rural 6,
  battlefield 6, wilderness 5, road 6, noble/urchin (city/road) 4; groups: coast 3,
  rural 3, battlefield 2, wilderness/road 2. Featured under-used roles (farmer,
  sailor, noble, urchin, soldier) and moods (cowardly, brave, greedy, bitter,
  nervous, dreamy, kindly). Verification: `_luacheck.py` → **OK**;
  `phase5_verify.py` → **Invalid identifiers: 0**, shared total 364 → **408**;
  `pass1_render_check.py` → **0 artifacts (CLEAN)**.
- **2026-05-30 — Final content pass 3/3 (alliance+horde expansion) complete.**
  Expanded ONLY the `alliance` and `horde` pools in
  `ActiveChat/talk_text/npc_text.lua` (no touch to `shared`), filling the thin
  non-city buckets with faction-true, tagged, token-rich chatter using each
  faction's own proper nouns. **Added per pool:** alliance — **61 lines, 15 duos,
  5 groups** (63 → **144** items); horde — **60 lines, 15 duos, 5 groups**
  (63 → **143** items). All under commented subsection headers. **Per-bucket
  coverage (both pools):** AREAS — added rural (Elwynn/Westfall farms &
  Dwarven-highland craft vs. Mulgore plains/Durotar), coast
  (Menethil/Auberdine docks vs. Ratchet/Bilgewater/Echo Isles), battlefield
  (each faction's own war front — Scourge/north), wilderness (Dun
  Morogh/Loch/Teldrassil hunting vs. Barrens/Stonetalon), road (the tram &
  Elwynn/Lakeshire caravans vs. Razor Hill/Crossroads & zeppelin runs), plus
  kept some city. ROLES — featured the thin ones: farmer, sailor, noble, urchin,
  plus soldier, guard, craftsman, drunkard, priest (faction-adapted: troll witch
  doctor / tauren spirit-walker / Forsaken shadow priest), mage, vendor,
  innkeeper, citizen, adventurer. MOODS — featured cowardly, brave, greedy plus
  dreamy, bitter, nervous, boastful, kindly, solemn, weary, wry, warm, cheerful,
  gossipy. No cross-faction confusion; Alliance uses Light/Cathedral/SI:7/kaldorei
  /Explorers' League proper nouns, Horde uses Earth Mother/loa/ancestors/Lok'tar
  /Warchief/Sin'dorei voice. **Verification:** `_luacheck.py` → **OK**;
  `phase5_verify.py` → **Invalid identifiers: 0**, alliance 63 → **144**, horde
  63 → **143** (tagged: alliance 92%, horde 96%; each retains area-global +
  rural/coast/road/battlefield/wilderness fallback so no character goes silent —
  Alliance also draws shared); `pass1_render_check.py` → **0 artifacts (CLEAN)**;
  15-line tone spot-check read faction- and tag-correct (tauren-rural dreamy,
  Drag-urchin wry/nervous, Horde soldier solemn cairn-burial, etc.).

## Content expansion complete

After the final 3-pass content expansion, the pool item totals stand at:
**shared 408**, **alliance 144**, **horde 143** (per `phase5_verify.py`). All
three pools now carry balanced rural/coast/battlefield/wilderness/road coverage
and full role/mood representation alongside the original city-heavy ambiance;
luacheck OK, 0 invalid identifiers, 0 render artifacts across all pools.
