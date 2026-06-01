# ActiveChat — Code Review

> **Implementation status (all code suggestions applied).** The engine was modularised
> and the fixes below landed. `npcTalk.lua` went 1860→~1036 lines; new modules:
> `config.lua` (all knobs), `context.lua` (time/event/season cache + resolvers),
> `data/pools.lua` (token vocabulary), `data/roster_defs.lua` (roster identity tables).
> Done: §1.1 GetGameTime comments corrected · §1.2 defensive `emit` team filter ·
> §1.3 require-path comment + docs · §1.4 `dt` rename, on-load `PrintInfo`, `buildItems`
> cursor removed · §2.1 `renderTokens` dispatch pass · §2.2 event-burst clearly tagged
> optional (kept inline — too coupled to extract) · §2.3 `normalize*` collapsed to
> `normalizeWeightedSet` · §3 `pools`/`roster_defs`/`context` extracted. Verified: all 7
> modules compile; runtime smoke test (4k ticks, real chatter loaded off-context) shows
> no token leaks, both factions broadcast with zero cross-faction leak, context cache
> populates, load line fires. **Only remaining non-code item: §4 repo hygiene** (drop the
> committed skill-eval workspace, consolidate tooling) — left to your discretion.

Scope: `ActiveChat/npcTalk.lua` (engine, ~1860 lines), `context_map.lua`, `npc_name.lua`,
`talk_text/gen_manifest.py`, repo layout. Chatter file `npc_text.lua` and `docs/` were
not opened (per CLAUDE.md). All three Lua files compile cleanly (`lupa` syntax check passes).

Overall this is a well-built, carefully-guarded codebase. Every external API touch is
capability- and `pcall`-guarded, the fallback invariant ("no silent characters, no errors")
is consistently honored, and the comments mostly explain *why*. The notes below are
refinements, not alarms — there are no crashes lurking.

---

## 1. Correctness / ALE conventions

### 1.1 `GetGameTime()` is real wall-clock seconds, not an in-game clock — FIX COMMENTS
`nowMs()` and `refreshCtx` decompose `os.date("*t", GetGameTime())` into hour/month, and
the comments repeatedly call this "the in-game clock … never a real date" (lines ~528,
683–691). In AzerothCore `GetGameTime()` returns the current Unix timestamp, so
`os.date("*t", …)` yields the **server's real local time** (and timezone). Functionally the
code still gets a valid 0–23 hour and 1–12 month, so time/season context works — but:

- "Night lines fire at night" actually means *the server host's* night, in its OS timezone.
- The README/context docs imply an in-fiction clock; that promise isn't kept.

Action: correct the comments (and docs) to say "server real time", or, if an accelerated
in-game day is wanted, source it from a different value. Low effort, prevents future
confusion. Not a runtime bug.

### 1.2 `GetPlayersInWorld(team)` — correct, but under-documented; add a guard comment
`emit()` calls `GetPlayersInWorld(team)` with `team` 0/1 to route faction-only lines. Stock
Eluna/ALE's signature is `GetPlayersInWorld(team = TEAM_NEUTRAL, onlyGM = false)`, so this
**is correct** — `0`→Alliance, `1`→Horde. Worth knowing the skill's quick-reference lists it
as no-arg; if a future ALE build ever drops the team param, every `alliance`/`horde` line
would silently leak cross-faction. Cheap insurance: filter defensively, e.g.
`if p:GetTeam() == team then …`, or at least leave a comment pinning the expected signature.

### 1.3 `require("npc_text")` resolves a file in `talk_text/` — fragile path assumption
`npc_text.lua` lives in `talk_text/` but is loaded as `require("npc_text")` (line 839); same
for the flat `require("npc_name")` / `require("context_map")`. This only works because
mod-ale adds script subdirectories to `package.path`. It's fine today, but it's an implicit
dependency on ALE's loader config — and it matters for §3 (if you split the engine into a
`data/` subdir, the new `require`s rely on the same behavior). Consider documenting the
assumption, or use explicit `require("talk_text.npc_text")` style once you've confirmed how
your loader maps it.

