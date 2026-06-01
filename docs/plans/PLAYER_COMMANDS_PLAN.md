# In-Game Player Commands for ActiveChat — SHIPPED

> Retired plan, condensed to a done-note. Players can now spawn and inspect roster
> characters in-game via `.ac` commands. Out-of-character tooling, not chatter: every
> reply is private to the requester (`SendBroadcastMessage`), never World chat.
> User-facing behavior lives in [../characters.md](../characters.md#spawning--inspecting-characters-in-game-ac-commands)
> and [../config.md](../config.md#player-commands).

## What shipped (Phase 1 — 2026-06-01)

- **Factory refactor.** `generateCharacter(faction)` is now a thin wrapper over a new
  `createCharacter(opts)` (`logic/chatter.lua`). `opts` (all optional): `faction`,
  `role`, `personality`, `area`, `gender`, `name`. Any missing field is rolled exactly
  as before — the no-override path is byte-for-byte identical in RNG order and
  registration, so **ambient lazy growth is unchanged**: `opts.faction` short-circuits
  the coin-flip (`or`), validation does only table lookups (no RNG), and each
  `if (not field)` branch takes the original rolling path in the original order. A
  supplied override replaces that field's roll. Validation rejects unknown
  role/mood/area/gender/faction (returns `nil, errKey`); a supplied `name` colliding
  with the live roster is auto-suffixed (` 2`, ` 3`, …). Trait-membership sets
  (`roleSet`/`moodSet`/`areaSet`/`genderSet`/`factionSet`) derive from the same key
  lists the pickers use, so new vocab auto-validates.
- **Command surface** (`RegisterPlayerEvent(42, …)`, claims a leading `ac` token,
  `return false` to swallow; non-`ac` commands pass through; `player` nil from console
  ignored):
  - `.ac who <name>` — case-insensitive exact, then prefix; ambiguous prefixes list
    candidates; otherwise a compact trait dump.
  - `.ac list [faction]` — one line per character, capped at 40 + `+N more`.
  - `.ac help` — usage; states the ephemeral (in-memory, restart-discarded) nature.
  - `.ac create k=v …` — arg form (`faction`/`role`/`mood`(=personality)/`gender`/
    `area`/`name="…"`), quoted-name aware; invalid trait lists the valid set.
  - `.ac create` (no args) — stepwise gossip wizard (`RegisterPlayerGossipEvent(menu, 2,
    …)`, menu id `0xACC0`): Faction → Role (`roleKeys`) → Personality (`moodKeys`) →
    Gender → Area (`AREAS`) → Confirm (rolled name + Spawn + re-roll). Reads the live
    key lists directly so new vocab appears automatically. Custom names are arg-form
    only; the wizard rolls + re-rolls.
- **Guards.** `playerCreateGmOnly` (GM gate, `IsGameMaster`/`IsGM`/`GetGMRank` fallback),
  `playerCreateLimit` (per-login-session create count), and the shared `maxCharacters`
  cap (refuses cleanly when full). Per-player gossip scratch (`pcreate[guid]`) +
  create-count cleared on `RegisterPlayerEvent(4, …)` (logout). Whole block + hooks gated
  on `enablePlayerCommands` and `enableScript` (no-op when off).
- **Config** (`AzerothChatter.lua`): `enablePlayerCommands=true`,
  `playerCreateGmOnly=false`, `playerCreateLimit=5`.

## Open decisions — resolved

- **Who may create** — open to all players, throttled by `playerCreateLimit`;
  `playerCreateGmOnly` flips to GM-only if abused. (As planned default.)
- **Cap accounting** — player creations **share** `maxCharacters` with ambient spawns
  (simplest, no separate counter). The reserved-slice alternative is left as a noted
  comment at the cap check in `doCreate`, not implemented.
- **Custom names from gossip** — skipped; gossip rolls + re-rolls, custom names are
  arg-form only.

## Verification

- `tools/lua_check.py` clean on all module files.
- Offline (lupa, ALE globals + a fake player stubbed): hooks register (42/4/gossip-2);
  `createCharacter` honors role/gender overrides with a gender-correct name, registered
  exactly once; `.ac who`/`.ac list`/invalid-trait/unknown-subcommand/name-dedup/
  session-limit/logout-reset/full gossip-wizard spawn all pass.
- In-game testing (live ALE `player`/gossip API) still recommended as the final check.
