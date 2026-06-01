# CLAUDE.md — ActiveChat

Guidance for AI agents working in this repo. The overriding goal is **correct edits
without burning context** — this codebase has one very large data file that must
stay out of the context window unless you are specifically editing it.

## What this is

ActiveChat is a "Lively World Chat" system for an AzerothCore (WotLK 3.3.5) server,
written as ALE/Eluna Lua. It makes a lazily-grown roster of fictional NPC characters
emit ambient world chat — gossip, weather, rumor, lore — gated by faction, time of
day, season, and active in-game holidays.

## Files (and how much to load)

The module lives under `AzerothChatter/`. `AzerothChatter.lua` is the primary
entry point and holds all config at the top.

| File | Size | Load it? |
|---|---|---|
| `AzerothChatter/AzerothChatter.lua` | ~3 KB | Yes — entry point + all tunable knobs (flags, intervals, caps, strengths). Edit values here. |
| `AzerothChatter/logic/chatter.lua` | ~47 KB / ~1.0k lines | Yes — the engine: parsing, scoring, roster, conversation, render/emit, timers. |
| `AzerothChatter/logic/context.lua` | ~19 KB | Time/event/season cache (`ctx`, `refreshCtx`) + the `%event%`/`%season%`/`%timeofday%` resolvers. Load when touching context logic. |
| `AzerothChatter/data/tokens.lua` | ~17 KB | Only when editing `%token%` vocabulary — placeholder pools + their `selectRandom*` accessors. |
| `AzerothChatter/data/traits.lua` | ~4 KB | Roster identity tables (`AREAS`, `ROLES`, `PERSONALITIES`, home cities, colours). |
| `AzerothChatter/data/context.lua` | ~4 KB | Yes — small context vocabulary/maps. |
| `AzerothChatter/data/names.lua` | ~6 KB | Yes — name pools. |
| `AzerothChatter/data/chatter.lua` | **~315 KB / 1.5k lines** | **No — see below.** |
| `AzerothChatter/meta/chatter.manifest.md` | tiny | Yes — read this *instead* of the chatter file. |
| `AzerothChatter/tools/` | small | `gen_manifest.py` (regenerate the manifest), `lua_check.py` (syntax-check). |
| `docs/`, `docs/plans/` | large | **No — only when explicitly told to.** |

### Hard rules

- **Do not read `data/chatter.lua`** unless the task is specifically to add or
  modify chatter lines. It is ~315 KB of pure content and will blow your context
  budget. To understand its shape, read `meta/chatter.manifest.md` instead.
- **Do not read anything under `docs/`** unless the user explicitly points you there.
  The design rationale you'll usually need is already inline in `logic/chatter.lua`.
- **When working from a plan file, do not load finished phases into context.** Every
  plan file carries a compact summary of completed phases at the top — read that, then
  jump straight to the phase being worked on. Keep that summary up to date as phases
  complete (and follow the "remove plans after implementation" rule below).

## The chatter file — working without loading it

`data/chatter.lua` returns one table with three faction pools, each holding
`{ lines, duos, groups }`:

- `lines` — single-speaker strings.
- `duos` — two-speaker alternating chains.
- `groups` — rotating multi-speaker chains.

Entries are either bare strings (untagged, fire anywhere) or tables carrying tags
(`roles`, `moods`, `areas`, `times`, `seasons`, `events`, `eventWindow`,
`notTimes`/`notSeasons`/`notEvents`, `weight`, `cooldown`, `chain`). Tags are parsed
by `makeItem` in `logic/chatter.lua`; see that function for the normalized item shape.

**The manifest** (`meta/chatter.manifest.md`) records pool counts, the `%token%`
vocabulary, the tag keys in use, and approximate per-pool start lines — enough to
reason about the content without opening it. Regenerate it after any chatter edit:

```bash
cd AzerothChatter
python3 tools/gen_manifest.py      # needs: pip3 install lupa --break-system-packages
```

### Editing chatter (the one time you open `data/chatter.lua`)

1. Use the manifest to locate the right pool and its line range.
2. Open `data/chatter.lua` with a bounded read around that range — avoid reading the
   whole file. Append/edit entries following the existing tag shape.
3. Any `%token%` you use must already be handled by `renderTokens` in `logic/chatter.lua`
   (the manifest lists the valid set). Don't invent new tokens without adding the
   matching substitution.
