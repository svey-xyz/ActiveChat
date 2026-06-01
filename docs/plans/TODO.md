# ActiveChat — Plans Backlog & Index

Cleaned-up backlog of open ideas, each turned into a concrete plan. The base
engine (characters, context-aware selection, ambient chatter) has shipped; everything
here is an **extension** on top of it. This file is the map; the linked plans hold the
detail.

## Where each idea lives

| Idea (from the brain-dump) | Plan | Section |
|---|---|---|
| Context tags on placeholder tokens (food → eggs in the morning, not meat pie) — ✅ DONE | [CONTEXT_AWARE_PLAN.md](./CONTEXT_AWARE_PLAN.md) | Phase 8 Part A (condensed) |
| Leading-`a` grammar inconsistency across critter/companion/drink tokens — ✅ DONE | [CONTEXT_AWARE_PLAN.md](./CONTEXT_AWARE_PLAN.md) | Phase 8 Part B (condensed) |
| Gendered tags — ✅ DONE | [CHARACTERS_PLAN.md](./CHARACTERS_PLAN.md) | shipped (condensed) |
| Tokenized names/roles ("Sister Cedric" should be gender-correct) — ✅ DONE | [CHARACTERS_PLAN.md](./CHARACTERS_PLAN.md) | shipped (condensed) |
| `%target%` — address another speaker by (short) name — ✅ DONE | [CHARACTERS_PLAN.md](./CHARACTERS_PLAN.md) | shipped (condensed) |
| Weighted traits (more farmers than nobles, kindly > cowardly) + correlations (Ironforge → gruff smith) — ✅ DONE | [WEIGHTED_TRAITS_PLAN.md](./WEIGHTED_TRAITS_PLAN.md) | shipped (condensed) |
| Zone-specific chatter + proximity + per-area timers (drop alliance/horde/shared timers) | [ZONE_AWARE_PLAN.md](./ZONE_AWARE_PLAN.md) | whole doc |
| Multi-line conversations on their own faster timer/knob — ✅ DONE | [CONVERSATION_PACING_PLAN.md](./CONVERSATION_PACING_PLAN.md) | shipped (condensed) |
| In-game `.` commands: create a character (pick traits) / inspect a character's traits — ✅ DONE | [PLAYER_COMMANDS_PLAN.md](./PLAYER_COMMANDS_PLAN.md) | shipped (condensed) |

## Dependency graph

```
A. Structured names + gender  ─┬─> B. Gendered line tags + pronoun tokens
   (CHARACTERS Phase 1 Part A) │       (CHARACTERS Phase 1 Part B) [DONE]
   [DONE]                      ├─> C. %target% address token (CHARACTERS Phase 1 Part C) [DONE]
                               ├─> Player commands "create" (PLAYER_COMMANDS_PLAN)
                               └─> W. Weighted/correlated traits (WEIGHTED_TRAITS_PLAN) [DONE]
                                      read gender + homeCity; reordered generateCharacter

E. Token article/grammar rule ───> D. Context-aware token values
   (CONTEXT_AWARE Phase 8 Part B)    (CONTEXT_AWARE Phase 8 Part A)  [same pool reshape — one pass]

Zone-aware delivery (ZONE_AWARE_PLAN) ──coordinate──> Conversation pacing
   (per-zone delivery groups)                          (key conversation state by zone)
```

Independent tracks: **{A→B,C}**, **{E→D}**, **{Zone + Pacing}**, **{Player commands
(inspect)}** can all proceed in parallel; player-command *creation* waits on Part A. W
shipped first among the Part-A dependents (it reordered `generateCharacter`), so B/C and
player-command *creation* now build on the reordered, weighted generator.

## Suggested build order

1. **A — structured names + gender** — ✅ DONE. Foundation; unblocks B, C, W, and
   command creation. Fixed the "Sister Cedric" bug.
2. **W — weighted/correlated traits** — ✅ DONE. Self-contained generation-time layer;
   the cast now reads like a real population (common folk dominate, few nobles,
   kindly > cowardly, Ironforge → gruff smith). Reordered `generateCharacter` (gender +
   home city roll before role/mood), so B/C and command *creation* build on it. See the
   condensed [WEIGHTED_TRAITS_PLAN.md](./WEIGHTED_TRAITS_PLAN.md).
