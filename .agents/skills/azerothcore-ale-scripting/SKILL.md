---
name: azerothcore-ale-scripting
description: Authoritative patterns for writing ALE (formerly Eluna) Lua scripts for AzerothCore — event-hook registration, the Player/Creature/Unit/Item class API, gossip menus, custom commands, NPC AI, timed events, and direct DB access via ALEQuery. Use this skill whenever the user is writing, reviewing, or debugging a Lua script for an AzerothCore (or TrinityCore/MaNGOS) server — anything mentioning ALE, Eluna, mod-ale, lua_scripts, RegisterPlayerEvent, RegisterCreatureEvent, RegisterServerEvent, a function(event, player, ...) hook, gossip menus, WorldDBQuery or CharDBQuery, or "make an NPC/command/script that does X" on a WoW emulator. Trigger even when the user only describes the gameplay behavior (such as "when a player logs in, give them gold", "an NPC that teleports you", or "a vendor that sells X") without naming ALE/Eluna, since Lua-on-AzerothCore is the canonical signal. For C++ core modules or SQL persistence design instead, see the azerothcore-module-character-persistence skill.
---

# AzerothCore ALE / Eluna Lua scripting

ALE (the AzerothCore-maintained successor to **Eluna**) is a Lua engine for WoW emulators. It lets you bind Lua callbacks to game **events** ("hooks") and manipulate live game objects without recompiling the core. The historical name *Eluna* is still ubiquitous in the community, tutorials, and the docs URL (`azerothcore.org/eluna`); the runtime is identical except a few renames (`ReloadALE` was `ReloadEluna`, query objects are `ALEQuery` not `ElunaQuery`). Treat "ALE" and "Eluna" as the same thing.

Write scripts the way the engine actually works: register a handler for an event, receive the relevant game object as a Lua userdata, and call methods on it. The whole API is "events in, method calls out."

## Mental model — three things to get right

1. **Every script is a set of event registrations.** A `.lua` file in the server's script directory runs once at load; its job is to call `Register*Event(...)` with callback functions. The callbacks fire later when the game event happens.
2. **Every callback's first parameter is `event`** (the numeric event ID that fired), *then* the event-specific arguments. `function(event, player)`, `function(event, creature, target)`, etc. Forgetting the leading `event` parameter is the single most common bug — every argument ends up shifted by one.
3. **Objects are an inheritance chain.** `Player` is a `Unit` is a `WorldObject` is an `Object`. A `Player` can call any `Unit`/`WorldObject`/`Object` method. `Creature` shares the same chain. So `player:GetHealth()` (a Unit method) and `creature:SendUnitSay()` both work. When you can't find a method on the class's own doc page, look up the inheritance chain — `GetEntry`/`GetGUID` are on `Object`, position/`GetMap`/distance helpers are on `WorldObject`, combat/movement/`GetVictim`/`SetFaction` are on `Unit`.

## Installation & where scripts live

ALE is the `mod-ale` module. Install like any AzerothCore module, then place scripts so the server loads them:

```bash
cd azerothcore-wotlk/modules
git clone https://github.com/azerothcore/mod-ale.git mod-ale
# re-run cmake + build
```

Scripts go in the server's Lua script directory (commonly `lua_scripts/` next to the worldserver binary; configurable in the module `.conf`). Every `.lua` file there is loaded at startup. Reload at runtime from the worldserver console or in-game GM chat with `.reload ale` (or call `ReloadALE()` from Lua) — no restart needed, which makes iterating fast. Tell users to keep one feature per file and to watch the server log: ALE prints Lua errors there with file and line.

## Registering events — the registrar functions

All registrars live in the global namespace. Object-scoped ones take a leading **key** (entry / GUID / opcode / menu id); server-wide ones don't. All accept an optional trailing `shots` argument (`0` = fire forever, the default; `N` = fire N times then auto-unbind) and return a `cancel` function you can call to unbind.

```lua
-- server-wide:  Register<Scope>Event(eventId, handler [, shots])
RegisterPlayerEvent(3, OnLogin)                 -- 3 = PLAYER_EVENT_ON_LOGIN

-- entry-keyed:  Register<Scope>Event(key, eventId, handler [, shots])
RegisterCreatureEvent(70535, 4, OnBossDeath)    -- creature entry 70535, event 4 = ON_DIED
RegisterPlayerGossipEvent(60000, 1, OnGossipHello)  -- keyed by gossip menu_id
```

