# Weighted & Correlated Character Traits — SHIPPED

> Retired plan, condensed to a done-note. The cast now reads like a real population:
> common folk dominate (few nobles), pleasant tempers beat dour ones, and traits
> correlate (role↔mood, gender, faction, home city). Generation-time only — no tokens,
> chatter, or line-scoring changes. User-facing behavior is documented in
> [../characters.md](../characters.md#trait-weighting--correlation).

## What shipped

- **Base weights** on every `ROLES` and `PERSONALITIES` entry in `data/traits.lua`
  (commoners common, nobles rare; kindly/warm common, cowardly/dreamy rare). Every
  weight `> 0`, so no trait is ever globally impossible.
- **Generic picker** `weightedPick(keys, baseOf, modifiers)` in `logic/chatter.lua`
  (replaced the old `pickRoleWeighted`): effective weight = base × Π applicable modifier
  factors; nil-safe; negatives clamp to 0; an all-zero total falls back to a uniform
  pick so generation never stalls.
- **Correlation layer.** `generateCharacter` rolls gender + homeCity first, then role,
  then mood, feeding bias maps through `weightedPick`:
  - `ROLES[*].moodBias` (role nudges temperament), `GENDER_BIAS`, `FACTION_BIAS`, and
    `CITY_BIAS` (all 8 home cities) in `data/traits.lua`.
  - Each modifier passes through `scaleModifier(m)` (`eff = 1 + (factor-1)*s`,
    `s = traitCorrelationStrength`) so one knob softens or disables all correlations.
- **Config** (`AzerothChatter.lua`): `enableTraitCorrelation = true`,
  `traitCorrelationStrength = 1.0`. Flag-off ⇒ base role weights only + uniform
  personality + flat home city (today's pre-feature behavior); `s = 0` ⇒ pure base
  weights with no correlation tilt.
- **Home-city *draw* stays flat (intentional).** Cities are roughly equal, so only
  `CITY_BIAS` *affinity* tilts a resident's role/mood — draw frequency is unweighted.
- **Verify:** `tools/trait_weights_check.py` (lupa-loaded data + a Python mirror of
  `weightedPick`/`scaleModifier`/`CITY_BIAS`; 20/20 ordering & flag-off/`s=0` collapse
  checks pass). `tools/lua_check.py` clean.
