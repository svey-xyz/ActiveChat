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

| File | Size | Load it? |
|---|---|---|
| `ActiveChat/npcTalk.lua` | ~47 KB / ~1.0k lines | Yes — the engine: parsing, scoring, roster, conversation, render/emit, timers. |
| `ActiveChat/config.lua` | ~3 KB | Yes — all tunable knobs (flags, intervals, caps, strengths). Edit values here. |
| `ActiveChat/context.lua` | ~19 KB | Time/event/season cache (`ctx`, `refreshCtx`) + the `%event%`/`%season%`/`%timeofday%` resolvers. Load when touching context logic. |
| `ActiveChat/data/pools.lua` | ~17 KB | Only when editing `%token%` vocabulary — placeholder pools + their `selectRandom*` accessors. |
| `ActiveChat/data/roster_defs.lua` | ~4 KB | Roster identity tables (`AREAS`, `ROLES`, `PERSONALITIES`, home cities, colours). |
| `ActiveChat/context_map.lua` | ~4 KB | Yes — small context vocabulary/maps. |
| `ActiveChat/npc_name.lua` | ~6 KB | Yes — name pools. |
| `ActiveChat/talk_text/npc_text.lua` | **~315 KB / 1.5k lines** | **No — see below.** |
| `ActiveChat/talk_text/npc_text.manifest.md` | tiny | Yes — read this *instead* of the chatter file. |
| `docs/`, `docs/plans/` | large | **No — only when explicitly told to.** |

### Hard rules

- **Do not read `talk_text/npc_text.lua`** unless the task is specifically to add or
  modify chatter lines. It is ~315 KB of pure content and will blow your context
  budget. To understand its shape, read `talk_text/npc_text.manifest.md` instead.
- **Do not read anything under `docs/`** unless the user explicitly points you there.
  The design rationale you'll usually need is already inline in `npcTalk.lua`.
- **When working from a plan file, do not load finished phases into context.** Every
  plan file carries a compact summary of completed phases at the top — read that, then
  jump straight to the phase being worked on. Keep that summary up to date as phases
  complete (and follow the "remove plans after implementation" rule below).

## The chatter file — working without loading it

`npc_text.lua` returns one table with three faction pools, each holding
`{ lines, duos, groups }`:

- `lines` — single-speaker strings.
- `duos` — two-speaker alternating chains.
- `groups` — rotating multi-speaker chains.

Entries are either bare strings (untagged, fire anywhere) or tables carrying tags
(`roles`, `moods`, `areas`, `times`, `seasons`, `events`, `eventWindow`,
`notTimes`/`notSeasons`/`notEvents`, `weight`, `cooldown`, `chain`). Tags are parsed
by `makeItem` in `npcTalk.lua`; see that function for the normalized item shape.

**The manifest** (`npc_text.manifest.md`) records pool counts, the `%token%`
vocabulary, the tag keys in use, and approximate per-pool start lines — enough to
reason about the content without opening it. Regenerate it after any chatter edit:

```bash
cd ActiveChat
python3 talk_text/gen_manifest.py      # needs: pip3 install lupa --break-system-packages
```

### Editing chatter (the one time you open `npc_text.lua`)

1. Use the manifest to locate the right pool and its line range.
2. Open `npc_text.lua` with a bounded read around that range — avoid reading the
   whole file. Append/edit entries following the existing tag shape.
3. Any `%token%` you use must already be handled by `renderTokens` in `npcTalk.lua`
   (the manifest lists the valid set). Don't invent new tokens without adding the
   matching substitution.
4. Rerun `gen_manifest.py` and syntax-check (below).

## Editing tokens

Token substitution runs in a single pass in `renderTokens` (`npcTalk.lua`): one
`string.gsub(txt, "%%(%w+)%%", …)` dispatches each `%token%` through the
`tokenResolvers` table (defined just above `renderTokens`). Each entry maps a token
name to a resolver called as `f(speaker, ctx, item)` — a `pools.selectRandom*`
accessor (from `data/pools.lua`) or a context resolver from `context.lua`
(`resolveEvent`, `resolveSeason`, `resolveTimeOfDay`, …). To add a token: add its pool
+ accessor in `data/pools.lua` (or a resolver in `context.lua`), add ONE line to
`tokenResolvers`, then use it in chatter — no per-token gsub plumbing. An unmapped `%token%` is left intact (visible,
never crashes), so orphans don't error. Context-aware tokens (`%event%`, `%season%`,
`%timeofday%`, `%nextevent%`, `%lastevent%`) resolve from the `ctx` cache and fall
back to random when context is off or unavailable — preserve that fallback invariant.

## Module map (so you can jump to the right file, not scroll)

The engine is split across `require`d modules (mod-ale adds the script dir **and its
subdirs** to `package.path`, so bare `require("pools")`/`require("context")` resolve
files in `data/` and the root alike):

- `config.lua` — every tunable flag/value. Single source of truth; `npcTalk.lua` and
  `context.lua` each pull what they need into locals. **Change behaviour here.**
- `data/pools.lua` (`pools`) — `%token%` vocabulary + `selectRandom*` accessors; the
  engine never indexes the raw tables.
- `data/roster_defs.lua` (`rosterDefs`) — `AREAS`/`ROLES`/`PERSONALITIES`, home cities,
  colour palette. `roleKeys`/`moodKeys` are derived from these in the engine.
- `context.lua` (`context`) — the time/event/season cache (`ctx`, `refreshCtx`,
  `nearestEvents`, schedule read) and the `%event%`/`%nextevent%`/`%lastevent%`/
  `%season%`/`%timeofday%` resolvers. The engine captures `context.ctx` once (it's
  mutated in place) and registers its `fireEventBurst` via `context.setEventBurstHook`.

Then within `npcTalk.lua`: config + module wiring → tag normalization (`normalize*`,
`makeItem`, `buildItems`) → character roster (`generateCharacter`, `resolveSpeaker`,
`pickCharacter`) → line scoring (`scoreLine` and its `*Factor` functions, which read
`ctx` + the context flags) → conversation state (`nextLine`, `assembleCast`) →
rendering & emission (`tokenResolvers`/`renderTokens`, `formatWorld`, `emit`, `speak`)
→ optional event-burst (default off) → timers (`CreateLuaEvent`).

## Verify before finishing

These files load via ALE's `require`, so a plain `lua` runner isn't here, but syntax
checks well with `lupa`:

```bash
cd ActiveChat
python3 -c "from lupa import LuaRuntime; L=LuaRuntime(); [L.compile(open(f).read()) for f in ['npcTalk.lua','config.lua','context.lua','data/pools.lua','data/roster_defs.lua','context_map.lua','npc_name.lua']]; print('OK')"
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
