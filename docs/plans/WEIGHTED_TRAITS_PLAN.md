# Plan: Weighted & Correlated Character Traits

> **Scope note.** Today the roster rolls most traits with a flat coin. Roles already
> carry a `weight`, but personalities are picked uniformly and home city is a flat
> draw, so a server is as likely to spawn a dreamy noble as a kindly farmer. This
> plan makes the cast read like a real population: common folk dominate (more farmers
> and citizens than soldiers or mages, *very* few nobles), warm/kindly tempers beat
> cowardly/dreamy ones, and traits **correlate** — an Ironforge native skews toward a
> gruff smith, a Darnassus native toward a dreamy priest. It is a generation-time
> weighting layer only: no new tokens, no chatter changes, no effect on line scoring
> or emission.

## Relevant docs

- docs/characters.md
- CHARACTERS_PLAN.md (Part A shipped `gender` + `nameParts`; this layer reads `gender`
  and `homeCity`, and reorders `generateCharacter` slightly — coordinate before B/C)

## Completed

- _(nothing yet — Phase 1 below is the whole plan)_

---

## Phases (planned)

### **Phase 1**

#### Note

> Builds directly on `generateCharacter` in `logic/chatter.lua`. The existing
> `pickRoleWeighted` (weighted roulette over `ROLES[*].weight`) is the seed of the
> mechanism — this generalizes it into one `weightedPick` used for every categorical
> trait, then layers conditional multipliers on top. All trait data stays in
> `data/traits.lua`; the engine only gains the picker and the wiring.

#### Dependencies & order

CHARACTERS Phase 1 Part A (gender + `homeCity` already on the character) is the only
prerequisite, and it has shipped. This plan is independent of CHARACTERS Parts B/C,
the token work, and zone work, but it **reorders** `generateCharacter` (home city and
gender are rolled *before* role/personality so they can condition them), so land it
before further character-generation changes. Per `TODO.md`, sequence it next, ahead of
CHARACTERS Part B. Build **Part A → Part B → Part C**.

#### Cross-cutting invariants (this plan)

- **No trait is ever globally impossible.** Every base weight stays `> 0`, so with the
  feature off, or all conditional modifiers neutralized, every role/personality can
  still appear. A conditional multiplier of `0` may exclude a trait *in one context*
  (e.g. no nobles in Thunder Bluff) — that is allowed and intentional, never global.
- **Flag-guarded, identical fallback.** Behind `enableTraitCorrelation`. Off ⇒ exactly
  today's behavior: roles weighted by `.weight`, personality uniform, home city
  uniform. Mirrors the context engine's discipline.
- **No silent characters / no orphan tokens.** This layer touches neither line
  selection nor `renderTokens`, so both base invariants are preserved by construction.

#### Part A — Global trait weights + the generic picker (foundation)

**Problem.** Personalities are drawn with `moodKeys[math.random(#moodKeys)]` — uniform,
so `dreamy` and `cowardly` are as common as `kindly`. Role weights exist but are
tuned mild (`noble = 3` is only 2.3× rarer than `citizen = 9`); the user wants common
folk to clearly dominate and nobles to be rare. And the weighting logic lives only in
`pickRoleWeighted`, with no reuse path for the other traits.

**Approach — one generic weighted picker, base weights on every categorical trait.**

1. **Add `weight` to `PERSONALITIES`** (`data/traits.lua`), parallel to `ROLES.weight`.
   Common, pleasant tempers high; rare/negative ones low:

   ```lua
   R.PERSONALITIES = {
     kindly  = { weight = 6, epithets = {...} },  warm    = { weight = 5, epithets = {...} },
     cheerful= { weight = 5, ... },               gruff   = { weight = 5, ... },
     gossipy = { weight = 4, ... },               wry     = { weight = 4, ... },
     weary   = { weight = 4, ... },               solemn  = { weight = 3, ... },
     boastful= { weight = 3, ... },               brave   = { weight = 3, ... },
     nervous = { weight = 3, ... },               bitter  = { weight = 2, ... },
     greedy  = { weight = 2, ... },               dreamy  = { weight = 2, ... },
     cowardly= { weight = 1, ... },
   }
   ```

2. **Retune `ROLES.weight`** so commoners dominate and nobles are scarce (target shape;
   tune freely): `citizen 10, farmer 8, vendor 7, guard 6, craftsman 6, innkeeper 5,
   adventurer 5, drunkard 4, urchin 4, sailor 4, soldier 3, priest 3, mage 2, noble 1`.

