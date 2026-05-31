# ALE / Eluna event reference

Every callback receives `event` (the numeric ID) as its **first argument**, then the tail shown in parentheses. IDs are stable across ALE/Eluna. Verified against `azerothcore.org/eluna/Global`. Where a hook can alter behavior, the return convention is noted.

Register with the matching registrar (see SKILL.md table). Object-scoped registrars take a leading key; e.g. `RegisterCreatureEvent(entry, 4, OnDied)`.

## Table of contents
- [PlayerEvents](#playerevents) — `RegisterPlayerEvent(event, fn)`
- [CreatureEvents](#creatureevents) — `RegisterCreatureEvent(entry, event, fn)` / `RegisterAllCreatureEvent` / `RegisterUniqueCreatureEvent`
- [GameObjectEvents](#gameobjectevents) — `RegisterGameObjectEvent(entry, event, fn)`
- [ItemEvents](#itemevents) — `RegisterItemEvent(entry, event, fn)`
- [GossipEvents](#gossipevents) — creature/GO/item/player gossip registrars
- [ServerEvents](#serverevents) — `RegisterServerEvent(event, fn)`
- [Map / Instance / Packet / BG / Group / Guild](#other-scopes)

---

## PlayerEvents
`RegisterPlayerEvent(eventId, fn [, shots])`. `player` is `nil` when the action comes from the server console (e.g. commands).

```
1  ON_CHARACTER_CREATE      (event, player)
2  ON_CHARACTER_DELETE      (event, guid)
3  ON_LOGIN                 (event, player)
4  ON_LOGOUT                (event, player)
5  ON_SPELL_CAST            (event, player, spell, skipCheck)
6  ON_KILL_PLAYER           (event, killer, killed)
7  ON_KILL_CREATURE         (event, killer, killed)
8  ON_KILLED_BY_CREATURE    (event, killer, killed)
9  ON_DUEL_REQUEST          (event, target, challenger)
10 ON_DUEL_START            (event, player1, player2)
11 ON_DUEL_END              (event, winner, loser, type)
12 ON_GIVE_XP               (event, player, amount, victim, source)   -- return new XP amount
13 ON_LEVEL_CHANGE          (event, player, oldLevel)
14 ON_MONEY_CHANGE          (event, player, amount)                   -- return new money amount
15 ON_REPUTATION_CHANGE     (event, player, factionId, standing, incremental) -- return new standing; -1 prevents gain
16 ON_TALENTS_CHANGE        (event, player, points)
17 ON_TALENTS_RESET         (event, player, noCost)
18 ON_CHAT                  (event, player, msg, Type, lang)          -- return false to mute; return false, newMsg to rewrite
19 ON_WHISPER               (event, player, msg, Type, lang, receiver)-- return false / false, newMsg
20 ON_GROUP_CHAT            (event, player, msg, Type, lang, group)   -- return false / false, newMsg
21 ON_GUILD_CHAT            (event, player, msg, Type, lang, guild)   -- return false / false, newMsg
22 ON_CHANNEL_CHAT          (event, player, msg, Type, lang, channel) -- return false / false, newMsg
23 ON_EMOTE                 (event, player, emote)
24 ON_TEXT_EMOTE            (event, player, textEmote, emoteNum, guid)
25 ON_SAVE                  (event, player)
26 ON_BIND_TO_INSTANCE      (event, player, difficulty, mapid, permanent)
27 ON_UPDATE_ZONE           (event, player, newZone, newArea)
28 ON_MAP_CHANGE            (event, player)
29 ON_EQUIP                 (event, player, item, bag, slot)
30 ON_FIRST_LOGIN           (event, player)        -- fires once, ever, per character
31 ON_CAN_USE_ITEM          (event, player, itemEntry)   -- return an InventoryResult to block
32 ON_LOOT_ITEM             (event, player, item, count)
33 ON_ENTER_COMBAT          (event, player, enemy)
34 ON_LEAVE_COMBAT          (event, player)
35 ON_REPOP                 (event, player)
36 ON_RESURRECT             (event, player)
37 ON_LOOT_MONEY            (event, player, amount)
38 ON_QUEST_ABANDON         (event, player, questId)
39 ON_LEARN_TALENTS         (event, player, talentId, talentRank, spellid)
42 ON_COMMAND               (event, player, command, chatHandler)  -- player nil from console; return false if you handled it
43 ON_PET_ADDED_TO_WORLD    (event, player, pet)
44 ON_LEARN_SPELL           (event, player, spellId)
45 ON_ACHIEVEMENT_COMPLETE  (event, player, achievement)
46 ON_FFAPVP_CHANGE         (event, player, hasFfaPvp)
47 ON_UPDATE_AREA           (event, player, oldArea, newArea)
48 ON_CAN_INIT_TRADE        (event, player, target)            -- return false to prevent
49 ON_CAN_SEND_MAIL         (event, player, receiverGuid, mailbox, subject, body, money, cod, item) -- return false to prevent
50 ON_CAN_JOIN_LFG          (event, player, roles, dungeons, comment) -- return false to prevent
51 ON_QUEST_REWARD_ITEM     (event, player, item, count)
52 ON_CREATE_ITEM           (event, player, item, count)
53 ON_STORE_NEW_ITEM        (event, player, item, count)
54 ON_COMPLETE_QUEST        (event, player, quest)
55 ON_CAN_GROUP_INVITE      (event, player, memberName)        -- return false to prevent
56 ON_GROUP_ROLL_REWARD_ITEM(event, player, item, count, voteType, roll)
57 ON_BG_DESERTION          (event, player, type)
58 ON_PET_KILL              (event, player, killer)
59 ON_CAN_RESURRECT         (event, player)
60 ON_CAN_UPDATE_SKILL      (event, player, skill_id)                 -- return true/false
61 ON_BEFORE_UPDATE_SKILL   (event, player, skill_id, value, max, step) -- return new value
62 ON_UPDATE_SKILL          (event, player, skill_id, value, max, step, new_value)
63 ON_QUEST_ACCEPT          (event, player, quest)
64 ON_AURA_APPLY            (event, player, aura)
65 ON_HEAL                  (event, player, target, heal)            -- return new heal
66 ON_DAMAGE                (event, player, target, damage)          -- return new damage
67 ON_AURA_REMOVE           (event, player, aura, remove_mode)
68 ON_MODIFY_PERIODIC_DAMAGE_AURAS_TICK (event, player, target, damage, spellInfo) -- return new damage
69 ON_MODIFY_MELEE_DAMAGE   (event, player, target, damage)          -- return new damage
70 ON_MODIFY_SPELL_DAMAGE_TAKEN (event, player, target, damage, spellInfo) -- return new damage
71 ON_MODIFY_HEAL_RECEIVED  (event, player, target, heal, spellInfo) -- return new heal
72 ON_DEAL_DAMAGE           (event, player, target, damage, damagetype) -- return new damage
73 ON_RELEASED_GHOST        (event, player)
```
(40, 41 unused.)

## CreatureEvents
`RegisterCreatureEvent(entry, eventId, fn [, shots])` binds all creatures of that template. `RegisterAllCreatureEvent(eventId, fn)` binds every creature (no key). `RegisterUniqueCreatureEvent(guid, instanceId, eventId, fn)` binds one spawned creature. Most action hooks `return true` to stop the default behavior.

```
1  ON_ENTER_COMBAT          (event, creature, target)        -- return true to stop
2  ON_LEAVE_COMBAT          (event, creature)                -- return true to stop
3  ON_TARGET_DIED           (event, creature, victim)        -- return true to stop
4  ON_DIED                  (event, creature, killer)        -- return true to stop
5  ON_SPAWN                 (event, creature)                -- return true to stop
6  ON_REACH_WP              (event, creature, type, id)      -- waypoint reached; return true to stop
7  ON_AIUPDATE              (event, creature, diff)          -- every tick; return true to stop
8  ON_RECEIVE_EMOTE         (event, creature, player, emoteid) -- return true to stop
9  ON_DAMAGE_TAKEN          (event, creature, attacker, damage) -- return true to stop; 2nd return = new damage
10 ON_PRE_COMBAT            (event, creature, target)        -- return true to stop
12 ON_OWNER_ATTACKED        (event, creature, target)        -- return true to stop
13 ON_OWNER_ATTACKED_AT     (event, creature, attacker)      -- return true to stop
14 ON_HIT_BY_SPELL          (event, creature, caster, spellid) -- return true to stop
15 ON_SPELL_HIT_TARGET      (event, creature, target, spellid)  -- return true to stop
19 ON_JUST_SUMMONED_CREATURE   (event, creature, summon)     -- return true to stop
20 ON_SUMMONED_CREATURE_DESPAWN(event, creature, summon)     -- return true to stop
21 ON_SUMMONED_CREATURE_DIED   (event, creature, summon, killer) -- return true to stop
22 ON_SUMMONED             (event, creature, summoner)       -- return true to stop
23 ON_RESET                (event, creature)
24 ON_REACH_HOME           (event, creature)                 -- return true to stop
26 ON_CORPSE_REMOVED       (event, creature, respawndelay)   -- return true to stop; 2nd return = new respawndelay
27 ON_MOVE_IN_LOS          (event, creature, unit)           -- sight range, not true LOS; return true to stop
30 ON_DUMMY_EFFECT         (event, caster, spellid, effindex, creature)
31 ON_QUEST_ACCEPT         (event, player, creature, quest)  -- return true
34 ON_QUEST_REWARD         (event, player, creature, quest, opt) -- return true
35 ON_DIALOG_STATUS        (event, player, creature)
36 ON_ADD                  (event, creature)
37 ON_REMOVE               (event, creature)
38 ON_AURA_APPLY           (event, creature, aura)
39 ON_HEAL                 (event, creature, target, heal)       -- return new heal
40 ON_DAMAGE               (event, creature, target, damage)     -- return new damage
41 ON_AURA_REMOVE          (event, creature, aura, remove_mode)
42 ON_MODIFY_PERIODIC_DAMAGE_AURAS_TICK (event, creature, target, damage, spellInfo) -- return new damage
43 ON_MODIFY_MELEE_DAMAGE  (event, creature, target, damage)     -- return new damage
44 ON_MODIFY_SPELL_DAMAGE_TAKEN (event, creature, target, damage, spellInfo) -- return new damage
45 ON_MODIFY_HEAL_RECEIVED (event, creature, target, heal, spellInfo) -- return new heal
46 ON_DEAL_DAMAGE          (event, creature, target, damage, damagetype) -- return new damage
```
(11, 16-18, 25, 28-29, 32-33 unused.)

## GameObjectEvents
`RegisterGameObjectEvent(entry, eventId, fn [, shots])`.

```
1  ON_AIUPDATE          (event, go, diff)
2  ON_SPAWN             (event, go)
3  ON_DUMMY_EFFECT      (event, caster, spellid, effindex, go)
4  ON_QUEST_ACCEPT      (event, player, go, quest)
5  ON_QUEST_REWARD      (event, player, go, quest, opt)
6  ON_DIALOG_STATUS     (event, player, go)
7  ON_DESTROYED         (event, go, attacker)
8  ON_DAMAGED           (event, go, attacker)
9  ON_LOOT_STATE_CHANGE (event, go, state)
10 ON_GO_STATE_CHANGED  (event, go, state)
12 ON_ADD              (event, go)
13 ON_REMOVE           (event, go)
14 ON_USE             (event, go, player)   -- return true to stop default use
```

## ItemEvents
`RegisterItemEvent(entry, eventId, fn [, shots])`.

```
1  ON_DUMMY_EFFECT  (event, caster, spellid, effindex, item)
2  ON_USE           (event, player, item, target)   -- return false to stop the item's spell cast
3  ON_QUEST_ACCEPT  (event, player, item, quest)
4  ON_EXPIRE        (event, player, itemid)
5  ON_REMOVE        (event, player, item)
```

## GossipEvents
Used by `RegisterCreatureGossipEvent(entry,…)`, `RegisterGameObjectGossipEvent(entry,…)`, `RegisterItemGossipEvent(entry,…)`, and `RegisterPlayerGossipEvent(menu_id,…)`.

```
1  GOSSIP_EVENT_ON_HELLO   (event, player, object)
       -- object is the Creature/GameObject/Item. Build the menu here. Return false for default action.
       -- NOTE: does nothing for RegisterPlayerGossipEvent (players have no "hello"); for item gossip, return false to stop the item's spell.
2  GOSSIP_EVENT_ON_SELECT  (event, player, object, sender, intid, code, menu_id)
       -- fires on option click. menu_id is only meaningful for player gossip. Return false for default action.
       -- `code` is the typed text when the option used a text box (popup); otherwise empty.
```

## ServerEvents
`RegisterServerEvent(eventId, fn [, shots])`. Spans world, map, packet, weather, auction, addon, and game-event domains.

```
5  SERVER_EVENT_ON_PACKET_RECEIVE   (event, packet, player)  -- player only if accessible; return false / false, newPacket
7  SERVER_EVENT_ON_PACKET_SEND      (event, packet, player)  -- return false / false, newPacket
8  WORLD_EVENT_ON_OPEN_STATE_CHANGE (event, open)
9  WORLD_EVENT_ON_CONFIG_LOAD       (event, reload)
11 WORLD_EVENT_ON_SHUTDOWN_INIT     (event, code, mask)
12 WORLD_EVENT_ON_SHUTDOWN_CANCEL   (event)
13 WORLD_EVENT_ON_UPDATE            (event, diff)            -- every world tick
14 WORLD_EVENT_ON_STARTUP           (event)
15 WORLD_EVENT_ON_SHUTDOWN          (event)
16 ALE_EVENT_ON_LUA_STATE_CLOSE     (event)                 -- just before ALE shutdown/reload
17 MAP_EVENT_ON_CREATE              (event, map)
18 MAP_EVENT_ON_DESTROY             (event, map)
21 MAP_EVENT_ON_PLAYER_ENTER        (event, map, player)
22 MAP_EVENT_ON_PLAYER_LEAVE        (event, map, player)
23 MAP_EVENT_ON_UPDATE              (event, map, diff)
24 TRIGGER_EVENT_ON_TRIGGER         (event, player, triggerId) -- areatrigger; return true to stop
25 WEATHER_EVENT_ON_CHANGE          (event, zoneId, state, grade)
26 AUCTION_EVENT_ON_ADD             (event, auctionId, owner, item, expireTime, buyout, startBid, currentBid, bidderGUIDLow)
27 AUCTION_EVENT_ON_REMOVE          (same args)
28 AUCTION_EVENT_ON_SUCCESSFUL      (same args)
29 AUCTION_EVENT_ON_EXPIRE          (same args)
30 ADDON_EVENT_ON_MESSAGE           (event, sender, type, prefix, msg, target) -- return false
31 WORLD_EVENT_ON_DELETE_CREATURE   (event, creature)
32 WORLD_EVENT_ON_DELETE_GAMEOBJECT (event, gameobject)
33 ALE_EVENT_ON_LUA_STATE_OPEN      (event)                 -- after all scripts loaded; good for one-time setup
34 GAME_EVENT_START                 (event, gameeventid)
35 GAME_EVENT_STOP                  (event, gameeventid)
```

## Other scopes
- **Map / Instance** — `RegisterMapEvent(map_id, event, fn)` (all instances) / `RegisterInstanceEvent(map_id, event, fn)` (one instance). InstanceEvents: `1 ON_INITIALIZE (event, instance_data, map)`, `2 ON_LOAD`, `3 ON_UPDATE (…, map, diff)`, `4 ON_PLAYER_ENTER (…, map, player)`, `5 ON_CREATURE_CREATE (…, map, creature)`, `6 ON_GAMEOBJECT_CREATE (…, map, go)`, `7 ON_CHECK_ENCOUNTER_IN_PROGRESS`.
- **Packet** — `RegisterPacketEvent(opcode, event, fn)`. Events `5 ON_PACKET_RECEIVE` / `7 ON_PACKET_SEND`, callback `(event, packet, player)`; return `false` / `false, newPacket`.
- **BattleGround / Group / Guild / Spell / Ticket** — `RegisterBGEvent(event, fn)`, `RegisterGroupEvent(event, fn)`, `RegisterGuildEvent(event, fn)`, `RegisterSpellEvent(entry, event, fn)`, `RegisterTicketEvent(event, fn)`. For their exact event IDs consult the live `Global` page — they're less commonly used; don't guess IDs.

## Unbinding
Each scope has a `Clear*Events` counterpart (`ClearPlayerEvents`, `ClearCreatureEvents(entry[, event])`, `ClearServerEvents`, …) that unbinds all of a scope's handlers or one event type. Alternatively, every `Register*Event` returns a `cancel` function — call it to unbind that single handler.
