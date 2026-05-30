# Eluna Lua Script: Lively World Chat

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
- This script requires the Eluna module for your server.
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
      * recencyPenalty (0 within the line's cooldown, ramping back to 1)
```

The next line is a weighted-random pick over score > 0. Role/mood mismatches only
*lower* the odds (never zero); only an out-of-area tagged line is hard-excluded.

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
| `%event%` | a holiday or world event (e.g. *Hallow's End*, *Brewfest*) |
| `%season%` | a season (e.g. *winter*, *high summer*) |
| `%timeofday%` | a time of day (e.g. *dusk*, *the small hours before dawn*) |
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
