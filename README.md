# Eluna Lua Script: Lively World & Guild Chat

This script is for AzerothCore using Eluna Lua scripting. It fills World and Guild
chat with **ambient, in-world roleplay chatter** — the kind of talk you'd overhear
in a busy capital: citizens, vendors, guards, adventurers, and soldiers swapping
gossip, lore, jokes, and quiet observations about life in Azeroth. It's intended
for single-player and low-population servers, where it makes the world feel
inhabited without anyone else being online.

The chatter is **deliberately not an imitation of real players.** There's no
gearscore spam, no auction-house adverts, no out-of-character meta. If you want
characters that behave like real players (LFG, trade, raid logistics), pair this
with a playerbot module instead — this script is for *flavor and atmosphere.*
Every line is written to stay inside the fiction: Azeroth is real to these voices.

Note: I am not the original author. If you are the original author please contact
me so I can give you proper credit. I just modified and expanded it. The content
was reworked away from player-imitation/meme humor toward lore-grounded RP.

If you expand the text, please make a pull request so we can all share in the fun —
and keep new lines in-character (no real-world references, no fourth-wall jokes).

![Active Chat](https://i.postimg.cc/fRvLKM1W/Capture.png)

## Installation
- This script requires the Eluna module for your server.
- Download the zip and extract the folder into your server's `lua_scripts` folder.

## Features

- **Ambient World and Guild Chat** — a steady stream of in-world chatter in both
  channels, so the cities feel alive.
- **Faction-aware** — lines can be broadcast to everyone (`shared`) or sent only
  to one faction (`alliance` / `horde`), each with its own city flavor
  (Stormwind/Ironforge/Darnassus vs. Orgrimmar/Thunder Bluff/Silvermoon/Undercity).
- **Three conversation shapes** — standalone one-liners, two-person back-and-forth
  exchanges, and multi-voice group discussions, all spoken by faction-appropriate
  randomized names.
- **Placeholder substitution** — lines can pull in random zones, dungeons, classes,
  professions, gathering activities, cities, races, native monsters and critters,
  bosses, mounts, items, gathered goods (herbs, ore, gems, fish), lore figures,
  food and drink, events, seasons, shops, routes, tales, weather, and more
  (44 tokens in all) so the chatter never reads the same way twice.
- **Easy to extend** — content lives in plain Lua tables; add or edit lines without
  touching the engine.

## Configuration

Set the flags and intervals at the top of `ActiveChat/npcTalk.lua`:

```lua
local enableScript      = true   -- master on/off
local enableGuildChat   = true   -- guild channel on/off
local enableFactionChat = true   -- true = gate alliance/horde lines by faction
                                 -- false = legacy: broadcast everything to everyone

local talk_time          = {1000, 10000}   -- shared WORLD chat interval (ms)
local guild_talk_time    = {10000, 30000}  -- shared GUILD chat interval (ms)
local faction_talk_time  = {8000, 20000}   -- faction WORLD chat (per faction)
local guild_faction_time = {20000, 45000}  -- faction GUILD chat (per faction)
```

Names are sourced from `ActiveChat/npc_name.lua` (faction-aware: `neutral`,
`alliance`, `horde`). You can optionally pull additional names from the world DB
by setting the `ns` query string near the top of `npcTalk.lua`.

## Content structure

World chatter lives in `ActiveChat/talk_text/npc_text.lua`; guild chatter in
`ActiveChat/talk_text/npc_text_guild.lua`. Both return the same shape:

```lua
return {
  shared   = { lines = {...}, duos = {...}, groups = {...} },  -- seen by everyone
  alliance = { lines = {...}, duos = {...}, groups = {...} },  -- Alliance only
  horde    = { lines = {...}, duos = {...}, groups = {...} },  -- Horde only
}
```

Each faction pool has three lists you can extend freely:

- **`lines`** — standalone one-liners, spoken by a single random character.
- **`duos`** — two-person back-and-forth. Two fixed speakers alternate
  A / B / A / B through the entries of the table.
- **`groups`** — group discussions. A rotating cast of 4–6 voices, one line each,
  no voice speaking twice in a row.

## Adding content

Open the relevant file in any text editor and add to the appropriate list.

A simple one-liner — add a string to `lines`:

```lua
"The Cathedral bells are early today. Someone's getting married, or buried.",
```

A two-person exchange — add a table of strings to `duos` (speakers alternate):

```lua
{"Is the tavern always this loud?", "Only when it's awake.", "...I'll come back at dawn."},
```

A group discussion — add a table of strings to `groups` (rotating cast):

```lua
{"Which capital's the finest?", "Ironforge, no contest.", "Stormwind, surely.",
 "You've all forgotten Thunder Bluff.", "...this argument never ends, does it."},
```

Keep new entries in-character. Good lines sound like something a tavern regular,
a city guard, or a road-weary adventurer would actually say. Avoid real-world
references, out-of-character meta, and anything that breaks the fiction.

### Placeholders

Drop these tokens into any line and the engine swaps in a random, lore-appropriate
value each time the line is spoken:

| Token | Replaced with |
|---|---|
| `%zone%` | a random game zone (e.g. *Stranglethorn Vale*) |
| `%instance%` | a random dungeon or raid (e.g. *Blackrock Depths*) |
| `%role%` | *Tank*, *Healer*, or *DPS* |
| `%class%` | a random player class (e.g. *Druid*) |
| `%bg%` | a random battleground (e.g. *AV*) |
| `%profession%` | a profession (e.g. *Jewelcrafting*, *Cooking*) |
| `%activity%` | a gathering/profession activity, gerund phrase (e.g. *collecting herbs*) |
| `%city%` | a capital or neutral hub (e.g. *Orgrimmar*, *Dalaran*) |
| `%race%` | a playable race (e.g. *Blood Elf*) |
| `%monster%` | a hostile native creature (e.g. *murloc*, *owlbeast*) |
| `%critter%` | a passive critter (e.g. *deer*, *rabbit*) |
| `%boss%` | a notable boss (e.g. *The Lich King*, *Ragnaros*) |
| `%consumable%` | a flask, potion, or food buff (e.g. *Fish Feast*) |
| `%item%` | a famous epic/legendary (e.g. *Shadowmourne*) |
| `%rep%` | a reputation faction (e.g. *Kirin Tor*) |
| `%mount%` | a notable mount (e.g. *Invincible*) |
| `%spell%` | a class spell/ability (e.g. *Bloodlust*) |
| `%rare%` | a rare spawn (e.g. *Time-Lost Proto-Drake*) |
| `%pvptitle%` | a PvP/achievement title (e.g. *the Kingslayer*) |
| `%emote%` | an emote action verb (e.g. *cheer*, *facepalm*) |
| `%difficulty%` | a difficulty tag (e.g. *25-man Heroic*) |
| `%gold%` | a random gold amount, suffixed `g` (e.g. *8500g*) |
| `%level%` | a random character level, 2–80 |
| `%gearscore%` | a random WotLK-era GearScore, 2400–6000 |
| `%event%` | a holiday or world event (e.g. *Hallow's End*, *Brewfest*) |
| `%season%` | a season (e.g. *winter*, *high summer*) |
| `%timeofday%` | a time of day (e.g. *dusk*, *the small hours before dawn*) |
| `%shop%` | a named tavern, inn, or shop (e.g. *the Pig and Whistle Tavern*) |
| `%route%` | a travel route or method (e.g. *the Deeprun Tram*) |
| `%tale%` | a famous legend or story (e.g. *the Culling of Stratholme*) |
| `%weather%` | a weather condition (e.g. *a blizzard*, *clear skies*) |
| `%herb%` | a gatherable herb (e.g. *Frost Lotus*, *Goldclover*) |
| `%ore%` | an ore or smeltable metal (e.g. *Saronite*, *Truesilver*) |
| `%gem%` | a cut or raw gem (e.g. *Cardinal Ruby*) |
| `%fish%` | a catchable fish (e.g. *Dragonfin Angelfish*) |
| `%npc%` | a famous lore figure (e.g. *Thrall*, *Jaina Proudmoore*) |
| `%currency%` | an earned currency/badge (e.g. *Emblem of Frost*) |
| `%food%` | a tavern food (e.g. *a Dalaran Brownie*) |
| `%drink%` | a tavern drink (e.g. *Thunder Ale*) |
| `%title%` | a non-PvP/PvE title (e.g. *the Loremaster*, *Chef*) |
| `%tradegood%` | a crafting material (e.g. *Frostweave Cloth*, *Eternal Fire*) |
| `%companion%` | a vanity companion pet (e.g. *an Onyxian Whelpling*) |
| `%enchant%` | a gear enchantment (e.g. *Mongoose*, *Crusader*) |
| `%toy%` | a novelty/fun item (e.g. *a Noggenfogger Elixir*) |

#### Player-imitation tokens (use sparingly)

These exist for the occasional adventurer voice, but the chatter is meant to be
**civilian/guard/NPC flavor, not an imitation of real players.** Avoid LFG/LFM,
grouping requests, and gearscore/parse talk — that's the job of a playerbot
module, not this script.

| Token | Replaced with |
|---|---|
| `%role%` | *Tank*, *Healer*, or *DPS* |
| `%difficulty%` | a difficulty tag (e.g. *25-man Heroic*) |
| `%gearscore%` | a WotLK-era GearScore number, 2400–6000 |

Example (in-character, world-focused — note: no grouping or gearscore talk):

```lua
"Folks are out %activity% in %zone% — the %herb% practically sells itself in %season%.",
"%weather% over %zone% at %timeofday%. Perfect %season% evening, if you ask me.",
"Heard %npc% was spotted near %city%. Whole tavern's talking about nothing else.",
"The %shop% is out of %drink% again, but the %food% is fresh. Small mercies.",
```

The lists these tokens draw from (`zones`, `instances`, `roles`, `classes`,
`battlegrounds`, `professions`, `activities`, `cities`, `races`, `monsters`,
`critters`, `bosses`, `consumables`, `items`, `reps`, `mounts`, `spells`,
`rares`, `pvptitles`, `titles`, `emotes`, `difficulties`, `events`, `seasons`,
`timesofday`, `shops`, `routes`, `tales`, `weathers`, `herbs`, `ores`, `gems`,
`fish`, `npcs`, `currencies`, `foods`, `drinks`, `tradegoods`, `companions`,
`enchants`, `toys`) live near the top of `npcTalk.lua` and can be edited there.
The numeric tokens (`%gold%`, `%level%`, `%gearscore%`) are generated by small
helper functions in the same file. Note: a token used twice in one line resolves
to the **same** value both times — the pick is made once per line.
