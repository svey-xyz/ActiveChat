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

---

## Phases (planned)

### **Phase 8**

#### Note

> Added after context-aware *line selection* shipped. Two related upgrades to the
> **token value pools** (the `local foods = {…}` etc. tables and their
> `selectRandomX` helpers in `npcTalk.lua`). Today line *eligibility* is
> context-aware, but the value a `%token%` resolves to is still a flat uniform random
> pick. Both parts below change how a token *value* is chosen — they do not
> touch the scorer.

#### Dependencies & order

A and B share the token-pool reshape — do them in one pass (**E's bare-noun rule
first, then D's tags on the cleaned values**). Both are independent of the
CHARACTERS_PLAN extensions and the zone work. See `TODO.md` for cross-plan ordering.

#### Part A — Context-aware token values

**Problem.** `%food%` in a morning line can resolve to *"a meat pie"*; `%food%` at a
festival ignores the festival. The token pools are flat lists picked uniformly by
`selectRandomFood()` and friends, with no notion of when/where a value fits. We want
*"eggs"* and *"porridge"* to be likelier than *"a meat pie"* in the morning, and
seasonal/event foods to surface during their window — using the **same `ctx`** the
scorer already maintains.

**Approach — tag the pool entries, add a context-weighted selector.** Reshape the flat
pools into the same string-first tagged shape the chatter file uses (a bare string =
untagged/global; a table = value + tags), reusing the existing `times`/`seasons`/
`events` vocabulary so authors learn one tag system:

```lua
local foods = {
  "a meat pie", "Smoked Salmon", "Honey Bread",        -- untagged: fit anywhere
  { "Spiced Beef Jerky", times={"night","dusk"} },
  { "Honey Bread",       times={dawn=3, morning=3} },  -- graded toward morning
  { "eggs and bacon",    times={"dawn","morning"} },
  { "Pilgrim's pie",     events={"Pilgrim's Bounty"} },
  { "Spice Bread",       seasons={"winter"} },
}
```

A shared `selectTagged(pool, ctx)` replaces the per-pool `selectRandomX` bodies:

1. Score each entry like a line but value-only: a tagged entry that hard-excludes on
   the current `ctx` bucket (e.g. a `night`-only food at midday) is dropped; graded
   tags bias the weight; untagged entries always stay in at weight 1 (the fallback
   guarantee, same as untagged lines).
2. Weighted-random pick over survivors. With context off / `ctx` unavailable, every
   entry scores 1 → behaves exactly like today's uniform random.

Implement once, generically, then point each `selectRandomFood/Drink/…` at it with its
pool. Reuse the existing `normalizeTimes`/`normalizeSeasons`/`normalizeEvents` +
`timeFactor`/`seasonFactor`/`eventFactor` helpers (factor them to take an explicit
tag-table arg so both lines and token entries can call them). **Cost:** a handful of
lookups per token resolved — negligible, and only on pools you actually tag.

**Scope discipline.** Only tag entries where context clearly matters (food, drink,
weather, activity, maybe critter). Leave abstract pools (item, boss, spell, gem)
untagged — over-tagging just adds noise. This mirrors the README's standing rule for
lines: *tag only when the content implies a context.*

**Interaction with Part B.** A tagged food entry still carries its leading
article per the grammar rule below (`"a meat pie"`, `"eggs and bacon"`), so the two
parts share the same pool reshape — do them together.

#### Part B — Article / grammar consistency rule for tokens

**Problem.** Some pool values bake in a leading article and some don't, with no rule,
so chatter grammar is inconsistent depending on which value is drawn:

- `foods`: *"a meat pie"*, *"a Dalaran Brownie"* (article) vs *"Smoked Salmon"*,
  *"Honey Bread"* (none).
- `drinks`: *"a tankard of ale"*, *"a Bottle of Pinot Noir"* vs *"Thunder Ale"*.
- `companions`: *"a Mechanical Squirrel"*, *"an Onyxian Whelpling"* (article) vs
  *"Pengu"*, *"Lil' K.T."* (proper names, correctly none).
- `critters`: bare nouns throughout (*"deer"*, *"rabbit"*) — needs an article at the
  call site (*"a deer wandered by"*).

A line author can't know whether `%food%` will produce *"a meat pie"* or *"meat pie,"*
so *"I fancy some %food%"* and *"I fancy a %food%"* are both wrong half the time.

**The rule (pick one and apply it pool-wide).** Recommended: **store every pool value
as a bare noun phrase with NO leading article**, and let the *chatter* supply the
article, because English article choice is context-dependent (*"some bread"* vs *"a
pie"* vs *"the ale"*) and only the sentence knows which fits.

1. **Strip baked-in articles** from `foods`/`drinks`/`companions`/`toys`/`currencies`/
   `consumables` etc. (*"a meat pie"* → *"meat pie"*, *"an Onyxian Whelpling"* →
   *"Onyxian Whelpling"*). Leave proper names alone (*"Pengu"*, *"Mr. Pinchy"*).
2. **Add an `%a%` article helper token** for the *"a/an"* case, so authors get
   correct *a*/*an* without guessing: `%a% %food%` → *"a meat pie"* / *"an apple"*.
   `%a%` looks ahead at the *next rendered token's* first letter (vowel → *an*) — so it
   must resolve **after** the noun tokens, or be implemented as a small wrapper that
   renders the following token and prepends the right article. Simplest robust form:
   a dedicated combined token per pool, e.g. `%afood%` → "a/an " + a food value,
   computed in one step where the article and the chosen value are known together.
   Author `%a% %food%` reads nicer; `%afood%` is easier to get correct — **decide one**
   (recommend `%afood%`/`%adrink%`/`%acompanion%`/`%acritter%` combined tokens; they
   sidestep the look-ahead entirely).
3. **Proper-name pools** (companions like *Pengu*, toys, named items) must NOT take an
   article — author them as `%companion%` bare, or split into a proper-name sub-pool
   so the `%a…%` token never prepends an article to a name.

**Tie to Part A.** Both reshape the same pools, so land the article cleanup in the
same pass as the context tags. After the change, audit the chatter file for `%food%` /
`%drink%` / `%critter%` / `%companion%` usages and fix any that assumed a baked-in
article (now they should read `%afood%` or `some %food%` as appropriate). The
`gen_manifest.py` token list + orphan-token check must learn any new `%a…%` tokens.

**Verification.** A render pass (extend `pass1_render_check.py`) that samples each
article-bearing token in context and flags double-articles (*"a a meat pie"*),
missing articles (*"I ate meat pie"*), or *a/an* mismatches (*"a apple"*).


