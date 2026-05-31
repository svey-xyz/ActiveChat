# Plan: In-Game Player Commands for ActiveChat

> Status: **planned**. Distinct from `PLAYER_INTERACTION_PLAN.md` (that's
> in-character *reactions* to player chat; this is *out-of-character tooling* — dot
> commands that inspect and seed the roster). Depends on the structured character
> model in `CHARACTERS_PLAN.md` (esp. Extension A: `gender`/`nameParts`), since
> creation lets players choose those traits.

## Goal

Two `.` commands, served from `npcTalk.lua`:

1. **Create a character** — a player spawns a roster character, choosing from the
   available traits (faction, role, personality, area, gender, and optionally a name).
   Unspecified traits are filled randomly. The character joins the in-memory roster and
   can speak immediately, like any generated one.
2. **Inspect a character** — given a name (or a pick from the current roster), print
   that character's traits to the requesting player.

Both are debugging/worldbuilding affordances, **not** in-world chatter — output goes to
the requesting player only, plainly formatted, not into World chat.

## Engine seam (what we build on)

- `generateCharacter(faction)` already does the full trait roll + registration
  (`roster` / `rosterByFaction` / `usedNames`). Creation is "the same, but with
  caller-supplied overrides."
- `ROLES` / `PERSONALITIES` / `AREAS` are the canonical trait vocabularies — the menus
  enumerate these, so the command stays in sync with the engine automatically.
- `rosterAtCap(faction)` enforces `maxCharacters`; player-created characters must
  respect it (or draw from a separate small allowance — see open decisions).
- ALE command/gossip hooks (verify exact event IDs against your mod-ale build via the
  `azerothcore-ale-scripting` skill): `RegisterPlayerEvent(PLAYER_EVENT_ON_COMMAND, fn)`
  fires on `.`-prefixed input and returns `false` to swallow the command; player gossip
  via `player:GossipMenuAddItem` / `player:GossipSendMenu` + `RegisterPlayerGossipEvent`
  drives the trait-picker UI.

## New factory: `createCharacter(opts)`

Refactor `generateCharacter` so the trait-rolling body takes an optional overrides
table; `generateCharacter(faction)` becomes `createCharacter({faction=faction})`:

```lua
-- opts (all optional except resolved faction): faction, role, personality,
--   area, gender, name. Missing fields are rolled exactly as today.
local function createCharacter(opts)
  opts = opts or {}
  local faction     = opts.faction     or (math.random() < 0.5 and "alliance" or "horde")
  local role        = opts.role        or pickRoleWeighted()
  local personality = opts.personality or moodKeys[math.random(#moodKeys)]
  local gender      = opts.gender      or rollGender()           -- from CHARACTERS_PLAN Ext. A
  local area        = opts.area        or biasedArea(role)       -- existing role→area bias
  local name        = opts.name        or generateName(faction, role, personality, gender)
  -- …assemble, validate name uniqueness, register in roster/rosterByFaction, return
end
```

Validation: reject unknown role/mood/area/gender (the menus only offer valid ones, but
a typed-arg form must guard); dedupe a supplied `name` against `usedNames`; refuse if
`rosterAtCap(faction)` and no player allowance remains.

## Command surface

Use a single namespaced command prefix so it's one hook and discoverable:

```
.ac create                 -> opens the gossip trait-picker (recommended UX)
.ac create <k=v> [<k=v>…]   -> arg form, e.g. .ac create faction=horde role=guard
                              mood=gruff gender=male area=city name="Old Borin"
.ac who <name>             -> print traits of the named roster character
.ac list [faction]         -> list current roster (name — role/mood/area), optional filter
.ac help                   -> usage
```

`RegisterPlayerEvent(PLAYER_EVENT_ON_COMMAND, …)`: match a leading `ac` token, dispatch
the subcommand, `return false` to swallow it (so it doesn't error as an unknown GM
command). Anything not starting with `ac` passes through untouched.

### Creation UX — gossip trait-picker (recommended)

`.ac create` opens a player gossip menu that walks the trait vocabularies, one step per
trait, then spawns:

