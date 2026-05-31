# Plan: In-Memory Characters for ActiveChat

> **Scope note.** This introduces a roster of **persistent-for-the-session, in-world
> personas** that speak the ambient World chatter. They are generated
> **lazily** — created on demand as chatter is emitted, up to a configurable
> `maxCharacters` cap — live entirely in Lua memory, and are discarded on every
> server reset — **no DB, no creatures, no per-character persistence** (consistent
> with the philosophy already established in `PLAYER_INTERACTION_PLAN.md`). The point
> is to make the city feel populated by *recurring* voices with consistent identity
> and mood, rather than an endless stream of one-off random names.

# Extensions (planned)

> Added after the base character system shipped. These build on the existing
> `generateCharacter` / `buildName` / `renderTokens` machinery in `npcTalk.lua`.
> The common thread: the character currently stores only a finished `name` *string*,
> which is the root cause of three separate problems (mismatched gendered prefixes,
> no pronoun control, no clean way to shorten a name for address). Storing the
> **name as structured parts plus a gender** fixes all three at once, so do that
> first — the rest depend on it.

## Extension A — Structured name parts + `gender` (foundation)

**Problem.** `buildName` returns a flat display string assembled from a gendered
prefix (`ROLES[role].prefixes`), a first name, an optional surname, and an optional
epithet, but throws the parts away. Two bugs fall out of that:

1. **Gender-mismatched prefixes.** The `{Role} {first}` pattern pairs a prefix with
   a first name at random, so the priest prefixes `Father`/`Sister`/`Brother` and
   noble `Lord`/`Lady`/`Baron` and farmer `Goodman`/`Goodwife` land on the wrong
   first name — *"Sister Cedric"*, *"Lady Thorgrim"*.
2. **No pronoun source.** A line can't say "a man like me" / "she's the one" because
   nothing knows the speaker's gender.

**Change the character model** (`generateCharacter`) to carry both the gender and the
name components, not just the finished string:

```lua
local character = {
  name      = "Sister Maelara",     -- still the display string (built from parts)
  gender    = "female",             -- "male" | "female" | "neutral"
  nameParts = {                     -- NEW: kept for address/pronoun use
    prefix  = "Sister",             -- role/title prefix, or nil
    first   = "Maelara",            -- always present
    surname = nil,                  -- or "Stormbringer"
    epithet = nil,                  -- or "the Brave"
  },
  -- …faction, role, personality, area, homeCity, chattiness, friendliness, color
}
```

**Gender assignment & gendered name pools.** Split the first-name pools in
`npc_name.lua` by gender so the chosen gender drives a matching first name:

```lua
-- npc_name.lua
alliance = { male = {"Aldric","Cedric",…}, female = {"Eleanor","Rowena",…},
             neutral = {"Sprocket","Cogwhistle",…} },   -- gnome/utility names can stay neutral
horde    = { male = {…}, female = {…}, neutral = {…} },
surnames = { … },                                       -- unchanged, gender-agnostic
```

`generateCharacter` rolls `gender` first (e.g. 48/48/4 male/female/neutral, tunable),
then `buildName(faction, role, personality, gender)` draws the first name from that
gender's sub-pool. Back-compat: if a pool has no gender sub-tables (a flat list),
treat the whole list as `neutral` and assign gender randomly — mirrors the existing
`t.init` fallback that treats a flat name list as the surname pool.

**Gender the role prefixes.** Restructure `ROLES[*].prefixes` from a flat list to a
gender map so `buildName` can pick a prefix that agrees with the character's gender —
this is the direct *"Sister Cedric"* fix:

```lua
priest = { prefixes = { male={"Father","Brother"}, female={"Sister"},
                        neutral={"Acolyte"} }, weight = 4, area = "city" },
noble  = { prefixes = { male={"Lord","Baron"},     female={"Lady"},
                        neutral={"Noble"} },        weight = 3, area = "city" },
farmer = { prefixes = { male={"Goodman"},          female={"Goodwife"},
                        neutral={"Farmer"} },       weight = 6, area = "rural" },
-- genderless roles (guard "Guardsman", soldier "Sergeant", …) keep all three
-- buckets pointing at the same neutral list, OR buildName falls back to neutral.
```

`buildName` change: in the `{Role} {first}` branch, pick from
`prefixes[gender] or prefixes.neutral or <any>`; in every branch, record the chosen
parts into `nameParts`. Epithets (`PERSONALITIES`) stay gender-neutral — no change.

