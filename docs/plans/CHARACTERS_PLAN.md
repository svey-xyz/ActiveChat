# In-Memory Characters for ActiveChat — SHIPPED

> Retired plan, condensed to a done-note. The roster of persistent-for-the-session,
> in-world personas now carries structured identity (gender + name parts), so lines can
> be gender-fit, pronouns resolve correctly, and one speaker can address another by a
> natural short name. Lazy, in-memory, no DB — discarded on every restart, unchanged.
> User-facing behavior is documented in [../characters.md](../characters.md).

## What shipped

- **Structured names + gender.** Each character carries `gender`
  (`male`/`female`/`neutral`) and `nameParts` `{prefix, first, surname, epithet}`
  alongside the finished `name` string. `buildName` rolls gender (config `genderRatio`)
  and draws an agreeing first name + role prefix, so the prefix never disagrees with the
  name (fixed *"Sister Cedric"*). First-name pools in `data/names.lua` and role prefixes
  in `data/traits.lua` are bucketed by gender; legacy flat lists still load as neutral.
- **Gendered line tags + pronoun tokens.** A `genders` line tag (parsed in `makeItem`
  beside `roles`/`moods`) is scored by `genderFactor` via the shared `matchFactor` in
  `scoreLine` — boost on match, low floor on mismatch, `1.0` untagged — so a gendered
  line is never *required*. Four speaker pronoun tokens keyed off `speaker.gender` with a
  neutral default: `%heshe%` (he/she/they), `%himher%` (him/her/them), `%hisher%`
  (his/her/their), `%manwoman%` (man/woman/one). Pronouns are speaker-only, not
  target-aware.
- **Addressing other speakers.** `nextLine` resolves a *target character* (duo → the
  other cast member; group → the prior speaker, random other on the first line; single
  line → none) and threads it through `renderTokens(txt, speaker, ctx, item, target)`.
  `addressName(c)` returns a weighted short form over `nameParts` (prefix / first /
  prefix+first / full; no-prefix folds its weight into "first alone"). Two chain-only
  tokens: `%target%` → `addressName(target)`, `%targetfull%` → `target.name`; both fall
  back to a neutral vocative pool off-chain so a mis-tagged single line never renders a
  literal token.

## Invariants preserved

- **No character ever goes silent** — every new scoring factor returns `1.0` when
  untagged; gendered lines bias, never exclude.
- **No orphan tokens** — `tools/gen_manifest.py` derives the resolver set from
  `tokenResolvers` and runs a bidirectional orphan check; the pronouns and the two
  chain-only address tokens are whitelisted so the check stays green.

## Where the code lives

- `logic/chatter.lua` — `buildName`, `generateCharacter`, `makeItem`, `scoreLine`
  (`genderFactor`), `targetForLine`, `nextLine`, `addressName`, `targetVocatives`,
  `tokenResolvers`, `renderTokens`, `speak`.
- `data/names.lua` — gendered first-name pools. `data/traits.lua` — gendered role
  prefixes. `AzerothChatter.lua` — `genderRatio`.
- `tools/gen_manifest.py` — resolver-aware orphan check; `meta/chatter.manifest.md`
  documents `%target%`/`%targetfull%` as chain-only with a vocative fallback.
