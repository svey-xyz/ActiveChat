# Plan: Player Interaction for ActiveChat

> **Status / scope note.** ActiveChat's primary purpose is **ambient, in-world RP
> chatter** — atmosphere, not player imitation. This player-interaction feature is
> an **optional, secondary enhancement**: when the real player speaks, a nearby
> *in-world character* (a passing citizen, a guard, a fellow adventurer) answers
> **in character**. It is explicitly **not** about making fake players that behave
> like real ones — that's what a playerbot module is for. Every response here must
> stay inside the fiction: no real-world references, no out-of-character meta, no
> "looks like a real player" framing. If that bar can't be met for a given
> category, leave the category out.

## Relevant docs

- docs/placeholders.md
- README.md (feature flags + reaction authoring format)
- CONTEXT_AWARE_PLAN.md (responders read the shared `ctx`)
- CONVERSATION_PACING_PLAN.md (shares the staggered burst renderer)

## Completed

- None yet — all phases below are planned. (Optional, secondary feature — may stay
  shelved indefinitely; see the open decisions at the end.)

---

## Phases (planned)

### **Phase 1 — In-character player responses**

#### Framing (read first)

ActiveChat is a **chat simulator**, not creature AI. The "characters" are in-world
personas (citizens, adventurers, soldiers) that post into World/Guild via
`SendWorldMessage` / `SendBroadcastMessage`. There are no real NPCs/creatures
involved, and nothing the module emits goes through the real chat pipeline.

So "player interaction" here means: **when the real player types, a faction-matched
in-world character responds in the same channel, in character.** A player says
"hello" → a same-faction resident answers "Well met, traveler." a beat later. The
response should read like overheard roleplay, not like another player whispering
back.

Two consequences shape everything below:

- **No DB, no creatures.** All state is ephemeral Lua, cleared on logout. (The
  AzerothCore character-persistence pattern does not apply — there is no
  per-character data worth persisting.)
- **No feedback loop, by construction.** Replies go out via
  `SendWorldMessage`/`SendBroadcastMessage`, which are display-only and never
  re-enter the chat hooks. Real chat in → in-world reply out, one direction.

#### Goals (from the clarified scope)

1. **Keyword + fuzzy matching** of player input into intent categories
   (greeting, farewell, thanks, laugh, lost/directions, lore-question, taunt).
   Categories must be answerable *in character* — no LFG/trade/auction
   transactional categories, which belong to player-imitation, not RP.
2. **Three conversation shapes**, all driven by player input:
   - **Character → player single reply** (the "say hello, get a hello" base case).
   - **Character ↔ player multi-turn thread** — the resident replies and asks a
     follow-up; if the player answers in-window, the thread advances.
   - **Character ↔ character, player-sparked burst** — a player greeting kicks off
     a short two-voice exchange that the player watches scroll by.
   - (Ambient character ↔ character already exists via the `duos`/`groups`
     conversation tables; we add an optional staggered "burst" renderer so those
     read as real-time exchanges rather than one line per global tick.)
3. **Same-faction responders** via `player:GetTeam()` → faction name pool +
   faction response pool. Optional cross-faction *in-character heckling* behind a
   flag (an enemy soldier muttering across neutral ground, never modern meta).

#### Current architecture (what we build on)

`ActiveChat/npcTalk.lua` (single script, `if enableScript then … end`):

- Config flags: `enableScript`, `enableGuildChat`, `enableFactionChat`; interval
  pairs `talk_time`, `guild_talk_time`, `faction_talk_time`, `guild_faction_time`.
- Content loaded from `talk_text/npc_text.lua` and `npc_text_guild.lua`, each
  returning `{ shared, alliance, horde }`, where every faction pool is
  `{ lines, duos, groups }` (one-liners, two-speaker exchanges, multi-voice
  threads). `buildItems` flattens these into a cursored, kind-tagged item list.
- Reusable machinery already present and directly reusable:
  - `nameFrom(faction)` / `twoNames(faction)` / `manyNames(faction, n)` — faction
    name selection.
  - `t.cc` color palette; `formatWorld(name, body)` / `formatGuild(name, body)`.
  - Placeholder substitution (`%zone% %instance% %role% %class% %bg%` plus the
    expanded set: `%profession% %city% %race% %boss% %consumable% %item% %rep%
    %mount% %spell% %rare% %pvptitle% %emote% %difficulty% %gold% %level%
    %gearscore% %event% %season% %timeofday% %shop% %route% %tale% %weather%`
    — see README.md) inside `t.dt`.
  - `t.fg` / `t.dt` — cursor-based conversation renderer with A/B speaker
    alternation (duos) and non-repeating cast rotation (groups).
