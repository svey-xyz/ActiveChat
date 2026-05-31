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
| `ActiveChat/npcTalk.lua` | ~89 KB / ~2.2k lines | Yes — the engine. Read what you need. |
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

Token substitution is centralized in `renderTokens` (`npcTalk.lua`). Each token is
one `string.gsub` call backed by a `selectRandomX` helper or a context resolver
(`resolveEvent`, `resolveSeason`, `resolveTimeOfDay`, …). To add a token: add its
source pool/helper, add the `gsub` line in `renderTokens`, then use it in chatter.
Context-aware tokens (`%event%`, `%season%`, `%timeofday%`, `%nextevent%`,
`%lastevent%`) resolve from the `ctx` cache and fall back to random when context is
off or unavailable — preserve that fallback invariant.

## Engine map (so you can jump, not scroll)

Data pools & `selectRandomX` helpers → context cache (`ctx`, `refreshCtx`) →
tag normalization (`normalize*`, `makeItem`, `buildItems`) → character roster
(`generateCharacter`, `resolveSpeaker`, `pickCharacter`) → line scoring
(`scoreLine` and its `*Factor` functions) → conversation state (`nextLine`,
`assembleCast`) → rendering & emission (`renderTokens`, `formatWorld`, `emit`,
`speak`) → timers (`CreateLuaEvent`). Config flags are at the top of the file.

## Verify before finishing

These files load via ALE's `require`, so a plain `lua` runner isn't here, but syntax
checks well with `lupa`:

```bash
cd ActiveChat
python3 -c "from lupa import LuaRuntime; L=LuaRuntime(); [L.compile(open(f).read()) for f in ['npcTalk.lua','context_map.lua','npc_name.lua']]; print('OK')"
```

After chatter edits, also confirm no orphan tokens (every `%token%` in the chatter is
handled by `renderTokens`, and vice-versa) — `gen_manifest.py` surfaces the token
list for this check.

## Style

When editing comments, keep them compact: explain *why* (non-obvious rationale,
invariants), not *what* the next line plainly does. Avoid restating code, and avoid
references to internal phase/plan numbers — they age badly and add noise.
