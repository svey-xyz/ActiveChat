# Plan: Zone-Aware Chatter for ActiveChat

> **Scope note.** Make World chatter *regional* instead of a single global megaphone:
> players in different zones see different characters and lines, hear voices biased
> toward their location, and get per-area cadence (a city is chatty, the wilds sparse,
> a battlefield bursty). This reworks both **delivery** (who sees a line) and the
> **timer architecture** (what drives a tick) — the largest of the open extensions, so
> land it after the smaller ones. Builds on the shipped character system
> (`CHARACTERS_PLAN.md`) and context engine (`CONTEXT_AWARE_PLAN.md`).

## Relevant docs

- docs/context.md
- CHARACTERS_PLAN.md (home zone extends the character model)
- CONTEXT_AWARE_PLAN.md (reuses `ctx.area` and the nil-safe map discipline)
- CONVERSATION_PACING_PLAN.md (conversation state must key by delivery group)
- docs/characters.md (the shipped trait-weighting layer — `AREA_ROLE_BIAS` reuses its
  `*_BIAS` map convention and the `scaleModifier` strength form)

## Completed

- None yet — all phases below are planned.

---

## Phases (planned)

### **Phase 1 — Per-zone delivery + per-area timers**

#### Note

> **Problem (the gap today).** World chat is global. `emit(audience, msg)` either calls
> `SendWorldMessage` (everyone) or loops `GetPlayersInWorld(team)` and
> `SendBroadcastMessage`s the *whole* team — so every online player sees the same
> speaker say the same line regardless of where they are. A character has an `area`
> affinity (`city`/`rural`/…) and a `homeCity`, but nothing keys chatter to the
> *listener's* location. We want:
>
> 1. **Zone-localized delivery** — players in different zones see *different* characters
>    and lines, so the world feels regional rather than one global megaphone.
> 2. **Proximity bias** — a player is likelier to hear a character whose home
>    zone/region is near them, and likelier to hear chatter *about* a city they're near.
> 3. **Per-area timers** — independent cadence for `city` / `rural` / `battlefield`
>    ambience (a city is busy and chatty; the wilds are sparse; a battlefield is bursty),
>    replacing the current per-faction (`alliance` / `horde` / `shared`) timer split,
>    which is no longer needed — faction becomes a per-delivery gate, not a timer axis.
> 4. **Area-appropriate voices** — the *role* doing the talking should suit the locale.
>    We shouldn't hear a noble holding forth in the wilderness, or a farmer on a
>    battlefield; soldiers and guards dominate contested zones, farmers and travelers the
>    rural roads, nobles and vendors the cities. A per-area role weight on the speaker pick.

**Current architecture (what we change).**

- **Timers** (`logic/chatter.lua` bottom): `alliance`-driver on `talk_time` carrying
  `shared`+`alliance`; `horde`-driver on `faction_talk_time` carrying `horde`. Faction
  is the timer axis.
- **`emit`** routes by the line's `audience` tag to world/team broadcast. No zone
  filter.
- **Character** carries `area` + `homeCity` but no zone/region.
- **`cityFor(speaker)`** biases `%city%` to the *speaker's* home city; the listener's
  location is never consulted.

#### Dependencies & order

Largest extension; land after the smaller ones. Conversation chains must stay within
**one** delivery group, so coordinate with `CONVERSATION_PACING_PLAN.md` — per-channel
conversation state must be keyed by zone bucket, not just faction, once delivery is
per-zone. See `TODO.md` for cross-plan ordering.

#### Part A — Zone classification maps (`data/context.lua`)

Zone tables belong with the other tuning maps. Add three, keyed off the existing
`zones`/`cities` vocabulary and the AzerothCore zone IDs ALE exposes via
`player:GetZoneId()`:

```lua
-- zone display name (or zone id) -> AREA bucket (one of AREAS)
M.zoneToArea = { ["Stormwind"]="city", ["Elwynn Forest"]="rural",
                 ["Wintergrasp"]="battlefield", ["Tanaris"]="wilderness", … }

-- zone -> region grouping, for proximity ("near their hometown / region")
M.zoneToRegion = { ["Elwynn Forest"]="elwynn", ["Westfall"]="elwynn",
                   ["Redridge Mountains"]="elwynn", ["Durotar"]="durotar", … }

-- zone -> nearest capital, for "chatter about a city you're close to"
M.zoneToNearestCity = { ["Elwynn Forest"]="Stormwind", ["Westfall"]="Stormwind",
                        ["Durotar"]="Orgrimmar", … }
```

Use **zone IDs** as keys (stable, locale-independent) with a name fallback. Provide a
default `"city"`/`"rural"` so an unmapped zone is never a hard error — same nil-safe
discipline as `eventIdToName`.

#### Part B — Character home zone/region

