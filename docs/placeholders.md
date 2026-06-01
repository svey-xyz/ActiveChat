# Placeholders

Drop these tokens into any line and the engine swaps in a random, lore-appropriate value
each time the line is spoken. (A token used twice in one line resolves to the **same**
value both times — the pick is made once per line.)

| Token | Replaced with |
|---|---|
| `%zone%` | a random game zone (e.g. *Stranglethorn Vale*) |
| `%instance%` | a random dungeon or raid (e.g. *Blackrock Depths*) |
| `%class%` | a random player class (e.g. *Druid*) |
| `%bg%` | a random battleground (e.g. *AV*) |
| `%profession%` | a profession (e.g. *Jewelcrafting*, *Cooking*) |
| `%activity%` | a gathering/profession activity, gerund phrase (e.g. *collecting herbs*) |
| `%city%` | a capital or neutral hub (biased to the speaker's home city when `homeCityBias`) |
| `%race%` | a playable race (e.g. *Blood Elf*) |
| `%monster%` | a hostile native creature (e.g. *murloc*, *owlbeast*) |
| `%critter%` | a passive critter, **bare noun** (e.g. *deer*, *rabbit*). **Context-aware** (light seasonal bias). Use `%acritter%` for "a/an". |
| `%boss%` | a notable boss (e.g. *The Lich King*, *Ragnaros*) |
| `%consumable%` | a flask, potion, or food buff (e.g. *Fish Feast*) |
| `%item%` | a famous epic/legendary (e.g. *Shadowmourne*) |
| `%rep%` | a reputation faction (e.g. *Kirin Tor*) |
| `%mount%` | a notable mount (e.g. *Invincible*) |
| `%spell%` | a class spell/ability (e.g. *Bloodlust*) |
| `%rare%` | a rare spawn (e.g. *Time-Lost Proto-Drake*) |
| `%pvptitle%` | a PvP/achievement title (e.g. *the Kingslayer*) |
| `%emote%` | an emote action verb (e.g. *cheer*, *facepalm*) |
| `%gold%` | a random gold amount, suffixed `g` (e.g. *8500g*) |
| `%level%` | a random character level, 2–80 |
| `%event%` | the most relevant **real** holiday/world event — what's active now, else the nearest upcoming/just-past one, else a neutral phrase. **Context-aware** (no longer a random holiday). See [context.md](context.md). |
| `%nextevent%` | the **soonest upcoming** holiday/world event (or a neutral phrase if none is known). For explicit anticipation lines. |
| `%lastevent%` | the **most recently ended** holiday/world event (or a neutral phrase if none is known). For explicit aftermath lines. |
| `%season%` | the **current** in-game season (e.g. *winter*, *spring*). **Context-aware** — resolves to what's actually true now, not random. |
| `%timeofday%` | the **current** in-game time of day (e.g. *dusk*, *the small hours before dawn*). **Context-aware** — resolves to the in-game clock, not random. |
| `%shop%` | a named tavern, inn, or shop (e.g. *the Pig and Whistle Tavern*) |
| `%route%` | a travel route or method (e.g. *the Deeprun Tram*) |
| `%tale%` | a famous legend or story (e.g. *the Culling of Stratholme*) |
| `%weather%` | a weather condition (e.g. *a blizzard*, *clear skies*). **Context-aware** — biased toward the current season; used bare/descriptive so its baked article stays. |
| `%herb%` | a gatherable herb (e.g. *Frost Lotus*, *Goldclover*) |
| `%ore%` | an ore or smeltable metal (e.g. *Saronite*, *Truesilver*) |
| `%gem%` | a cut or raw gem (e.g. *Cardinal Ruby*) |
| `%fish%` | a catchable fish (e.g. *Dragonfin Angelfish*) |
| `%npc%` | a famous lore figure (e.g. *Thrall*, *Jaina Proudmoore*) |
| `%currency%` | an earned currency/badge (e.g. *Emblem of Frost*) |
| `%food%` | a tavern food, **bare noun** (e.g. *meat pie*, *Honey Bread*). **Context-aware** (morning/seasonal/event bias). Use `%afood%` for "a/an". |
| `%drink%` | a tavern drink, **bare noun** (e.g. *Thunder Ale*). **Context-aware**. Use `%adrink%` for "a/an". |
| `%title%` | a non-PvP/PvE title (e.g. *the Loremaster*, *Chef*) |
| `%tradegood%` | a crafting material (e.g. *Frostweave Cloth*, *Eternal Fire*) |
| `%companion%` | a vanity companion pet, **bare noun** (e.g. *Onyxian Whelpling*) or a proper name (*Pengu*). Use `%acompanion%` for "a/an". |
| `%enchant%` | a gear enchantment (e.g. *Mongoose*, *Crusader*) |
| `%toy%` | a novelty/fun item, **bare noun** (e.g. *Noggenfogger Elixir*). Use `%atoy%` for "a/an". |

> **In-character rule for the context tokens.** `%timeofday%`, `%season%`, `%event%`,
> `%nextevent%`, and `%lastevent%` always resolve to **fiction words only** — a
> time-of-day phrase, a season name, or a holiday name. They **never** surface a real
> clock (`22:00`), "server time", or a printed date. The time/season come from a
> *mapping* over the in-game game-time, not a displayed value.

## Articles & the `%a…%` tokens

Countable-noun pools (`%food%`, `%drink%`, `%companion%`, `%toy%`, `%critter%`) store
their values **as bare noun phrases with no leading article** — *meat pie*, not *a meat
pie*. The sentence decides the article, because English article choice is
context-dependent (*some bread* vs *a pie* vs *the ale*). So **author the article
yourself**, one of two ways:

- **`%afood%` / `%adrink%` / `%acompanion%` / `%atoy%` / `%acritter%`** — combined
  tokens that pick a value and prepend the correct **vowel-aware** *a*/*an* in one step:
  *a meat pie*, *an apple*, *an Onyxian Whelpling*. Prefer these for the indefinite
  case — they can't get *a/an* wrong, and they never prefix a **proper name** (so
  `%acompanion%` yields *Pengu*, never *a Pengu*).
- **`some %food%` / `the %drink%` / `my %companion%`** — when a different article (or
  none) fits, just write it before the bare token.

Do **not** write `a %food%` — that risks *a apple* (wrong) or, with a value that still
carried an article, *a a meat pie* (double). Use `%afood%` instead. `tools/pass1_render_check.py`
samples every `%a…%` token and fails on double-articles, *a/an* mismatches, or an
article stuck on a proper name.

## Context-aware token values

A handful of pools where context clearly matters — `%food%`, `%drink%`, `%weather%`,
`%activity%`, `%critter%` — bias their pick toward what fits *right now*, using the same
`ctx` and the same `times`/`seasons`/`events` vocabulary as context-aware **line**
selection (see [context.md](context.md)). *porridge* is likelier in the morning,
*mulled wine* in winter, *Pilgrim's pie* only during Pilgrim's Bounty. Off-context
values are hard-excluded the same way an off-context line is; untagged values fit
anywhere. **With context off or unavailable, every value scores equally — exactly
today's uniform random pick** (the fallback invariant). Abstract pools (`%item%`,
`%boss%`, `%spell%`, `%gem%`, …) stay untagged — tag only where the value implies a
context. Token-pool tags live in `data/tokens.lua`; the scoring reuses the engine's
`timeFactor`/`seasonFactor`/`eventFactor` via `selectTagged`.

## Speaker & address tokens

These resolve from the **characters in the conversation**, not a random pool. See
[characters.md](characters.md#gender-aware-lines--pronouns).

| Token | Replaced with |
|---|---|
| `%heshe%` | the **speaker's** pronoun — *he* / *she* / *they* (neutral default) |
| `%himher%` | the speaker's pronoun — *him* / *her* / *them* |
| `%hisher%` | the speaker's pronoun — *his* / *her* / *their* |
| `%manwoman%` | the speaker's noun — *man* / *woman* / *one* |
| `%target%` | the addressed cast member, **short form** (prefix, first name, or full). **Chain-only** — meaningful inside `duos`/`groups`; falls back to a vocative (*friend*, *traveler*) in a single line. |
| `%targetfull%` | the addressed cast member's **full** name. **Chain-only**, same vocative fallback as `%target%`. |

> Pronoun tokens are **speaker-only** (not target-aware) and have no capitalized
> variants — phrase lines so the pronoun isn't sentence-initial.

## Player-imitation tokens (use sparingly)

These exist for the occasional adventurer voice, but the chatter is meant to be
**civilian/guard/NPC flavor, not an imitation of real players.** Avoid LFG/LFM, grouping
requests, and gearscore/parse talk — that's the job of a playerbot module, not this
script.

| Token | Replaced with |
|---|---|
| `%role%` | *Tank*, *Healer*, or *DPS* |
| `%difficulty%` | a difficulty tag (e.g. *25-man Heroic*) |
| `%gearscore%` | a WotLK-era GearScore number, 2400–6000 |

The lists these tokens draw from live in `AzerothChatter/data/tokens.lua` (with their
`selectRandom*` accessors) and can be edited there. The numeric tokens (`%gold%`,
`%level%`, `%gearscore%`) are generated by small helper functions in the same file.