3. **E then D — token pool reshape** — ✅ DONE (2026-06-01). Article rule first, then
   context tags, one pass over the token pools. Added `%afood%`/`%adrink%`/`%acompanion%`/
   `%atoy%`/`%acritter%` (vowel-aware combined tokens); `selectTagged(pool, ctx)` weighted
   selector reusing the line factor helpers. See the condensed
   [CONTEXT_AWARE_PLAN.md](./CONTEXT_AWARE_PLAN.md) Phase 8.
4. **B — gendered tags + pronoun tokens** (needs A) — ✅ DONE. `genders` line tag +
   `%heshe%`/`%himher%`/`%hisher%`/`%manwoman%` speaker pronouns.
5. **C — `%target%`** (needs A; touches conversation cast plumbing) — ✅ DONE.
   `%target%`/`%targetfull%` address the other speaker; chain-only, vocative fallback.
6. **Conversation pacing** — ✅ DONE (2026-06-01). `enableBurstConversations` +
   `convLineGap`/`convMaxLines`; `runChainBurst` self-rescheduling one-shot timer runs a
   started chain at its own pacing, decoupled from ambient cadence (`st.bursting` guard
   prevents double-emission). Zone delivery must later key `t.conv` by zone bucket (compact
   ZONE NOTE left in `runChainBurst`). See the condensed
   [CONVERSATION_PACING_PLAN.md](./CONVERSATION_PACING_PLAN.md).
7. **Player commands** — ✅ DONE (2026-06-01). `.ac who`/`list`/`help` (inspect) +
   `.ac create` (arg form and gossip trait-picker); `createCharacter(opts)` factory that
   `generateCharacter` now delegates to. Behind `enablePlayerCommands`/`playerCreateGmOnly`/
   `playerCreateLimit`; ephemeral, player creations share `maxCharacters`. See the condensed
   [PLAYER_COMMANDS_PLAN.md](./PLAYER_COMMANDS_PLAN.md).
8. **Zone-aware chatter** (largest; reworks delivery + timers). **Next / only remaining
   track.** Land last and reconcile conversation state with per-zone delivery groups —
   note the `ZONE NOTE` left in `runChainBurst` (conversation pacing) about keying
   `t.conv` by zone bucket.

## Cross-cutting invariants to preserve (every plan)

- **No character ever goes silent** — untagged lines stay global fallbacks; every new
  scoring factor returns `1.0` when untagged (gender, etc.), never a hard-exclude
  except the existing `area`/`time`/`season`/`event` rules.
- **No orphan tokens** — any new `%token%` (`%target%`, `%heshe%`, `%afood%`, …) is
  added to `renderTokens` **and** `gen_manifest.py`'s token set, and the orphan-token
  check stays green.
- **Capability/flag guards** — every feature behind a config flag, falling back to
  current behavior when off or when an ALE API is missing (the context engine's
  discipline).
- **Ephemeral roster** — no persistence; player-created characters vanish on restart.
- **Verify** — `tools/lua_check.py` + `phase5_verify.py` + `pass1_render_check.py` after each
  change; regenerate `meta/chatter.manifest.md` after any chatter edit.

## Smaller / loose items

- Capitalized pronoun variants (`%Heshe%`) only if a line needs sentence-initial
  pronouns — otherwise authors phrase around it (see CHARACTERS Phase 1 Part B).
- `AREAS` `coast`/`wilderness`/`road` currently fold into city/rural/battlefield via the
  zone map; revisit giving them their own timers once the three-timer model is proven
  (ZONE_AWARE_PLAN).
- Decide `%a% %food%` (look-ahead article) vs combined `%afood%` tokens — recommended
  `%afood%` to sidestep look-ahead (CONTEXT_AWARE Phase 8 Part B).
- Player-command cap accounting (shared vs reserved roster slice) — open decision in
  PLAYER_COMMANDS_PLAN.
