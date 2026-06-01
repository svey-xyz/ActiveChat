# Plan: Context-Aware Chatter for ActiveChat

> **Scope note.** By default the chatter doesn't just read like Azeroth — it reads like Azeroth *right
> now*. Night lines fire at night, festival lines fire during the actual festival, and
> season talk tracks the real game state instead of a coin flip.

## Relevant docs

- docs/context.md

## Completed

- **Phase 1 — DONE (2026-05-30).** `ctx` + refresh, time only.
- **Phase 2 — DONE (2026-05-30).** `timeFactor` in the scorer + `times` tag.
- **Phase 3 — DONE (2026-05-30).** Active events: `GetActiveGameEvents()` sourcing,
	`eventFactor` in the scorer, the `events` tag, and active-only `%event%`.
- **Phase 5 — DONE (2026-05-30).** Seasons: `M.monthToSeason` map + holiday→season
  cross-check.
- **Phase 6 — DONE (2026-05-30), event-burst part; dispatcher-wiring DEFERRED.**
  Optional event-activation burst behind `enableEventBurst` (default `false`).
- **Phase 4 — DONE (2026-05-30).** Nearest events: startup `game_event` schedule
  snapshot.
- **Phase 7 — DONE (2026-05-30), documentation.** README only — no engine/content
  change.
- **Phase 8 — DONE (2026-06-01).** Token-pool reshape (value selection, not the
  scorer). **Part B (articles):** stripped baked-in articles from food/drink/companion/
  toy/currency pools (proper names left bare); added combined, vowel-aware
  `%afood%`/`%adrink%`/`%acompanion%`/`%atoy%`/`%acritter%` tokens that prepend *a*/*an*
  in one step and never prefix a proper name. Audited chatter and converted
  indefinite-article uses (`a %food%` → `%afood%`, sentence-initial ones reworded).
  **Part A (context values):** reshaped food/drink/weather/activity/critter pools into
  string-first tagged shape (`{ value=…, times/seasons/events=… }`); added
  `selectTagged(pool, ctx)` + engine-injected `scoreTokenEntry` (via `pools.setTagScorer`),
  reusing the SAME `timeFactor`/`seasonFactor`/`eventFactor` (refactored to take explicit
  tag tables). Fallback invariant preserved: context off / ctx unavailable ⇒ uniform.
  Abstract pools left untagged. New tool `tools/pass1_render_check.py` (a/an + double-
  article verify); manifest regenerated, orphan check green (unresolved=0). Docs:
  `placeholders.md` (new `%a…%` tokens + article rule + context-tag note), `context.md`.

> **All phases complete.** Engine/content in `logic/chatter.lua`, `data/tokens.lua`,
> `data/chatter.lua`; vocabulary/maps in `data/context.lua`; the event-burst is the
> shared `ctx` seam for the player-interaction roadmap.