4. Rerun `gen_manifest.py` and syntax-check (below).

## Editing tokens

Token substitution runs in a single pass in `renderTokens` (`logic/chatter.lua`): one
`string.gsub(txt, "%%(%w+)%%", …)` dispatches each `%token%` through the
`tokenResolvers` table (defined just above `renderTokens`). Each entry maps a token
name to a resolver called as `f(speaker, ctx, item)` — a `pools.selectRandom*`
accessor (from `data/tokens.lua`) or a context resolver from `logic/context.lua`
(`resolveEvent`, `resolveSeason`, `resolveTimeOfDay`, …). To add a token: add its pool
+ accessor in `data/tokens.lua` (or a resolver in `logic/context.lua`), add ONE line to
`tokenResolvers`, then use it in chatter — no per-token gsub plumbing. An unmapped `%token%` is left intact (visible,
never crashes), so orphans don't error. Context-aware tokens (`%event%`, `%season%`,
`%timeofday%`, `%nextevent%`, `%lastevent%`) resolve from the `ctx` cache and fall
back to random when context is off or unavailable — preserve that fallback invariant.

## Module map (so you can jump to the right file, not scroll)

The engine is split across `require`d modules. mod-ale adds the module dir **and its
subdirs** to `package.path`, so modules are required by **dotted, directory-qualified
names** (`require("data.tokens")`, `require("logic.context")`). The qualification is
load-bearing: `data/chatter.lua` vs `logic/chatter.lua` and `data/context.lua` vs
`logic/context.lua` share a basename, so a bare `require("chatter")`/`require("context")`
would be ambiguous. If a split module ever fails to load, confirm that loader
behaviour first.

- `AzerothChatter.lua` (`require("AzerothChatter")`) — entry point + every tunable
  flag/value. Single source of truth; `logic/chatter.lua` and `logic/context.lua` each
  pull what they need into locals. **Change behaviour here.**
- `data/tokens.lua` (`pools`) — `%token%` vocabulary + `selectRandom*` accessors; the
  engine never indexes the raw tables.
- `data/traits.lua` (`rosterDefs`) — `AREAS`/`ROLES`/`PERSONALITIES`, home cities,
  colour palette. `roleKeys`/`moodKeys` are derived from these in the engine.
- `data/context.lua` (`ctxMap`) — small context vocabulary/maps (eventId→name,
  month→season, neutral events) consumed by `logic/context.lua` and the event-burst.
- `data/names.lua` — NPC display-name source pools.
- `logic/context.lua` (`context`) — the time/event/season cache (`ctx`, `refreshCtx`,
  `nearestEvents`, schedule read) and the `%event%`/`%nextevent%`/`%lastevent%`/
  `%season%`/`%timeofday%` resolvers. The engine captures `context.ctx` once (it's
  mutated in place) and registers its `fireEventBurst` via `context.setEventBurstHook`.

Then within `logic/chatter.lua`: config + module wiring → tag normalization (`normalize*`,
`makeItem`, `buildItems`) → character roster (`generateCharacter`, `resolveSpeaker`,
`pickCharacter`) → line scoring (`scoreLine` and its `*Factor` functions, which read
`ctx` + the context flags) → conversation state (`nextLine`, `assembleCast`) →
rendering & emission (`tokenResolvers`/`renderTokens`, `formatWorld`, `emit`, `speak`)
→ optional event-burst (default off) → timers (`CreateLuaEvent`).

## Verify before finishing

These files load via ALE's `require`, so a plain `lua` runner isn't here, but syntax
checks well with `lupa` via `tools/lua_check.py`:

```bash
cd AzerothChatter
python3 tools/lua_check.py AzerothChatter.lua logic/chatter.lua logic/context.lua \
  data/tokens.lua data/traits.lua data/context.lua data/names.lua data/chatter.lua
```

After chatter edits, also confirm no orphan tokens (every `%token%` in the chatter is
handled by `renderTokens`, and vice-versa) — `gen_manifest.py` surfaces the token
list for this check.

Always update relevant docs after any edits.

## Style

When editing comments, keep them compact: explain *why* (non-obvious rationale,
invariants), not *what* the next line plainly does. Avoid restating code, and avoid
references to internal phase/plan numbers — they age badly and add noise.

Remove plans after they have been implemented leaving a very compact note in place.