3. **Generalize the picker** in `logic/chatter.lua`. `weightedPick` takes a key list,
   a base-weight function, and an optional ordered list of multiplier maps
   (`{key -> factor}`, missing key ⇒ `1.0`). It subsumes `pickRoleWeighted`:

   ```lua
   -- Effective weight = base * Π(applicable modifiers). Modifiers are nil-safe and
   -- optional, so Part A calls it with none (pure base weights). A modifier may zero a
   -- weight; if EVERY weight ends up <= 0, fall back to a uniform pick so generation
   -- never stalls.
   local function weightedPick(keys, baseOf, modifiers)
     local eff, total = {}, 0
     for _, k in ipairs(keys) do
       local w = baseOf(k) or 1
       if modifiers then
         for _, m in ipairs(modifiers) do
           if m and m[k] then w = w * m[k] end
         end
       end
       if w < 0 then w = 0 end
       eff[k], total = w, total + w
     end
     if total <= 0 then return keys[math.random(#keys)] end
     local r, acc = math.random() * total, 0
     for _, k in ipairs(keys) do
       acc = acc + eff[k]
       if r <= acc then return k end
     end
     return keys[#keys]                         -- float-rounding fallback
   end
   ```

   Replace `pickRoleWeighted()` with `weightedPick(roleKeys, function(k) return ROLES[k].weight end)`
   and the uniform personality draw with
   `weightedPick(moodKeys, function(k) return PERSONALITIES[k].weight end)`.

4. **Config.** Add `enableTraitCorrelation = true` and `traitCorrelationStrength = 1.0`
   to `AzerothChatter.lua` (alias both in the engine). With the flag **off**, skip the
   personality `weight` and all Part B/C modifiers (uniform personality, base-only
   roles, uniform home city) — i.e. today's behavior. Note: base role/personality
   `weight`s authored in Part A are *always* honored; the flag governs only the
   correlation layer (Parts B/C) and whether personality uses its weight vs uniform.
   (Decide and document: simplest is base weights always on, correlation flag-gated.)

**Verification.** A sampling script (`tools/trait_weights_check.py`, lupa-loaded data +
a Python mirror of `weightedPick`) draws a large sample and asserts the *ordering*
holds within tolerance: `citizen > soldier > noble`, `kindly > cowardly`, every trait
appears at least once, and flag-off reproduces a uniform personality histogram.

#### Part B — Conditional correlations: role↔mood, gender & faction skews

**Problem.** Even with good base weights, traits are independent — a smith is no more
likely to be gruff than dreamy, and gender/faction don't tilt the cast. We want light,
authored correlations so archetypes feel coherent.

**Approach — declarative modifier tables fed into `weightedPick`.** Add bias maps to
`data/traits.lua` and stack them as the picker's `modifiers` argument. None of these
hard-exclude (multipliers, not gates), so the fallback invariant holds.

1. **Role → mood bias** on each role (the role nudges temperament):

   ```lua
   R.ROLES.craftsman.moodBias = { gruff = 2.0, dreamy = 0.5 }
   R.ROLES.priest.moodBias    = { solemn = 1.8, kindly = 1.6, boastful = 0.5 }
   R.ROLES.soldier.moodBias   = { brave = 1.8, gruff = 1.4, cowardly = 0.4 }
   R.ROLES.noble.moodBias     = { boastful = 2.0, greedy = 1.8, warm = 0.6 }
   R.ROLES.drunkard.moodBias  = { cheerful = 1.6, weary = 1.5 }
   R.ROLES.urchin.moodBias    = { nervous = 1.6, wry = 1.4 }
   -- roles without a moodBias contribute no tilt
   ```

2. **Gender skews** (light — the user flagged this as "may be interesting"):

   ```lua
   R.GENDER_BIAS = {
     male   = { roles = { soldier = 1.4, guard = 1.2, smith = 1.0 } },
     female = { roles = { priest  = 1.2 } },
     neutral= { },
   }
   ```

3. **Faction skews** (optional, subtle), e.g. Horde slightly more `soldier`/`guard`,
   Alliance slightly more `vendor`/`noble`:

   ```lua
   R.FACTION_BIAS = {
     alliance = { roles = { vendor = 1.2, noble = 1.3 } },
     horde    = { roles = { soldier = 1.2, guard = 1.2 } },
   }
   ```

