# Code Review — ActiveChat (resolved)

A quality/conventions review of the ALE engine. **All code findings are implemented;**
this is the closing record.

## Outcome

The engine was modularised and the fixes below landed. `logic/chatter.lua` 1860 → ~1036 lines.
New modules: `AzerothChatter.lua` (all knobs), `logic/context.lua` (time/event/season cache + resolvers),
`data/tokens.lua` (token vocabulary + accessors), `data/traits.lua` (roster identity
tables). Layout and module map are documented in `CLAUDE.md`.

## Fixes applied

- **Correctness:** `emit` re-checks `p:GetTeam()` so a faction line can't leak
  cross-faction; corrected the `GetGameTime` comments (server wall-clock, not an in-game
  day); documented the `require` subdir/`package.path` assumption.
- **Lua quality:** `renderTokens` is one `gsub` + `tokenResolvers` dispatch (was ~50
  sequential gsubs); the three identical `normalize*` functions collapsed to
  `normalizeWeightedSet`; dead `[0]` cursor removed; `dt` rename (no shadow of `t`);
  on-load `PrintInfo`. Event-burst kept inline but clearly tagged optional (too coupled
  to extract cleanly).
- **Structure:** `data.tokens` / `data.traits` / `logic.context` extracted via `require`.
- **Repo hygiene:** `.DS_Store` + the skill-eval workspace added to `.gitignore`; the 23
  committed eval-artifact files were untracked (`git rm --cached`, kept on disk).

## Verification

All 7 Lua modules compile (`lupa`). Runtime smoke test (4k ticks, real chatter loaded
off-context): no unrendered tokens, both factions broadcast with zero cross-faction leak,
context cache populates, load line fires.

## Deployment note

`require("AzerothChatter"/"logic.context"/"data.tokens"/"data.traits")` relies on mod-ale
adding the module dir **and subdirs** to `package.path` (same mechanism that already loads
`data.chatter`). Dotted names are required because `data/chatter.lua` vs `logic/chatter.lua`
and `data/context.lua` vs `logic/context.lua` share basenames. Confirm with one `.reload ale`.