- Emission via `CreateLuaEvent(fn, {min,max}, 0)` repeating timers;
  `GetPlayersInWorld(team)` for faction-scoped broadcast.

All the hard parts (faction names, formatting, placeholders, chain rendering)
already exist. The new work is mostly **input handling + scheduling**, reusing
these helpers.

#### Files

| File | Change |
|---|---|
| `ActiveChat/npcTalk.lua` | Add config block, normalize/fuzzy utils, per-player state, chat hooks, response scheduler, logout cleanup. Keep new logic in this file's scope so it reuses existing closures (`nameFrom`, `formatWorld`, placeholder subst). *Simple > complex — no new shared module unless it grows.* |
| `ActiveChat/talk_text/npc_reactions.lua` | **New.** In-character reaction content keyed by category × faction. Mirrors the `{shared, alliance, horde}` shape so faction gating is consistent. |
| `README.md` | Document the feature, config flags, and how to add reaction categories/threads — with the in-character authoring rule called out. |

> **Cross-reference (context-aware chatter).** Responders read the shared `ctx`
> table — the single source of "what's true right now" (time/season/active +
> nearest events) populated by `refreshCtx()` in `context.lua` — so reaction
> content can carry the same `times`/`events`/`seasons` tags and resolve
> `%event%`/`%season%`/`%timeofday%` to the live moment. The event-activation burst
> hook also lives in `refreshCtx()` (behind `enableEventBurst`): when an event flips
> active it seeds a one-shot character↔character festival burst via the existing
> conversation machinery. Wiring `ctx` into the reaction *dispatcher*
> (`dispatch`/`advanceThread`) is straightforward once those functions exist — `ctx`
> is module-level and already read at the top of `speak()`. See CONTEXT_AWARE_PLAN.md
> "Tie-in: Player Interaction plan".

#### Part A — Data model: `npc_reactions.lua`

Author it the same way as the existing files (strings = one-liners, tables of
strings = exchanges) so contributors already know the format. Add one new entry
shape — a **thread** object — for player follow-ups. **All content must be
in-character** (see the scope note up top).

```lua
return {
  greeting = {
    shared = {
      "Well met, traveler.",
      "Hail, friend. Safe roads.",
      { kind = "npc_npc", chain = {"New face in the city?", "Looks it. Welcome, stranger."} },
    },
    alliance = { "For the Alliance. Well met.", "Light be with you, citizen." },
    horde    = { "Lok'tar, traveler.", "Throm-Ka. Strength to you." },
  },

  directions = {            -- player is lost / asking the way (in-world help)
    shared = {
      -- character -> player thread: reply, then expect a follow-up keyword
      {
        kind = "npc_player",
        say  = "Lost, are you? Where are you headed?",
        expect = {                       -- player's next msg routed by intent
          instance = "Ah, %instance%. Mind the road, and don't travel it alone.",
          zone     = "%zone%? Follow the main road out the gate and keep your blade handy.",
          _default = "Ask the city guard by the gate — they know every street.",
        },
      },
    },
    alliance = { "The Stormwind guards will point you true. Look for the tabards." },
    horde    = { "Ask in Orgrimmar — the Valley of Honor folk will set you right." },
  },

  lore  = { ... },   -- short in-world answers to questions about the world
  taunt = { ... },   -- in-character heckling, only if enableCrossFactionTaunts
  farewell = { ... }, thanks = { ... }, laugh = { ... },
}
```

Entry shapes, unified:

- `"string"` → single reply (existing convention).
- `{ "l1", "l2", ... }` → reuse existing exchange renderer (character ↔ character burst).
- `{ kind="npc_npc", chain={...} }` → explicit player-sparked character↔character burst.
- `{ kind="npc_player", say="…", expect={ intent=reply, _default=reply } }` →
  multi-turn thread; `expect` maps the *next* classified intent to a reply (or
  another nested thread for 3+ turns).

Placeholders (`%zone%` etc.) work everywhere because all output passes through
the existing substitution step.

#### Part B — Matching: normalize + fuzzy classify

New pure functions (unit-testable offline, no game state):

```
normalize(msg)        -> lowercased, color-codes/links stripped, punctuation
                         removed, collapsed whitespace, trimmed
classify(msg)         -> category string or nil
```

`classify` runs three passes per category keyword set, cheapest first, first hit
wins (deterministic priority order so "thanks for the directions" resolves
predictably):

1. **Whole-word** match against the normalized token list.
2. **Substring** match (e.g. "helloooo" contains "hello").
3. **Levenshtein ≤ 1**, only for short tokens (≤ 6 chars) to catch typos
   ("helo", "thsnks") without false positives on long words. Cap with an early
   exit so it stays O(token·keyword) and trivial.