**Verification.** Extend `phase5_verify.py` (or a small new check) to assert no
female first name carries a male-only prefix and vice-versa across a large sample of
`generateCharacter` calls; confirm `gender` is always set and `nameParts.first` is
always non-empty.

## Extension B — Gendered line tags + pronoun tokens

With `gender` on the character, lines can be gender-fit and pronoun tokens resolve
correctly.

**`genders` line tag** (parallel to `roles`/`moods`, parsed in `makeItem`):
`{"female"}` / `{"male"}`. Omit = any gender (the global default). Scoring adds a
`genderFactor` built exactly like `matchFactor(item.roles, char.role)` — a boost on
match, a low floor (not exclude) on mismatch, `1.0` when untagged — so the fallback
invariant is preserved (a gendered line is never *required*). Wire it into
`scoreLine` alongside the role/mood factors. Use sparingly; most ambience is
gender-neutral.

**Pronoun tokens** resolved in `renderTokens` from `speaker.gender` (and, once
Extension C lands, from the target's gender for replies):

| Token | male | female | neutral |
|---|---|---|---|
| `%heshe%`   | he  | she | they  |
| `%himher%`  | him | her | them  |
| `%hisher%`  | his | her | their |
| `%manwoman%`| man | woman | one |

Each is one `string.gsub` keyed off `speaker.gender`, following the same pattern as
the other resolvers in `renderTokens`. Capitalized variants (`%Heshe%`) only if a
line needs a sentence-initial pronoun; otherwise authors phrase around it.

## Extension C — Addressing other speakers (`%target%`)

**Goal.** In a duo/group, let one speaker name another cast member — *"Well said,
Captain."* / *"Cedric, you're dreaming."* — and let a reply name the speaker who just
spoke. Today `renderTokens(txt, speaker, ctx, item)` has no access to the rest of the
cast, so this needs light plumbing, not a redesign.

**Plumbing.** `nextLine` already holds the fixed `st.cast`, the current `speaker`,
and `st.prevName`. Resolve a *target character* there and pass it to `renderTokens`:

- **Duo:** the target is the other cast member (B addresses A and vice-versa).
- **Group:** the target is the previous speaker (`st.prevName`'s character) so a line
  reads as a reply; fall back to a random other cast member on the first line.
- **Single `line`:** no target → `%target%` falls back to a neutral form (see below).

Extend the signature to `renderTokens(txt, speaker, ctx, item, target)` and add the
gsubs. `speakerForLine` already tracks `prevName`; keep a parallel `prevChar` (or look
the character up in `st.cast` by name) so the target is a full character, not just a
string — needed for its `nameParts` and `gender`.

**Short forms (don't always use the full name).** Using `nameParts` from Extension A,
add `addressName(targetChar)` returning a weighted variant so address feels natural
and varied — *Captain Cedric* can be addressed as *Captain*, *Cedric*, or the full
name:

```
addressName(c) -- weighted pick over the parts that exist:
  prefix alone   ("Captain", "Sister")        ~30%  (only if nameParts.prefix)
  first alone    ("Cedric", "Maelara")        ~45%
  prefix + first ("Captain Cedric")           ~15%  (only if prefix)
  full name      (c.name)                     ~10%
  -- if no prefix, redistribute its weight to "first alone"
```

**Tokens.**

- `%target%` → `addressName(target)` (varied short form); fallback when there is no
  target: drop to a neutral vocative like *"friend"*, *"traveler"*, *"stranger"* (a
  small pool) so a mis-tagged single line never renders a literal `%target%`.
- `%targetfull%` → `target.name` (full), same fallback pool.

Pronoun tokens (Extension B) can also be made target-aware for third-person replies
(*"%heshe% knows the way"* referring to the prior speaker) — but keep speaker-pronouns
the default; only resolve target-pronouns for explicitly third-person reply lines if
you add a tag for it. Simpler first cut: ship `%target%`/`%targetfull%` only.

**Authoring.** `%target%` is meaningful only inside `duos`/`groups`. Document in
`npc_text.manifest.md`'s token list and the README that it's chain-only and falls
back to a vocative elsewhere. Add `%target%` to `renderTokens` *and* the
`gen_manifest.py` token set so the orphan-token check stays honest.

## Dependencies & order

A (structured names + gender) is the foundation. B (gendered tags + pronouns) needs
A's `gender`. C (`%target%`) needs A's `nameParts`. Build **A → B → C**. All three
preserve the "no character ever goes silent / no orphan token" invariants the base
system guarantees. See `TODO.md` for the cross-plan ordering.
