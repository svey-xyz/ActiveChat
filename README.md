# ALE Script: Lively World Chat

Fill **World chat** with ambient, in-world roleplay chatter — the kind of talk you'd
overhear in a busy capital: citizens, vendors, guards, adventurers, and soldiers swapping
gossip, lore, jokes, and quiet observations about life in Azeroth. Built for AzerothCore
(Eluna Lua), it makes **single-player and low-population servers** feel inhabited without
anyone else online.

## Why it's fun

- **Characters with personality, not random names.** Chatter is voiced by a roster of
  **recurring residents** — each with a name, faction, role, mood, home city, and a stable
  name color — who reappear across a session as familiar voices. → [docs/characters.md](docs/characters.md)
- **The world reads like Azeroth *right now*.** Night lines fire at night, festival lines
  fire during the actual festival, and season talk tracks real game state — all inside the
  fiction, no clocks or "server time." → [docs/context.md](docs/context.md)
- **~45 lore placeholders** keep it fresh: `%zone%`, `%boss%`, `%mount%`, `%event%`,
  `%city%`, and more swap in random, lore-appropriate values so no line reads the same
  way twice. → [docs/placeholders.md](docs/placeholders.md)
- **Three conversation shapes** — standalone one-liners, two-person back-and-forth, and
  multi-voice group discussions.
- **Faction-aware** — lines go to everyone (`shared`) or one faction (`alliance` /
  `horde`), each with its own capital-city flavor.
- **Easy to extend** — all content lives in plain Lua tables; add lines without touching
  the engine. → [docs/authoring.md](docs/authoring.md)

It's **deliberately not an imitation of real players**: no gearscore spam, no auction
adverts, no out-of-character meta. Every line stays inside the fiction — Azeroth is real
to these voices. If you want player-like behavior (LFG, trade, raid logistics), pair this
with a playerbot module; this script is for *flavor and atmosphere.*

## Installation

1. Requires **mod-ale** on your server.
2. Download the zip and extract the folder into your server's `lua_scripts` folder.

## How it works

The engine keeps an **in-memory roster** that starts empty and grows lazily toward a cap
as chat timers fire, self-balancing so the population settles and then reuses familiar
voices. Characters are never persisted — a restart regrows a fresh roster.
→ [docs/characters.md](docs/characters.md)

When a timer fires, the engine picks a speaker (weighted by `chattiness`), then **scores
every candidate line** against that character's role, mood, and area plus the live
time/event/season context. Tagged lines that don't fit are down-weighted or hard-excluded;
untagged lines stay global, so no character ever goes silent.
→ [docs/authoring.md](docs/authoring.md)

Two timers drive output — an Alliance-driver (shared + Alliance lines) and a Horde-driver
(Horde lines) — routing each line to the right audience.
→ [docs/config.md → Audience model](docs/config.md#audience-model-who-hears-each-line)

## Quick start: add a line

Content lives in `ActiveChat/talk_text/npc_text.lua`. The simplest line is a bare string;
add tags only when the content implies a role/mood/area/context:

```lua
-- universal ambience (the fallback pool — keep most lines like this)
"The lamplighters are making their rounds.",

-- a gruff city vendor, night only
{ "Three coppers a loaf and not a copper less.",
  roles={"vendor"}, moods={"gruff"}, times={"night"} },
```

Full authoring format, tag fields, and the scoring model: [docs/authoring.md](docs/authoring.md).

## Configuration

All knobs live at the top of `ActiveChat/npcTalk.lua` — master on/off, timer intervals,
roster cap, match strengths, and the context-aware flags. Full reference:
[docs/config.md](docs/config.md).

## Documentation

| Doc | Covers |
|---|---|
| [characters.md](docs/characters.md) | The recurring roster: fields, lazy growth, names, roles/personalities/areas |
| [authoring.md](docs/authoring.md) | Content pools, tagged format, tag fields, how a line is chosen |
| [context.md](docs/context.md) | Time/event/season awareness, context tokens, sourcing |
| [config.md](docs/config.md) | Every config var, context flags, `homeCityBias`, audience model |
| [placeholders.md](docs/placeholders.md) | All `%token%` substitutions |
| [docs/plans/](docs/plans/) | Roadmap and design notes |

> **Guild chat removed.** Earlier versions emitted Guild chat; a guild is a
> player-organization construct that doesn't fit the civilian/guard/NPC scope, so this
> module is now **World-chat only.**

## Contributing

I am not the original author — I modified and expanded it, reworking the content away from
player-imitation/meme humor toward lore-grounded RP. If you expand the text, please open a
pull request so we can all share in the fun — and keep new lines in-character (no
real-world references, no fourth-wall jokes).