| Registrar | Key | Handler kind |
|---|---|---|
| `RegisterPlayerEvent(event, fn[, shots])` | — | Player events (`PlayerEvents`) |
| `RegisterServerEvent(event, fn[, shots])` | — | World/map/packet/auction/addon/game-event (`ServerEvents`) |
| `RegisterCreatureEvent(entry, event, fn[, shots])` | creature entry | Creature events (`CreatureEvents`) |
| `RegisterUniqueCreatureEvent(guid, instanceId, event, fn[, shots])` | one spawned creature | Creature events |
| `RegisterAllCreatureEvent(event, fn[, shots])` | — (all creatures) | Creature events |
| `RegisterGameObjectEvent(entry, event, fn[, shots])` | GO entry | GameObject events (`GameObjectEvents`) |
| `RegisterItemEvent(entry, event, fn[, shots])` | item entry | Item events (`ItemEvents`) |
| `RegisterCreatureGossipEvent(entry, event, fn[, shots])` | creature entry | Gossip events (`GossipEvents`) |
| `RegisterGameObjectGossipEvent(entry, event, fn[, shots])` | GO entry | Gossip events |
| `RegisterItemGossipEvent(entry, event, fn[, shots])` | item entry | Gossip events |
| `RegisterPlayerGossipEvent(menu_id, event, fn[, shots])` | gossip menu id | Gossip events |
| `RegisterMapEvent(map_id, event, fn[, shots])` | map id (all instances) | Map events |
| `RegisterInstanceEvent(map_id, event, fn[, shots])` | map id (one instance) | Map events |
| `RegisterPacketEvent(opcode, event, fn[, shots])` | opcode | Packet events |
| `RegisterBGEvent` / `RegisterGroupEvent` / `RegisterGuildEvent` / `RegisterSpellEvent(entry,...)` / `RegisterTicketEvent` | varies | their scope's events |

For the full event-ID enums and each callback's exact argument tail, see `references/events.md` — load it whenever you need a specific event number or aren't sure what arguments a hook receives. The most common ones (`ON_LOGIN=3`, `ON_LOGOUT=4`, `ON_FIRST_LOGIN=30`, `ON_CHAT=18`, `ON_COMMAND=42`, `ON_KILL_CREATURE=7`, `ON_LEVEL_CHANGE=13` for players; `ON_DIED=4`, `ON_ENTER_COMBAT=1`, `ON_AIUPDATE=7`, `ON_SPAWN=5` for creatures) are inlined there.

### Returning values to alter behavior

Many hooks let the callback **change or cancel** the default action by returning a value. This is how you block, modify, or override gameplay. Returning nothing leaves default behavior intact. Patterns (documented per-event in `references/events.md`):

- **Chat hooks** (`ON_CHAT`, whisper, etc.): `return false` to suppress the message; `return false, newMessage` to rewrite it.
- **Amount hooks** (`ON_GIVE_XP`, `ON_MONEY_CHANGE`, `ON_DAMAGE`, `ON_HEAL`, reputation): `return newAmount` to override the value.
- **Gate hooks** (`ON_CAN_INIT_TRADE`, `ON_CAN_JOIN_LFG`, `ON_CAN_GROUP_INVITE`, creature `ON_*` actions): `return false`/`return true` to allow/stop.
- **Gossip hooks**: `return false` to suppress the default action and take over the menu yourself.

## Common recipes

These are the shapes the great majority of requests reduce to. Adapt the entry IDs, coordinates, and messages.

### A custom chat command

```lua
-- ".myteleport" — works in-game; player is nil when run from server console.
local function OnCommand(event, player, command)
    if command == "myteleport" then
        if player then
            player:Teleport(0, -8833, 628, 94, 0)   -- Stormwind
            player:SendBroadcastMessage("Teleported!")
        end
        return false   -- we handled it; stop the core from reporting "unknown command"
    end
    -- return nothing for other commands so they pass through
end
RegisterPlayerEvent(42, OnCommand)   -- 42 = PLAYER_EVENT_ON_COMMAND
```

### A gossip NPC (menu + actions)

Gossip is two events on the same key: **hello** (1) builds the menu, **select** (2) reacts to a click. `intid` is the integer id you assigned to each option.

