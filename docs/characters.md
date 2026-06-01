# Characters & roster

Chatter is voiced by an **in-memory roster of recurring characters** — named,
personality-bearing residents who reappear across a play session with a stable
identity, mood, and name color, rather than an endless stream of one-off random names.

The roster is:

- **Lazily generated.** It starts **empty** on every server start and grows on demand
  (see [Lazy growth](#lazy-growth--self-balancing)).
- **In-memory only.** Characters live entirely in Lua memory — **never persisted** (no
  DB rows, no creatures, no per-character save) and **reset on every restart**. A
  restart regrows a brand-new roster from scratch.
- **Recurring.** Within one session a character reappears across many lines with the
  same name, color, and personality, so the world feels populated by familiar voices.

## Character fields

Each generated character is a small Lua table:

| Field | Meaning |
|---|---|
| `name` | Display name (see [Name generation](#name-generation)) |
| `faction` | `"alliance"` or `"horde"` — intrinsic, never changes |
| `role` | Civic/occupation archetype, one of `ROLES` (e.g. `guard`, `vendor`) |
| `personality` | Mood descriptor, one of `PERSONALITIES` (e.g. `gruff`, `warm`) |
| `area` | Locale affinity, one of `AREAS` (e.g. `city`, `battlefield`) |
| `homeCity` | A capital **of the character's own faction** |
| `chattiness` | `0..1` — **selection weight**: how often this character is chosen to speak |
| `friendliness` | `0..1` — how likely they are pulled in as a **co-speaker** in a duo/group |
| `color` | Name color, **picked once at generation** and reused for every line they speak |

### chattiness vs friendliness

Two distinct levers. **`chattiness`** is the weight a character carries when a global
chat timer resolves *who speaks* — higher ⇒ chosen more often. **`friendliness`** sets
how likely a character is drawn in as a *co-speaker* when someone else starts a duo or
group. So a gruff hermit can be chatty but unfriendly (talks a lot, rarely joins
others); a shy regular can be friendly but quiet (seldom starts, often joins).

### Stable name color

A character's `color` is assigned **once**, at generation, from a small class-color
palette, and used by every line they ever speak. There is no per-line random color — a
recurring voice keeps a stable visual identity in chat.

## Lazy growth & self-balancing

The roster grows toward `maxCharacters` and then holds steady, with no startup batch
generation:

- On each chat tick the engine runs a weighted roulette over **every existing
  same-faction character** (weight = `chattiness`) **plus one virtual "spawn a new
  character" slot** (weight = `newCharacterWeight`).
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

## Name generation

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
feed additional surnames from the world DB via the `ns` query string in `config.lua`.

## Roles, personalities, areas

These three identity vocabularies are each defined in **exactly one table** in
`ActiveChat/data/roster_defs.lua` (required as `rosterDefs`). To add or change one, edit
only that table — no engine changes needed.

- **`ROLES`** (civic/occupation archetypes). Each entry has name `prefixes`, a
  roster-frequency `weight`, and a default `area` affinity:
  `guard`, `citizen`, `vendor`, `innkeeper`, `adventurer`, `soldier`, `mage`, `priest`,
  `craftsman`, `farmer`, `sailor`, `noble`, `drunkard`, `urchin`.
- **`PERSONALITIES`** (mood descriptors). Each maps to a pool of name epithets and
  doubles as a line-selection tag:
  `warm`, `gruff`, `cheerful`, `weary`, `wry`, `boastful`, `nervous`, `solemn`,
  `greedy`, `kindly`, `bitter`, `dreamy`, `brave`, `cowardly`, `gossipy`.
- **`AREAS`** (locale affinities):
  `city`, `rural`, `battlefield`, `coast`, `wilderness`, `road`.

At generation a character's `area` is biased (~65%) toward its role's default area, else
picked at random — so the roster reads as roughly role-typed without being rigid. How
the `area` affinity interacts with line tags is covered in
[authoring.md → The area tag](authoring.md#the-area-tag).

### Future hook: zone-specific chatter

In v1 a character's `area` is a **static affinity** assigned once at generation. The
code carries a **documented seam** (a commented `FUTURE HOOK` at the `area` assignment in
`generateCharacter`) for a later version to derive a character's *effective* area from a
**real player's current zone**, enabling true zone-specific chatter (e.g. battlefield
lines while players are in a contested zone) without changing the selection engine.