**Pipeline reorder in `generateCharacter`.** Roll the conditioning traits first:

   ```
   gender   = rollGender()                      -- Part A (already shipped)
   homeCity = weightedPick(cities[faction], …)  -- Part C (flat today)
   role     = weightedPick(roleKeys, ROLES.weight,
                modifiers = { FACTION_BIAS[faction].roles, GENDER_BIAS[gender].roles,
                              CITY_BIAS[homeCity].roles })          -- city term: Part C
   mood     = weightedPick(moodKeys, PERSONALITIES.weight,
                modifiers = { ROLES[role].moodBias, GENDER_BIAS[gender].moods,
                              CITY_BIAS[homeCity].moods })          -- city term: Part C
   area     = <unchanged: role.area biased ~65%>
   ```

   `traitCorrelationStrength` scales each modifier toward 1.0 (`eff = 1 + (factor-1)*s`)
   so a single knob can soften or disable all correlations without editing tables; `s=0`
   ⇒ pure base weights, `s=1` ⇒ as authored.

**Scope discipline.** Keep modifiers few and legible — a handful per role/city, not a
full matrix over every trait. Over-biasing makes the cast feel deterministic; the goal
is *flavor*, not typecasting.

**Verification.** Extend the Part A script: assert smiths are gruff more often than the
global gruff rate, soldiers brave more often than baseline, and that `strength = 0`
collapses every conditional histogram back to the Part A (base-weight) distribution.

#### Part C — Home-city affinity matrices

**Problem.** Home city is a flat draw and influences nothing, so the dwarven and
night-elf capitals produce statistically identical residents. The user wants locale to
shape the resident — "someone from Ironforge is more likely to be a gruff smith than
someone from Darnassus."

**Approach — a `CITY_BIAS` table: city → { roles = {…}, moods = {…} }** consumed by the
`role`/`mood` calls in the Part B pipeline (the `CITY_BIAS[homeCity]` modifier term).
One entry per home city in `data/traits.lua` (`allianceCities`/`hordeCities`):

   ```lua
   R.CITY_BIAS = {
     -- Alliance
     ["Ironforge"]    = { roles = { craftsman = 3.0, soldier = 1.6, noble = 0.4 },
                          moods = { gruff = 2.5, boastful = 1.4, dreamy = 0.4 } },
     ["Darnassus"]    = { roles = { priest = 2.2, mage = 1.6, soldier = 0.5 },
                          moods = { dreamy = 2.0, solemn = 1.6, warm = 1.3, gruff = 0.5 } },
     ["Stormwind"]    = { roles = { guard = 1.5, vendor = 1.3, noble = 1.4 },
                          moods = { boastful = 1.3, brave = 1.3 } },
     ["The Exodar"]   = { roles = { priest = 1.8, mage = 1.5 },
                          moods = { solemn = 1.5, kindly = 1.4, weary = 1.3 } },
     -- Horde
     ["Orgrimmar"]    = { roles = { soldier = 1.8, guard = 1.5, noble = 0.4 },
                          moods = { gruff = 1.8, brave = 1.5, boastful = 1.4, dreamy = 0.4 } },
     ["Thunder Bluff"]= { roles = { farmer = 2.0, priest = 1.6, adventurer = 1.4 },
                          moods = { solemn = 1.6, warm = 1.5, kindly = 1.4, greedy = 0.5 } },
     ["Undercity"]    = { roles = { mage = 1.6, craftsman = 1.4 },
                          moods = { bitter = 2.0, solemn = 1.5, wry = 1.4, cheerful = 0.4 } },
     ["Silvermoon City"]={ roles = { noble = 1.6, mage = 1.8 },
                          moods = { boastful = 1.6, greedy = 1.5, wry = 1.4, gruff = 0.5 } },
   }
   -- A city with no entry contributes no tilt (treated as {}).
   ```

   The "Ironforge gruff smith" effect emerges from two stacking modifiers — the city
   pushes `craftsman`+`gruff`, and (Part B) `craftsman` itself pushes `gruff` — without
   any single overpowering weight.

**Optional — weighted home-city draw.** If desired, give `allianceCities`/`hordeCities`
their own pick weights (e.g. capitals over smaller hubs) via the same `weightedPick`;
default flat preserves current behavior. Keep optional; cities are roughly equal today.

**Scope discipline.** Author all eight home cities or none — a half-filled table makes
some capitals biased and others flat, which reads as a bug. Keep each city to a few
strong, recognizable affinities.

**Verification.** Extend the script: assert P(role=craftsman | Ironforge) and
P(mood=gruff | Ironforge) both exceed their Darnassus counterparts and the global rate,
that no city zeroes a trait it shouldn't, and that flag-off / `strength = 0` makes home
city statistically irrelevant to role and mood again.