1. **Faction** → Alliance / Horde.
2. **Role** → enumerate `roleKeys` (Guard, Citizen, Vendor, …).
3. **Personality** → enumerate `moodKeys`.
4. **Gender** → Male / Female / Neutral.
5. **Area** → enumerate `AREAS`.
6. **Confirm** → shows the rolled name + chosen traits; "Spawn" calls
   `createCharacter(opts)`; an option to re-roll the name.

Each step stores the partial selection in a per-player scratch table
(`pcreate[guid] = {...}`), cleared on confirm/cancel/logout. Because the menu reads
`roleKeys`/`moodKeys`/`AREAS` directly, adding a role or mood to the engine adds it to
the picker with no extra wiring. (Name entry from gossip is awkward; default to a
rolled name with a re-roll button, and allow a custom name only via the arg form.)

### Inspection output

`.ac who <name>` finds the character in `roster` (case-insensitive exact, then prefix
match; if ambiguous, list candidates) and sends the requester a compact dump:

```
[ActiveChat] Sister Maelara — alliance priest, female
  personality: solemn   area: city   home: Stormwind (Elwynn Forest)
  chattiness: 0.72   friendliness: 0.41
```

via `player:SendBroadcastMessage`. `.ac list` prints one line per character (cap the
output, e.g. first 40 + a count) so a 128-character roster doesn't flood chat.

## Config additions (top of `npcTalk.lua`)

```lua
local enablePlayerCommands = true
local playerCreateGmOnly   = false   -- true = restrict .ac create to GMs (player:GetGMRank()/IsGameMaster)
local playerCreateLimit    = 5       -- max characters one player may spawn per session (anti-spam)
```

## Edge cases / correctness checklist

- Unknown subcommand / bad `k=v` → print `.ac help`, don't error; `return false`.
- Invalid trait value (arg form) → reject with the valid set listed; menu form can't hit
  this since it only offers valid options.
- Roster cap — player creations count against `maxCharacters`; if at cap, refuse with a
  clear message (or consume `playerCreateLimit` allowance — decide in open questions).
- Name collisions — dedupe against `usedNames`; reject or auto-suffix.
- Per-player scratch state (`pcreate`) and create-count cleared on
  `PLAYER_EVENT_ON_LOGOUT` (reuse the interaction plan's cleanup hook if both ship).
- Ephemeral by design — created characters live in memory only and vanish on restart,
  consistent with the roster's no-persistence rule. State this in `.ac help` output so
  players aren't surprised.
- Respect master switches: no-op when `enableScript`/`enablePlayerCommands` is off.
- Gossip menu IDs and `PLAYER_EVENT_ON_COMMAND`/`ON_GOSSIP` numeric IDs **must** be
  verified against the running mod-ale build (use the `azerothcore-ale-scripting` skill).

## Phased implementation

1. **Factory refactor** — `createCharacter(opts)`; `generateCharacter` delegates to it.
   Verify existing ambient spawning is unchanged (regression).
2. **Inspect** — `.ac who` / `.ac list` (read-only, lowest risk; ship first).
3. **Create (arg form)** — `.ac create k=v …` with validation + cap/limit handling.
4. **Create (gossip picker)** — the stepwise menu over `roleKeys`/`moodKeys`/`AREAS`.
5. **Logout cleanup + README** — document commands, flags, and the ephemeral nature.

## Verification

- `_luacheck.py` on `npcTalk.lua`.
- Offline: `createCharacter({role="guard", gender="female"})` yields a guard with a
  gender-correct name/prefix (depends on CHARACTERS_PLAN Ext. A) and is registered once.
- In-game: `.ac create` walks the menu and the spawned character can speak; `.ac who`
  on it prints matching traits; `.ac list` is bounded; cap/limit refuses cleanly; a
  non-`ac` command still works normally; toggle `enablePlayerCommands=false` (silent
  no-op); `playerCreateGmOnly=true` blocks a non-GM.

## Open decisions

- **Who may create** — all players vs GM-only (`playerCreateGmOnly`). Default open with
  a per-session `playerCreateLimit`; flip to GM-only if abused.
- **Cap accounting** — do player creations share `maxCharacters` with ambient spawns,
  or get a separate reserved slice so a few players can't fill the roster and starve
  ambient variety?
- **Custom names from gossip** — skip (roll + re-roll) vs add a name-entry step (more UI
  work). Default: arg form only for custom names.
