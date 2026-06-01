# Config reference

All knobs live in `AzerothChatter/AzerothChatter.lua` — a single flat table, the one source of
truth, read by both the engine (`logic/chatter.lua`) and `logic/context.lua`. Edit values there.

```lua
return {
    enableScript      = true,   -- master on/off
    enableFactionChat = true,   -- true = gate alliance/horde lines by faction
                                -- false = legacy: broadcast everything to everyone

    talk_time         = {1000, 10000},   -- Alliance-driver interval (ms)
    faction_talk_time = {8000, 20000},   -- Horde-driver interval (ms)
    -- ... (see AzerothChatter.lua for the full set)
}
```

## Core

| Var | Default | What it does |
|---|---|---|
| `enableScript` | `true` | Master on/off for the whole module. |
| `enableFactionChat` | `true` | `true` = gate alliance/horde lines by faction. `false` = legacy: merge everything and broadcast to everyone. |
| `talk_time` | `{1000, 10000}` | Interval (ms, min/max) for the **Alliance-driver** timer — carries shared (everyone) + Alliance-only chatter. |
| `faction_talk_time` | `{8000, 20000}` | Interval (ms) for the **Horde-driver** timer. |
| `maxCharacters` | `128` | Cap on the lazily-grown roster. |
| `maxCharactersPerFaction` | `nil` | Optional per-faction sub-cap (`nil` = share the global cap). |
| `newCharacterWeight` | `8` | Weight of the virtual "spawn a new character" slot vs. existing characters' summed chattiness — tunes how fast the roster fills. |
| `lineCooldownTicks` | `8` | Default per-line repeat cooldown (in ticks) used by the line scorer. |
| `homeCityBias` | `true` | Bias `%city%` toward the speaking character's own home city (see below). |
| `roleMoodMatchStrength` | `3.0` | How hard role/mood matching is weighted in line scoring (`1` = off). |
| `areaMatchStrength` | `3.0` | How hard area matching is weighted in line scoring (`1` = off). |

There is also an `ns` string in `AzerothChatter.lua`: an optional `WorldDBQuery` to source extra
surnames from the world DB (blank = use only `data/names.lua`).

## Conversation pacing

Two **orthogonal** knobs govern timing. `talk_time` / `faction_talk_time` set **ambient
frequency** — how often a *new* conversation starts. `convLineGap` sets **within-conversation
pacing** — how fast the lines of a single duo/group flow once it has started. They are
independent on purpose: you can widen `talk_time` to make the world quieter *without*
making each conversation drag, so a sparse world still plays out its occasional exchanges
crisply.

With `enableBurstConversations = true`, when a duo/group starts the ambient driver emits
line 1 and hands the remainder to a dedicated short-interval **burst timer** that voices the
rest at `convLineGap` pacing using the same fixed cast. The ambient tick yields for that
channel until the chain finishes. With it `false`, behaviour is exactly the legacy cadence:
each chain line advances on the next ambient tick (paced by `talk_time`). Single `line`
items are never bursted — one-and-done.

| Var | Default | What it does |
|---|---|---|
| `enableBurstConversations` | `true` | `true` = play a chain's remaining lines on the burst timer. `false` = legacy one-line-per-ambient-tick. |
| `convLineGap` | `{1500, 4000}` | Interval (ms, min/max, jittered) between successive lines of an in-flight chain. |
| `convMaxLines` | `nil` | Cap on a single chain's aired lines (airtime), so a long group can't monopolize a channel. `nil` = run the whole chain. |

## Context-aware chatter flags

These control the time/event/season awareness (see [context.md](context.md)). Each
dimension degrades gracefully: turning a flag off — or running on a build whose
game-time/event API is missing — reverts that dimension to random behaviour. It is
**safe to ship on any build**; nothing here can error or silence a character.