```lua
local NPC = 600000   -- creature_template entry of your NPC

local function OnHello(event, player, creature)
    player:GossipClearMenu()
    player:GossipMenuAddItem(0, "Heal me up", 0, 1)        -- icon, text, sender, intid
    player:GossipMenuAddItem(0, "Teleport to Dalaran", 0, 2)
    player:GossipMenuAddItem(0, "Nevermind", 0, 99)
    player:GossipSendMenu(1, creature)                      -- npc_text id, sender
end

local function OnSelect(event, player, creature, sender, intid, code, menu_id)
    if intid == 1 then
        player:SetHealth(player:GetMaxHealth())
    elseif intid == 2 then
        player:Teleport(571, 5807, 588, 660, 0)             -- Dalaran
    end
    player:GossipComplete()                                 -- close the window
end

RegisterCreatureGossipEvent(NPC, 1, OnHello)    -- 1 = GOSSIP_EVENT_ON_HELLO
RegisterCreatureGossipEvent(NPC, 2, OnSelect)   -- 2 = GOSSIP_EVENT_ON_SELECT
```

(The NPC still needs a `creature_template` row with `npcflag` including gossip (1) and a spawn; mention this to the user — Lua scripts the behavior, SQL creates the NPC.)

### Custom creature AI

```lua
local BOSS = 70535
local SPELL_NOVA = 12548

local function OnCombat(event, creature, target)
    creature:SendUnitYell("You dare challenge me?!", 0)
    creature:RegisterEvent(function(e, delay, repeats, c)
        if c and c:IsInCombat() then c:CastSpell(c:GetVictim(), SPELL_NOVA, true) end
    end, 8000, 0)   -- cast every 8s; per-object timer auto-cleans when the creature despawns
end

local function OnDeath(event, creature, killer)
    creature:SendUnitSay("Impossible...", 0)
end

RegisterCreatureEvent(BOSS, 1, OnCombat)   -- 1 = ON_ENTER_COMBAT
RegisterCreatureEvent(BOSS, 4, OnDeath)    -- 4 = ON_DIED
```

Prefer `creature:RegisterEvent` (a per-object timer) for repeating AI actions over `ON_AIUPDATE` (7), which fires every server tick (~tens of ms) and forces you to track timing by hand — only reach for `ON_AIUPDATE` when you genuinely need per-tick logic.

### Timed and delayed actions

`CreateLuaEvent(fn, delay, repeats)` is the global scheduler. `delay` is milliseconds (or a `{min,max}` table for a random delay), `repeats` is the count (`0` = infinite, default `1`). Its callback signature is the **exception** to the `(event, ...)` rule: it receives `(eventId, delay, repeats)`.

```lua
CreateLuaEvent(function() SendWorldMessage("Server restarting soon!") end, 60000, 0)  -- every 60s forever
local id = CreateLuaEvent(function() doThing() end, 5000, 1)  -- once after 5s
-- RemoveEventById(id) to cancel a global event early
```

For an action tied to a specific object's lifetime, use `worldobject:RegisterEvent(fn, delay, repeats)` instead — it's auto-removed when that object is destroyed, avoiding callbacks that fire on stale objects.

### Direct database access

Three databases, three function families: `World*` (`acore_world` — static templates/loot/NPC data), `Char*` (`acore_characters` — character state), `Auth*` (`acore_auth` — accounts). Each has `…DBQuery(sql)` (synchronous, returns an `ALEQuery` or `nil`), `…DBExecute(sql)` (fire-and-forget write), and `…DBQueryAsync(sql, callback)` (non-blocking read).

```lua
local q = CharDBQuery("SELECT guid, name FROM characters WHERE online = 1")
if q then
    repeat
        local guid = q:GetUInt32(0)        -- columns are 0-based
        local name = q:GetString(1)
        print(guid, name)
    until not q:NextRow()
end
```

Iterate with the `repeat … until not q:NextRow()` idiom — `NextRow()` advances *after* the current row, so calling it first would skip row 0. Column getters are typed and 0-indexed: `GetUInt32`, `GetInt32`, `GetUInt64`, `GetFloat`, `GetString`, `GetBool`, etc. (full list in `references/db-and-globals.md`). For storing per-character/account data, follow the table conventions in the `azerothcore-module-character-persistence` skill — same databases, same `custom_*` naming.

## Class API — where to look

