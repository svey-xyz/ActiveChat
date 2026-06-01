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
| `gender` | `"male"`, `"female"`, or `"neutral"` — drives an agreeing name + pronouns |
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

A character's **gender** is rolled first (config `genderRatio`), and the name is built to
agree with it. Names come from `AzerothChatter/data/names.lua` (first-name pools bucketed
by gender) plus the gender-bucketed role prefixes and the personality epithets in `ROLES`
/ `PERSONALITIES`. One of four weighted patterns is chosen per character:

| Pattern | ~Weight | Example |
|---|---|---|
| `{first} {last}` | 55% | *Aldric Stormbringer* |
| `{Role} {first}` | 20% | *Innkeep Hellena*, *Sergeant Brom* |
| `{first}, {epithet}` | 15% | *Actal, the Brave* |
| `{first}` (bare) | 10% | *Maelara* |

Because the first name and the role prefix are both drawn from the character's gender, the
prefix always agrees with the name — no more *"Sister Cedric"* or *"Lady Thorgrim"*. The
chosen pieces are kept as structured `nameParts` (`prefix` / `first` / `surname` /
`epithet`) so a conversation can address a character by a natural short form (see
[Addressing other speakers](#addressing-other-speakers)). Legacy flat name/prefix lists
still load and are treated as neutral.

Names are de-duplicated against the live roster (bounded retry). You can optionally
feed additional surnames from the world DB via the `ns` query string in `AzerothChatter.lua`.

## Gender-aware lines & pronouns

A character's `gender` lets lines fit the speaker and lets pronouns resolve correctly.

- **`genders` line tag.** A line may carry `genders = {"female"}` (or `{"male"}`) to
  prefer a matching speaker — scored like the `roles`/`moods` tags: a boost on match, a
  low floor (never an exclude) on mismatch, neutral when untagged. So a gendered line is
  a *preference*, never a requirement — no character is ever left without lines. Use it
  sparingly; most ambience is gender-neutral.
- **Pronoun tokens** resolve from the **speaker's** gender (neutral default):

  | Token | male | female | neutral |
  |---|---|---|---|
  | `%heshe%`   | he  | she   | they  |
  | `%himher%`  | him | her   | them  |
  | `%hisher%`  | his | her   | their |
  | `%manwoman%`| man | woman | one   |

  Pronouns are speaker-only (not target-aware), and have no capitalized variants — phrase
  lines so the pronoun isn't sentence-initial.

## Addressing other speakers

Inside a **duo** or **group**, a line can name another cast member with `%target%`
(*"Well said, Captain."*) or `%targetfull%` for the full name. The engine resolves the
addressed character — in a duo the other speaker, in a group the speaker who just spoke
(a random other on the first line) — and `%target%` renders a **varied short form** of
their name (the prefix alone, the first name, prefix + first, or the full name) so
address feels natural rather than repetitive.

These two tokens are **chain-only**: in a single-speaker line there is no one to address,
so they fall back to a neutral vocative (*"friend"*, *"traveler"*, …) and never render a
literal `%target%`.

## Roles, personalities, areas

These three identity vocabularies are each defined in **exactly one table** in
`AzerothChatter/data/traits.lua` (required as `rosterDefs`). To add or change one, edit
only that table — no engine changes needed.

- **`ROLES`** (civic/occupation archetypes). Each entry has name `prefixes`, a
  roster-frequency `weight`, an optional `moodBias`, and a default `area` affinity:
  `guard`, `citizen`, `vendor`, `innkeeper`, `adventurer`, `soldier`, `mage`, `priest`,
  `craftsman`, `farmer`, `sailor`, `noble`, `drunkard`, `urchin`.
- **`PERSONALITIES`** (mood descriptors). Each carries a roster-frequency `weight`, maps
  to a pool of name epithets, and doubles as a line-selection tag:
  `warm`, `gruff`, `cheerful`, `weary`, `wry`, `boastful`, `nervous`, `solemn`,
  `greedy`, `kindly`, `bitter`, `dreamy`, `brave`, `cowardly`, `gossipy`.
- **`AREAS`** (locale affinities):
  `city`, `rural`, `battlefield`, `coast`, `wilderness`, `road`.

At generation a character's `area` is biased (~65%) toward its role's default area, else
picked at random — so the roster reads as roughly role-typed without being rigid. How
the `area` affinity interacts with line tags is covered in
[authoring.md → The area tag](authoring.md#the-area-tag).

## Trait weighting & correlation

Roles and personalities are **not** rolled with a flat coin — each carries a base
`weight` so the cast reads like a real population: common folk dominate (citizens and
farmers are common, nobles rare), and pleasant tempers (`kindly`, `warm`) outnumber dour
ones (`cowardly`, `dreamy`). Every weight is `> 0`, so no trait is ever globally
impossible.

Traits also **correlate** at generation. The engine rolls gender and home city first,
then biases role and mood off them via small affinity maps in `data/traits.lua`:

- **Role → mood** — a craftsman skews `gruff`, a soldier `brave`, a priest `solemn`/`kindly`.
- **Gender / faction** — light skews (e.g. Horde a touch more martial).
- **Home city** — a resident's locale tilts their role and mood, so an Ironforge native
  is likelier a gruff smith and a Darnassus native a dreamy priest.

Two config knobs in `AzerothChatter.lua` govern the correlation layer:

- **`enableTraitCorrelation`** (default `true`) — turn it **off** for the pre-feature
  behavior: roles still use their base `weight`, but personality is a uniform draw and
  home city tilts nothing.
- **`traitCorrelationStrength`** (default `1.0`) — scales every correlation toward
  neutral; `1.0` is as authored, `0` collapses back to pure base weights (no role/gender/
  faction/city tilt). Base role and personality weights are always honored regardless.

Home city is still a **flat draw** — locale shapes *who* a resident is, not *how often*
each capital appears.

### Future hook: zone-specific chatter

In v1 a character's `area` is a **static affinity** assigned once at generation. The
code carries a **documented seam** (a commented `FUTURE HOOK` at the `area` assignment in
`generateCharacter`) for a later version to derive a character's *effective* area from a
**real player's current zone**, enabling true zone-specific chatter (e.g. battlefield
lines while players are in a contested zone) without changing the selection engine.