### 1.4 Minor
- `local t` inside `refreshCtx` (line 686) shadows the module-level state table `t`
  (`t.conv`, `t.d`, `t.cc`). Harmless (the inner scope never needs the outer `t`) but a
  footgun — rename the decomposition local to `dt`/`clock`.
- The script is **silent on load**. Given how much is capability-guarded and falls back
  quietly, a single `PrintInfo("ActiveChat loaded: %d alliance / %d horde candidates")` would
  make "is it even running / did context init?" answerable from the worldserver log.
- `buildItems` still builds a `[0] = {1,1}` cursor that its only caller (`taggedItems`)
  immediately discards — a vestige of the pre-conversation-state design. Drop it.

---

## 2. Lua style & quality

### 2.1 `renderTokens` — replace the 50-line `gsub` wall with one dispatch pass (highest-value change)
`renderTokens` runs ~50 sequential `string.gsub` calls on every emitted line, each a full
string scan, whether or not the token is present. It's not a hot path (chat fires every
1–20 s), so this is about **maintainability**, not speed:

- CLAUDE.md documents a 3-step ritual to add a token (add pool/helper, add a `gsub` line,
  use it) and warns about orphan tokens. A single-pass dispatch removes step 2 entirely and
  makes orphan detection automatic.
- The current ordering is load-bearing-by-luck: `%event%` is gsub'd before `%nextevent%`/
  `%lastevent%`. They don't actually collide (the patterns are anchored by `%`), but a
  future `%…event%` token could. A dispatch table is collision-proof.

Suggested shape:

```lua
local tokenResolvers = {
    zone = selectRandomZone, instance = selectRandomInstance, -- …
    city = function(_, speaker) return cityFor(speaker) end,
    event = function(item, _, ctx) return resolveEvent(item, ctx) end,
    season = function(_, _, ctx) return resolveSeason(ctx) end,
    -- …
}
local function renderTokens(txt, speaker, ctx, item)
    return (txt:gsub("%%(%w+)%%", function(tok)
        local f = tokenResolvers[tok]
        return f and f(item, speaker, ctx) or ("%" .. tok .. "%")  -- unknown: leave intact
    end))
end
```

This also subsumes the ~45 near-identical `selectRandomX` one-liners (they can stay as the
resolver values, or collapse into `function() return pick(pool) end`). Net: ~90 lines of
boilerplate gone, one obvious place to register a token, and the "orphan token" class of bug
becomes structurally impossible.