Keyword sets live next to `npc_reactions.lua` (or as a `keywords` table inside
it) so content and triggers are edited together. Keep them in-world — match what
a roleplayer would actually type, not LFG/trade shorthand:

```lua
keywords = {
  greeting   = {"hello","hi","hey","heya","greetings","hail","well met","wave"},
  farewell   = {"bye","farewell","goodbye","later","safe travels","logging"},
  thanks     = {"thanks","thank you","cheers","much obliged","appreciate"},
  laugh      = {"haha","hah","lol","hehe"},
  directions = {"lost","how do i get","where is","which way","find my way"},
  lore       = {"who is","what is","tell me about","why does","history of"},
  taunt      = {"for the horde","for the alliance","coward","you'll fall"},
}
```

(Note: trade/LFG shorthand like `wts`/`wtb`/`lf` is intentionally **not** matched
— that's player-imitation behavior this module no longer simulates.)

#### Part C — Chat hooks

Register the relevant Eluna player chat events (verify the numeric IDs against
your mod-eluna build; canonical values shown):

| Event | ID | Signature |
|---|---|---|
| `PLAYER_EVENT_ON_CHAT` | 18 | `(event, player, msg, Type, lang)` — Say/Yell |
| `PLAYER_EVENT_ON_GUILD_CHAT` | 21 | `(event, player, msg, Type, lang, guild)` |
| `PLAYER_EVENT_ON_CHANNEL_CHAT` | 22 | `(event, player, msg, Type, lang, channel)` |

(Whisper/group intentionally skipped — no audience to simulate. Easy to add
later.) One shared handler:

```
onPlayerChat(event, player, msg, Type, lang, extra)
  if not enablePlayerInteraction then return end
  if msg sub(1,1) == "." then return end            -- ignore GM/commands
  local norm = normalize(msg)
  if #norm < 2 then return end                       -- ignore noise
  local guid = player:GetGUIDLow()

  -- 1) Continuing an open character<->player thread?
  if advanceThread(guid, norm) then return end       -- handled, done

  -- 2) Fresh classify
  local cat = classify(norm)
  if not cat then return end
  if onCooldown(guid) then return end                -- anti-spam
  if math.random(100) > replyChance then return end  -- not every line replies

  setCooldown(guid)
  dispatch(player, cat, channelOf(Type, extra))
```

Handlers **do not** return `false` — the player's own message passes through
normally; we only *add* a reply. `channelOf` decides whether to answer through
`formatWorld` vs `formatGuild` based on `Type`/which hook fired, so the reply
lands in the channel the player used.

#### Part D — Response scheduling

A reply that appears instantly reads as a bot. Use one-shot timers so it feels
like a person taking a moment to answer:

```
schedule(delayMs, fn) -> CreateLuaEvent(fn, delayMs, 1)   -- repeats = 1
```

- **Single reply:** `schedule(rand(replyDelay), emit)`.
- **Character↔character burst:** schedule each line at increasing offsets
  (`base + i*lineGap` with jitter), reusing the existing A/B speaker alternation
  so two distinct same-faction names trade lines.
- **Character→player thread:** emit `say` now-ish, then store thread state
  `{ expect=…, expires=now+threadTimeout }` keyed by GUID. The player's next
  message is routed by `advanceThread` before fresh classification.

**Player-validity guard (important):** the player may log out before a timer
fires. Capture `guid` (not the userdata) and re-fetch inside the closure:

```lua
schedule(delay, function()
    local p = GetPlayerByGUID(guid)        -- nil if gone
    if not p then return end
    local team = (p:GetTeam() == 0) and "alliance" or "horde"
    p:SendBroadcastMessage(formatWorld(nameFrom(team), substitute(line)))
end)
```

In multiplayer you may instead broadcast to all same-faction players via
`GetPlayersInWorld(team)`; default to replying to the triggering player only,
which is correct for the single-player target audience.

#### Part E — Per-player state

```lua
local pstate = {}   -- [guidLow] = { lastReply=ms, thread=nil|{expect,expires} }
```

- `onCooldown` / `setCooldown` read/write `lastReply` against
  `perPlayerCooldown`.
- `advanceThread` checks `thread` + `expires`; on match, emits the mapped reply
  and either clears the thread or installs the next step; on miss/expiry, clears
  silently (no nagging).
- **Cleanup:** `RegisterPlayerEvent(PLAYER_EVENT_ON_LOGOUT, fn)` →
  `pstate[guid] = nil`. Optional lazy sweep of expired threads on each inbound
  message to bound memory.

#### Part F — Faction logic

`team = player:GetTeam()` → `0 = Alliance`, `1 = Horde` → pool key
`"alliance"`/`"horde"`. Reply pool selection per category:

- `enableFactionChat == true` and a faction pool exists → use it, with a
  fallback to `shared` when empty.
- otherwise → `shared`.
- Cross-faction `taunt` only fires when `enableCrossFactionTaunts == true`, and
  uses the **opposite** faction's name pool so the heckler reads as the enemy.
  Keep these lines in-character (a sneering enemy soldier), never modern trash-talk.

#### Part G — Config

```lua
local enablePlayerInteraction  = true
local enableCrossFactionTaunts = false
local replyChance              = 65          -- percent chance a matched line gets a reply
local replyDelay               = {1200, 4000}-- ms, pause before first reply
local lineGap                  = {1500, 3500}-- ms, gap between burst lines
local perPlayerCooldown        = 8000        -- ms, min spacing between replies to one player
local threadTimeout            = 30000       -- ms, character<->player follow-up window
local replyToFactionRoom       = false       -- false=reply to player only; true=whole faction
```

#### Edge cases / correctness checklist

- Ignore messages starting with `.` (GM commands) and empty/normalized-too-short input.
- No recursion — replies use `Send*Message`, never real chat. (Verify by confirming the hook does not fire on our own output.)
- Re-fetch player by GUID inside every scheduled closure; bail if `nil`.
- Cooldown + `replyChance` to avoid spammy or bot-like behavior; cross-faction taunts off by default.
- Respect existing master switches (`enableScript`, `enableFactionChat`).
- Faction-pool fallback to `shared` when alliance/horde pool is missing/empty.
- Strip color codes/item links in `normalize` so `|cff…|Hitem:…|h[X]|h|r` doesn't break matching.
- Thread expiry clears silently; one open thread per player (a new classified greeting can replace it).
- Reuse `twoNames` for distinct A/B so a player-sparked burst doesn't read as one persona talking to itself.
- **In-character guard:** every reaction line stays inside the fiction. No real-world references, no meta, no LFG/trade transactional content. This is the whole point of the pivot — don't reintroduce player imitation through the reaction content.

#### Build order

1. **Utilities** — `normalize`, `levenshtein`, `classify`, `substitute`
   (extract placeholder substitution out of `t.dt` so replies can reuse it).
   Unit-testable with a small offline Lua harness.
2. **Content** — author `talk_text/npc_reactions.lua` with `keywords` +
   categories (greeting/farewell/thanks/laugh/directions/lore, taunt optional),
   covering shared/alliance/horde and at least one `npc_player` thread and one
   `npc_npc` burst. Keep every line in-character.
3. **Single replies** — config + `onPlayerChat` + `dispatch` + `schedule` for
   the base "hello → well met" case. Ship and test this alone first.
4. **Character↔character bursts** — staggered multi-line via existing renderer.
5. **Character↔player threads** — `pstate`, `advanceThread`, timeout + logout cleanup.
6. **Faction + cross-faction taunts** — wire `GetTeam` routing and the taunt flag.
7. **README** — document flags, the `npc_reactions.lua` authoring format, and the
   in-character rule.

#### Verification

- **Syntax/load:** `luac -p` (or `load`) every touched file; run the offline
  harness asserting `classify("Helloooo!")=="greeting"`, `classify("thsnks")=="thanks"`,
  `classify("random noise")==nil`, and that `normalize` strips a sample
  color-coded item link.
- **In-game matrix:** say "hello" (same-faction reply), spam "hi" repeatedly
  (cooldown holds), trigger a `directions` thread and answer the follow-up
  (advances) vs. wait it out (expires silently), fire a guild-channel keyword
  (replies in Guild), toggle `enablePlayerInteraction=false` (silent), toggle
  `enableCrossFactionTaunts` both ways, log out mid-delay (no error / no orphan
  reply).
- **Tone check:** read every reaction line aloud and confirm it would fit beside
  the ambient RP in `npc_text.lua` — if it sounds like a real player or a forum
  post, it doesn't ship.
- **Regression:** confirm ambient World/Guild timers still fire unchanged.

#### Open decisions

- **Reply audience** when more than one player is online: triggering player only
  (default) vs. whole faction. Single-player target says "player only".
- **Whisper support** — currently skipped; trivial to add a 19/`ON_WHISPER`
  hook that whispers back if you want a "a passing character pulls you aside"
  feel.
- Whether ambient character↔character exchanges should adopt the new staggered
  burst timing globally, or keep the current one-line-per-tick cadence and use
  bursts only for player-sparked exchanges.
- **Whether to build this at all.** Given the pivot toward pure ambient RP, the
  player-reply feature is optional. It can stay shelved indefinitely without
  affecting the core chatter — revisit only if you want light interactivity.