| Var | Default | What it does |
|---|---|---|
| `enableContextAware` | `true` | Master switch for the whole context feature. Off ⇒ all three dimensions revert to random. |
| `enableTimeContext` | `true` | In-game-clock-aware `times` tags + `%timeofday%`. |
| `enableEventContext` | `true` | Active-event gating (`events`/`eventWindow` tags) + `%event%`/`%nextevent%`/`%lastevent%`. |
| `enableSeasonContext` | `true` | In-game-month season (`seasons` tags) + `%season%`. |
| `timeMatchStrength` | `3.0` | How hard a graded `times` match is boosted (`1` = off), like `areaMatchStrength`. |
| `seasonMatchStrength` | `3.0` | How hard a graded `seasons` match is boosted (`1` = off). |
| `contextRefreshMs` | `60000` | TTL (ms) of the cached `ctx`. Context is re-read at most this often, never per line. |
| `eventApproachDays` | `5` | Length (days) of the `eventWindow="approach"` run-up window. |
| `eventAfterDays` | `3` | Length (days) of the `eventWindow="after"` wind-down window. |
| `enableEventBurst` | `false` | Optional one-shot "the festival has begun" exchange when an event flips active. Off by default. |

## Player commands

In-game `.ac` commands (create / who / list / help) that let a player spawn and inspect
roster characters. Output is **private** to the requesting player, never World chat. See
[characters.md → Spawning & inspecting characters in-game](characters.md#spawning--inspecting-characters-in-game-ac-commands).

| Var | Default | What it does |
|---|---|---|
| `enablePlayerCommands` | `true` | Master on/off for the `.ac` command surface. Off ⇒ no hooks are registered (silent no-op). |
| `playerCreateGmOnly` | `false` | `true` = restrict `.ac create` (both arg and gossip forms) to GMs (`player:IsGameMaster()`, with `IsGM`/`GetGMRank` fallbacks across ALE builds). |
| `playerCreateLimit` | `5` | Max characters one player may create per **login session** (anti-spam). The counter resets on logout. |

Player creations **share the global `maxCharacters` cap** with ambient spawns — when the
roster is full, `.ac create` refuses cleanly rather than evicting an ambient character. (An
alternative reserved-slice model, so players can't starve ambient variety, is noted in the
code but not implemented.)

## `homeCityBias` and `%city%`

With `homeCityBias = true`, the `%city%` token resolves to the **current speaker's own
`homeCity`**, so a line reads as self-reference (each cast member in a duo/group
references *their* home, not just the conversation's initiator). Because a character's
`homeCity` is drawn from **their own faction's** capital list, this is automatically
faction-correct — a Horde speaker biases to a Horde capital, an Alliance speaker to an
Alliance one. Neutral hubs (Dalaran, Shattrath, Booty Bay) are never home cities, so they
only appear via the random path. With `homeCityBias = false`, `%city%` is random over all
cities (capitals + neutral hubs).

## Audience model (who hears each line)

Lines are routed to listeners by the **origin pool** of the chosen line, and the two chat
timers are mapped to **factions** (not to audiences):

- **Alliance-driver** (on `talk_time`): an **Alliance** character speaks, drawing from
  `shared ∪ alliance`. Each chosen line is routed by its origin — a **shared** line ⇒
  `SendWorldMessage` (everyone), an **alliance** line ⇒ Alliance players only. So
  everyone-visible chatter is always **Alliance-voiced**; a Horde character never voices
  an everyone-visible line.
- **Horde-driver** (on `faction_talk_time`): a **Horde** character speaks, drawing from
  `horde` only, emitted to Horde players only.

Two drivers cover every audience path with no duplication: Alliance-only lines are
already alliance-origin items inside the Alliance speaker's candidate set, so a separate
Alliance-only timer would double-voice that pool — hence it was dropped.

**Legacy `enableFactionChat = false`:** all three pools merge into one everyone-visible
set (tagged `shared`), so both timers broadcast everything to everyone — the original
behavior, now voiced by characters.

Both drivers gate on `GetPlayersInWorld(team)`: with no online listeners for an audience,
the message is simply skipped.