The most-used methods, grouped by class with signatures, are in `references/classes.md`. Reach for it whenever you need to confirm a method exists or get its arguments — **don't guess method names**, since plausible-sounding ones often don't exist (e.g. it's `Player:ModifyMoney(copper)` not `AddGold`, `Unit:CastSpell(target, id, triggered)` not `Cast`). Highlights:

- **Player**: `AddItem(entry, count)`, `RemoveItem`, `GetItemCount`, `ModifyMoney(copper)` / `GetCoinage`, `GiveXP`, `Teleport(map,x,y,z,o)`, `SendBroadcastMessage`, `Say`/`Yell`/`Whisper`, `LearnSpell`, `AddQuest`/`GetQuestStatus`, `GetGroup`/`GetGuild`, `GossipMenuAddItem`/`GossipSendMenu`/`GossipComplete`, `IsGM`/`SetGameMaster`, `GetSelection`, `SaveToDB`.
- **Unit** (Player & Creature): `GetHealth`/`SetHealth`/`GetMaxHealth`/`GetHealthPct`, `GetLevel`, `CastSpell(target, id, triggered)`, `AddAura`/`HasAura`/`RemoveAura`, `Attack`/`Kill`/`GetVictim`, `MoveTo`/`NearTeleport`, `GetFaction`/`SetFaction`, `SendUnitSay`/`SendUnitYell`, `EmoteState`/`PerformEmote`.
- **WorldObject** (everything with a position): `GetX/Y/Z/O`, `GetMap`/`GetMapId`/`GetZoneId`/`GetAreaId`, `GetDistance`, `GetNearestPlayer`/`GetPlayersInRange`/`GetNearestCreature`, `SpawnCreature`, `SummonGameObject`, `RegisterEvent`.
- **Object** (base): `GetEntry`, `GetGUID`, `GetGUIDLow`, `ToPlayer`/`ToCreature`/`ToUnit` (downcasts; nil if wrong type).
- **Creature**: AI/threat (`GetAITarget`, `SetReactState`, `SetInCombatWithZone`), spawn (`DespawnOrUnsummon`, `Respawn`, `SetEquipmentSlots`), `UpdateEntry`.
- **Item / GameObject / ALEQuery**: see the reference.

Global utility functions (player lookup, spawning, messaging, time, core info, the DB families) are in `references/db-and-globals.md`.

## Idioms & pitfalls

- **Always include `event` as the first callback parameter.** `function(event, player)`, never `function(player)`. The mismatch is silent and shifts every argument.
- **Validate userdata before use.** Objects can be `nil` (offline player, despawned creature). Async DB callbacks and timed events are the worst offenders — re-fetch the player by GUID inside the callback rather than capturing the object, since it may have logged out: `local p = GetPlayerByGUID(guid); if not p then return end`.
- **`GetGUID()` returns a packed string; `GetGUIDLow()` returns the numeric low GUID** you use as a DB key. Don't mix them.
- **Money is in copper.** 1 gold = 10000 copper. `player:ModifyMoney(10000)` grants one gold; negative subtracts.
- **Spell casts: `CastSpell(target, spellId, triggered)`.** Pass `triggered = true` to skip cost/cooldown/cast-time — usually what you want for scripted effects.
- **Never block the world thread.** Avoid synchronous `…DBQuery` in hot paths (`ON_AIUPDATE`, per-tick). Cache on login, or use `…DBQueryAsync`. Synchronous queries are fine in one-shot hooks like `ON_LOGIN`.
- **Lua scripts behavior; SQL creates entities.** An NPC, GameObject, or item must exist in `*_template` + be spawned via SQL/`.npc add`/`PerformIngameSpawn`. Lua attaches logic to an existing entry — say so when a request needs both halves.
- **One file per feature, watch the log.** ALE reports Lua errors (with line numbers) to the worldserver log; `.reload ale` re-runs everything without a restart.
- **Don't invent methods.** If unsure a method exists, check `references/classes.md` or the live docs at `https://www.azerothcore.org/eluna/<Class>/index.html` rather than guessing. The per-method page is `…/<Class>/<Method>.html`.

## Authoritative documentation

- ALE API index: `https://www.azerothcore.org/eluna/` — class list; each class has an `index.html` listing its methods, and each method its own page.
- `Global` (all registrars + utilities): `https://www.azerothcore.org/eluna/Global/index.html`.
- mod-ale repo: `https://github.com/azerothcore/mod-ale`. Typed alternative (TypeScript→Lua): `https://github.com/azerothcore/eluna-ts`.
- Community examples: the `mod-eluna`/`mod-ale` and `eluna-scripts` repos, and AzerothCore Discord `#ale-ac`.