### 2.2 The `enableEventBurst` machinery is disabled dead weight
`fireEventBurst`, `eventBurstPool`, the forward-declared local, and the diff-tracking in
`refreshCtx` (~80 lines) exist for a feature that's off by default (`enableEventBurst =
false`). It's cleanly guarded and well-commented as a forward hook, but it's complexity an
agent must read past in the engine's most delicate function. Options: keep it (it's not
hurting anything) but tag it clearly as optional, or move it to its own module so the core
path stays lean. Flagging the cost, not demanding removal.

### 2.3 Comment density
Comments are generally excellent and explain rationale/invariants — exactly what CLAUDE.md
asks for. A few drift into restating the next line (e.g. several `-- list form` / `-- map
form` blocks across the five near-identical `normalize*` functions). Those five functions
are themselves copy-paste variants (areas/times/seasons identical; events/exclude differ
slightly); a single `normalizeWeightedSet(field, {binary=…})` helper would cut four of them
and their duplicated comments. Lower priority than §2.1.

---

## 3. Breaking up the large engine file

`npcTalk.lua` is 89 KB / 1860 lines and mixes seven concerns. CLAUDE.md's overriding goal is
"correct edits without burning context", and the file already documents an "engine map" of
exactly these seams — so splitting is well-motivated *if* done by `require` (the project
already uses `require` for its three data files, so the pattern is established and proven).

**Recommended, in priority order (highest value / lowest risk first):**

1. **`data/pools.lua`** — the ~350 lines of static vocabulary tables (zones, instances,
   herbs, ores, gems, fish, npcs, bosses, … through weathers) **plus** their `selectRandomX`
   helpers. This is the single best split: it's pure, rarely-edited data that an agent
   editing *engine logic* never needs in context, and the move is near-zero-risk (return one
   table, `require` it). Roughly halves the engine file on its own.
2. **`data/roster_defs.lua`** — `AREAS`, `ROLES`, `PERSONALITIES`, `allianceCities`/
   `hordeCities`, the color palette `t.cc`. Same rationale: tuning data, not logic.
3. **`context.lua`** — `ctx`, `refreshCtx`, `nearestEvents`, `readEventSchedule`, the
   resolvers, `context_map` wiring. Self-contained and the most "read-only when editing
   scoring/conversation" of the logic modules.

Stop there for now. The remaining clusters (normalization/`makeItem`/scoring;
roster/character generation; conversation/render/emit) are more entangled through shared
upvalues and config flags — splitting them means threading a `config` module (the
`enable*`/`*Strength`/timer locals) through every module, which is a real refactor with real
bug surface. The data extractions (1–2) get you most of the context-budget win for almost
none of the risk.

**Caveats for any split:**
- Confirm `require` resolution for whatever directory you place modules in (see §1.3). Keep
  the new files either flat beside `npcTalk.lua` or verify the loader walks `data/`.
- The whole engine is wrapped in `if enableScript then … end`. Extracted modules run at
  `require` time regardless of that flag; keep them side-effect-free (pure data / function
  definitions) so requiring them while the script is "off" does nothing observable.
- Re-run the `lupa` compile check + a smoke `require` after each extraction.

---

## 4. Directory structure & repo hygiene

Current top level mixes the deliverable (`ActiveChat/`), docs, and unrelated tooling/artifacts.

- **Skill-eval artifacts are committed into the game repo.** `.agents/skills/azerothcore-
  ale-scripting-workspace/iteration-1/**` (benchmark.json, grading.json, per-eval `with_skill`/
  `without_skill` outputs) are tracked — that's skill-*development* output, not part of
  ActiveChat. Recommend removing it from this repo (or moving the skill to its own repo and
  keeping only `SKILL.md` + `references/` if it's meant to ship with the project).
- **Scattered tooling.** `gen_manifest.py` sits in `talk_text/` while `docs/plans/_luacheck.py`
  sits under docs. Consider a single `tools/` dir for both, so build/lint helpers aren't
  interleaved with content and planning docs.
- **`._*` AppleDouble files** appear in the working tree but are correctly gitignored
  (`._*`) and *not* tracked — no action needed; noted so it's not mistaken for a problem.
  Consider also adding `.DS_Store`.
- The `ActiveChat/` script folder itself is clean and logical: engine + small data files at
  the root, bulk content isolated in `talk_text/` with its manifest + generator. The §3
  `data/` split would slot in naturally here.

---

## Summary — suggested order of work

1. Fix the `GetGameTime` "in-game clock" comments/docs (§1.1) — 10 min, prevents
   misunderstanding.
2. Refactor `renderTokens` to a single dispatch pass (§2.1) — biggest maintainability win,
   removes the documented token-adding ritual and the orphan-token bug class.
3. Extract `data/pools.lua` (+ optionally `roster_defs.lua`, `context.lua`) (§3) — halves the
   engine file's context cost at low risk.
4. Add a defensive team filter / signature comment in `emit` (§1.2) and an on-load
   `PrintInfo` (§1.4).
5. Repo hygiene: drop the committed skill-eval workspace, consolidate tooling (§4).

No correctness bugs that would crash or silence the script were found; the guarding and
fallback discipline throughout is genuinely solid.
