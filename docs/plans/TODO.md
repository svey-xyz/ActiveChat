# ActiveChat — Plans Backlog & Index

Cleaned-up backlog of open ideas, each turned into a concrete plan. The base
engine (characters, context-aware selection, ambient chatter) has shipped; everything
here is an **extension** on top of it. This file is the map; the linked plans hold the
detail.

## Where each idea lives

| Idea (from the brain-dump) | Plan | Section |
|---|---|---|
| Context tags on placeholder tokens (food → eggs in the morning, not meat pie) | [CONTEXT_AWARE_PLAN.md](./CONTEXT_AWARE_PLAN.md) | Extension D |
| Leading-`a` grammar inconsistency across critter/companion/drink tokens | [CONTEXT_AWARE_PLAN.md](./CONTEXT_AWARE_PLAN.md) | Extension E |
| Gendered tags | [CHARACTERS_PLAN.md](./CHARACTERS_PLAN.md) | Extension A + B |
| Tokenized names/roles ("Sister Cedric" should be gender-correct) | [CHARACTERS_PLAN.md](./CHARACTERS_PLAN.md) | Extension A |
| `%target%` — address another speaker by (short) name | [CHARACTERS_PLAN.md](./CHARACTERS_PLAN.md) | Extension C |
| Zone-specific chatter + proximity + per-area timers (drop alliance/horde/shared timers) | [ZONE_AWARE_PLAN.md](./ZONE_AWARE_PLAN.md) | whole doc |
| Multi-line conversations on their own faster timer/knob | [CONVERSATION_PACING_PLAN.md](./CONVERSATION_PACING_PLAN.md) | whole doc |
| In-game `.` commands: create a character (pick traits) / inspect a character's traits | [PLAYER_COMMANDS_PLAN.md](./PLAYER_COMMANDS_PLAN.md) | whole doc |

## Dependency graph

```
A. Structured names + gender  ─┬─> B. Gendered line tags + pronoun tokens
   (CHARACTERS Ext. A)         │
                               └─> C. %target% address token (CHARACTERS Ext. C)
                               └─> Player commands "create" (PLAYER_COMMANDS_PLAN)

E. Token article/grammar rule ───> D. Context-aware token values
   (CONTEXT_AWARE Ext. E)            (CONTEXT_AWARE Ext. D)   [same pool reshape — one pass]

Zone-aware delivery (ZONE_AWARE_PLAN) ──coordinate──> Conversation pacing
   (per-zone delivery groups)                          (key conversation state by zone)
```

Independent tracks: **{A→B,C}**, **{E→D}**, **{Zone + Pacing}**, **{Player commands
(inspect)}** can all proceed in parallel; player-command *creation* waits on A.

## Suggested build order

1. **A — structured names + gender** (foundation; unblocks B, C, and command creation).
   Smallest high-leverage change; fixes the "Sister Cedric" bug immediately.
2. **E then D — token pool reshape** (article rule first, then context tags). One pass
   over the token pools; independent of everything else.
3. **B — gendered tags + pronoun tokens** (needs A).
4. **C — `%target%`** (needs A; touches conversation cast plumbing).
5. **Conversation pacing** (small, self-contained; nice quality win; sequence before
   zone work so zone delivery can build on the pacing/conversation-state changes).
6. **Player commands** — inspect first (read-only), then create (needs A).
7. **Zone-aware chatter** (largest; reworks delivery + timers). Land last and
   reconcile conversation state with per-zone delivery groups.

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
- **Verify** — `_luacheck.py` + `phase5_verify.py` + `pass1_render_check.py` after each
  change; regenerate `npc_text.manifest.md` after any chatter edit.

## Smaller / loose items

- Capitalized pronoun variants (`%Heshe%`) only if a line needs sentence-initial
  pronouns — otherwise authors phrase around it (see CHARACTERS Ext. B).
- `AREAS` `coast`/`wilderness`/`road` currently fold into city/rural/battlefield via the
  zone map; revisit giving them their own timers once the three-timer model is proven
  (ZONE_AWARE_PLAN).
- Decide `%a% %food%` (look-ahead article) vs combined `%afood%` tokens — recommended
  `%afood%` to sidestep look-ahead (CONTEXT_AWARE Ext. E).
- Player-command cap accounting (shared vs reserved roster slice) — open decision in
  PLAYER_COMMANDS_PLAN.