Extend `generateCharacter`: assign `homeZone` (and derive `homeRegion` via
`zoneToRegion`) biased by faction + role, the same way `homeCity` and `area` are
biased today. `homeCity` stays (it's the capital); `homeZone` is the finer-grained
origin used for proximity. The existing `area` field still drives line eligibility;
`homeZone`/`homeRegion` drive *who gets delivered to whom*.

#### Part C — Delivery model: per-zone emission

The core shift: a tick no longer means "one speaker → everyone." It means **for each
populated zone, resolve a speaker and a line appropriate to that zone, and deliver only
to the players there.**

```
tickArea(areaType):                      -- areaType ∈ {"city","rural","battlefield"}
  players = GetPlayersInWorld()          -- all online
  if none -> return                      -- keep the existing "no listeners, skip" guard
  buckets = group players by GetZoneId() where zoneToArea[zone] == areaType
  for each (zone, playersInZone) in buckets:
      region = zoneToRegion[zone]
      team   = faction majority/serverside of that zone (or per-player on send)
      -- pick a speaker biased toward this zone/region AND suited to the locale's role mix:
      speaker = resolveSpeaker(faction) with a per-character weight:
                  chattiness × proximityFactor(char, zone, region)
                             × areaRoleFactor(char.role, areaType)
      item    = pickLine(candidatesFor(faction), speaker, tick) with ctx.area = areaType
      deliver rendered line to playersInZone via SendBroadcastMessage
```

- **`proximityFactor(char, zone, region)`** — boost when `char.homeZone == zone`,
  smaller boost when `char.homeRegion == region`, neutral otherwise. A new
  `proximityStrength` config (like `areaMatchStrength`) tunes it; `1` disables (global
  behavior). This realizes "more likely to hear a character near their hometown."
- **`areaRoleFactor(role, areaType)`** — realizes "no noble in the wilderness." A
  declarative `AREA_ROLE_BIAS` map (area bucket → `{role -> factor}`, missing role ⇒
  `1.0`) lives in `data/traits.lua` alongside the shipped roster bias tables
  (`CITY_BIAS`/`GENDER_BIAS`/`FACTION_BIAS`) and reuses the same convention. It's a
  *speaker-selection* multiplier over the existing roster (not a generation-time pick),
  so it folds into the speaker weight beside `proximityFactor` rather than going through
  `weightedPick`. Softened by `areaRoleStrength` with the shipped `scaleModifier` form
  `eff = 1 + (factor-1)*s` (`s=0` ⇒ off, every role equally likely for the locale; `s=1`
  ⇒ as authored). A factor of `0` excludes a role *for that area only* (a noble simply
  isn't chosen as the wilderness speaker) — the character still exists and still speaks
  in cities, so the trait layer's "never globally impossible" invariant holds. If every
  candidate in a bucket zeroes out, fall back to a chattiness-only pick so a populated
  zone is never silent (mirrors `weightedPick`'s `total <= 0` guard).

  ```lua
  -- data/traits.lua — keyed by AREA bucket (one of AREAS); author a few strong, legible
  -- affinities per area, not a full role×area matrix. Zeros are in-context exclusions.
  R.AREA_ROLE_BIAS = {
    city        = { noble = 1.6, vendor = 1.4, guard = 1.3, farmer = 0.5 },
    rural       = { farmer = 2.2, adventurer = 1.4, sailor = 1.2, noble = 0.2, mage = 0.4 },
    wilderness  = { adventurer = 2.0, sailor = 1.3, noble = 0, vendor = 0.2, innkeeper = 0.2 },
    battlefield = { soldier = 3.0, guard = 2.0, adventurer = 1.4, noble = 0, farmer = 0.2 },
    coast       = { sailor = 2.5, vendor = 1.2, noble = 0.3 },
    road        = { adventurer = 1.6, vendor = 1.4, sailor = 1.2 },
  }
  -- An area with no entry, or a role absent from its map, contributes no tilt.
  ```

  Note this complements the existing character `area` affinity (a softer, per-character
  locale lean): `area` nudges *which characters* prefer a locale; `AREA_ROLE_BIAS` gates
  *which roles* are plausible to be heard there, which is what "no noble in the wilds"
  asks for. Keep both — they stack multiplicatively on the speaker weight.
- **City-topic bias** — `cityFor()` gains a listener-aware mode: when delivering to a
  zone, bias `%city%` toward `zoneToNearestCity[zone]` (so players near Stormwind hear
  Stormwind chatter), falling back to the speaker's `homeCity`, then random. Thread the
  delivery zone into the render path (`speak`/`renderTokens`) so the resolver can see
  it. This realizes "more likely to hear chatter regarding a city you're close to."
- **Faction gating** stays: a zone's deliverable players are split by `GetTeam()` on
  send, or the speaker's faction is chosen to match the zone's controlling faction;
  `shared`-origin lines deliver to both. The `audience` tag still exists but is now
  resolved *per delivery group*, not per global broadcast.

**Cost note.** Per-zone, per-player `SendBroadcastMessage` scales with player count.
For a small realm this is fine; gate the whole feature behind `enableZoneChat` and keep
the legacy global `emit` path when it's off. Cap work by only iterating *populated*
zones (skip empties) and reusing one rendered string per (zone, faction) group.

#### Part D — Timer architecture: per-area, not per-faction

Replace the two faction-drivers with **area-driver timers**, each with its own cadence
pair so density differs by locale:

```lua
-- new config (replaces talk_time / faction_talk_time as the timer axis)
local cityTalkTime        = {4000, 12000}   -- busy: frequent
local ruralTalkTime       = {15000, 45000}  -- sparse: occasional
local battlefieldTalkTime = {6000, 18000}   -- bursty when contested

CreateLuaEvent(function() tickArea("city")        end, {cityTalkTime[1],        cityTalkTime[2]},        0)
CreateLuaEvent(function() tickArea("rural")       end, {ruralTalkTime[1],       ruralTalkTime[2]},       0)
CreateLuaEvent(function() tickArea("battlefield") end, {battlefieldTalkTime[1], battlefieldTalkTime[2]}, 0)
```

- Faction is **no longer a timer**. Each `tickArea` handles both factions by bucketing
  players and matching speaker faction per bucket. This removes the
  "alliance-also-carries-shared" coupling and the legacy second-driver branch.
- The other `AREAS` (`coast`/`wilderness`/`road`) either fold into the nearest of the
  three timers via `zoneToArea` (e.g. coast→rural) or get their own timer later. Start
  with three; the mapping table makes adding a fourth a data change.
- Keep `enableZoneChat=false` → fall back to the **current** two-faction timers + global
  `emit` unchanged, so this is a clean opt-in and an easy A/B.

#### Part E — Config

```lua
local enableZoneChat       = true
local cityTalkTime         = {4000, 12000}
local ruralTalkTime        = {15000, 45000}
local battlefieldTalkTime  = {6000, 18000}
local proximityStrength    = 3.0    -- home-zone/region speaker boost; 1 = off
local cityTopicBias        = true   -- bias %city% toward listener's nearest capital
local areaRoleStrength     = 1.0    -- area-appropriate speaker roles; 0 = off (any role)
```

#### Build order

1. **Data maps** — add `zoneToArea` / `zoneToRegion` / `zoneToNearestCity` to
   `data/context.lua` (IDs + name fallback) with safe defaults; unit-check every
   `zones`/`cities` entry resolves.
2. **Character home zone** — add `homeZone`/`homeRegion` to `generateCharacter`
   (faction/role biased); leave `area`/`homeCity` untouched.
3. **Proximity + city-topic + area-role** — add `proximityFactor` and `areaRoleFactor`
   (+ the `AREA_ROLE_BIAS` map in `data/traits.lua`), thread delivery-zone into the
   speaker pick and `cityFor`; behind `proximityStrength` / `cityTopicBias` /
   `areaRoleStrength`. All three are multiplicative terms on the speaker weight.
4. **Per-zone delivery** — implement `tickArea` and per-zone bucketed delivery behind
   `enableZoneChat`; keep legacy `emit` for the off path.
5. **Per-area timers** — swap the faction-drivers for the three area-drivers (only when
   `enableZoneChat`); retire the legacy second-driver branch on that path.
6. **README + manifest** — document the new model, the maps, and the cadence knobs.

#### Edge cases / correctness checklist

- Unmapped zone → default area + no proximity boost; never errors.
- Zero players in an area-type → skip silently (no cursor churn), as today.
- A character with no `homeZone` (pre-existing/edge) → `proximityFactor` returns 1.0.
- A role absent from an area's `AREA_ROLE_BIAS` entry, or an area with no entry →
  `areaRoleFactor` returns 1.0 (no tilt). If every candidate speaker in a bucket zeroes
  out, fall back to a chattiness-only pick so a populated zone never goes silent.
- `AREA_ROLE_BIAS` zeros are in-context exclusions only — they must never make a role
  globally impossible (it still appears in roster generation and speaks in other areas).
- `enableZoneChat=false` → byte-for-byte the current global behavior (regression-test
  this path stays intact).
- Player count scaling — confirm one rendered string is reused per (zone, faction)
  group, not re-rendered per player; cap or sample if a zone holds very many players.
- Conversation chains (duos/groups) must stay within **one** delivery group — a chain
  started for a zone bucket should finish for that same bucket, not leak across zones.
  Coordinate with `CONVERSATION_PACING_PLAN.md` (per-channel conversation state must be
  keyed by zone bucket, not just faction, once delivery is per-zone).

#### Verification

- `tools/lua_check.py` on touched files; a map-coverage check (every `zones`/`cities` entry
  is classified).
- Offline: `proximityFactor` returns the expected ordering (home-zone > home-region >
  elsewhere) and `cityFor` picks the nearest capital for a sample of zones. Sampling
  check: over many ticks, P(speaker=noble | wilderness/battlefield) ≈ 0 while nobles
  still speak in cities; soldiers dominate the battlefield speaker mix; `areaRoleStrength=0`
  collapses the per-area role histogram back to the chattiness-only baseline. Every
  `AREA_ROLE_BIAS` zero is intentional and no role is globally excluded.
- In-game matrix: two players in different zones see different speakers/lines; a player
  in Elwynn hears Stormwind-flavored `%city%`; a battlefield zone fires on the bursty
  cadence; `enableZoneChat=false` reproduces the old global chatter; log a player out
  mid-tick (no orphan send).
