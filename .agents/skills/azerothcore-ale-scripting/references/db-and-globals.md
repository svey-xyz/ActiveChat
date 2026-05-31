# ALE / Eluna global functions & database access

Globals live in the top-level namespace — call them anywhere, anytime (including at file load). Names verbatim from `azerothcore.org/eluna/Global`.

## Database access

Three databases, three function families:

| Family | Database | Holds |
|---|---|---|
| `World…` | `acore_world` | Static, designer-authored: templates, loot, NPC/GO/quest data, vendor lists |
| `Char…`  | `acore_characters` | Per-character state: characters, inventory, achievements, your `custom_*` tables |
| `Auth…`  | `acore_auth` | Accounts, bans, realm list |

Each family has three calls:

```lua
ALEQuery = WorldDBQuery(sql)      -- SYNCHRONOUS read; returns an ALEQuery or nil. Blocks the world thread.
           WorldDBExecute(sql)    -- fire-and-forget write (INSERT/UPDATE/DELETE); no return.
           WorldDBQueryAsync(sql, function(query) ... end)  -- non-blocking read; ALEQuery passed to callback.
```
…and identically `CharDBQuery`/`CharDBExecute`/`CharDBQueryAsync`, `AuthDBQuery`/`AuthDBExecute`/`AuthDBQueryAsync`.

**When to use which:** synchronous `…DBQuery` is fine in one-shot hooks (`ON_LOGIN`, a command) where a brief block is acceptable. **Never** call it on a hot path (`ON_AIUPDATE`, `WORLD_EVENT_ON_UPDATE`, per-tick) — it stalls the whole server. Use `…DBQueryAsync` or cache the value at login instead. Use `…DBExecute` for all writes that don't need a result.

### Iterating an ALEQuery result

```lua
local q = CharDBQuery("SELECT guid, name, level FROM characters WHERE online = 1")
if q then
    repeat
        local guid  = q:GetUInt32(0)   -- columns are 0-based, typed
        local name  = q:GetString(1)
        local level = q:GetUInt8(2)
        print(guid, name, level)
    until not q:NextRow()
end
```

`NextRow()` advances *past* the current row and returns `false` when there are no more — so the `repeat … until not q:NextRow()` shape reads row 0 first, then advances. Calling `NextRow()` before reading would skip the first row.

`ALEQuery` methods (column index is 0-based):
```
number  q:GetColumnCount()  /  q:GetRowCount()
boolean q:NextRow()                 -- advance; false when exhausted
table   q:GetRow()                  -- current row as { fieldName = value }
boolean q:IsNull(column)
-- typed getters, all (column):
q:GetBool, q:GetString, q:GetFloat, q:GetDouble,
q:GetUInt8, q:GetInt8, q:GetUInt16, q:GetInt16,
q:GetUInt32, q:GetInt32, q:GetUInt64, q:GetInt64
```
`GetRow()` is the convenience form: `local row = q:GetRow(); print(row.name)` — still iterate with `NextRow()`.

**Escape user input.** ALE has no parameterized-statement API in Lua, so build SQL carefully. Prefer integer values you control (GUIDs, entries) in interpolated SQL; for any player-supplied string, sanitize or avoid putting it in a query. Storing per-character/account data? Follow the `custom_*` table conventions from the `azerothcore-module-character-persistence` skill.

## Global functions by purpose

### Players
```
Player  GetPlayerByGUID(guid)        -- online player by GUID, or nil
Player  GetPlayerByName(name)        -- online player by name, or nil
number  GetPlayerCount()             -- players online
table   GetPlayersInWorld()          -- all online players
        SaveAllPlayers()
        Kick(player)  /  Ban(banMode, nameOrIP, duration, reason, whoBanned)
        SendMail(subject, text, receiverGUIDLow, senderGUIDLow, stationary [, delay, money, cod, ...itemEntries/counts])
```

### Messaging / logging
```
SendWorldMessage(message)            -- system message to every online player
PrintInfo(...)  /  PrintError(...)  /  PrintDebug(...)   -- to the worldserver log
RunCommand(command)                  -- run a console/GM command string
```

### Time & timed events
```
number  GetGameTime()                -- seconds
number  GetCurrTime()                -- server current time (ms-resolution)
number  GetTimeDiff(oldTime)
number  CreateLuaEvent(function, delay [, repeats])   -- delay ms (or {min,max}); repeats 0=infinite, default 1
                                                      -- callback gets (eventId, delay, repeats)
        RemoveEventById(eventId [, all_Events])
        RemoveEvents()               -- all global timed events
```

### Spawning
```
WorldObject PerformIngameSpawn(spawnType, entry, mapId, instanceId, x, y, z, o [, save, durorresptime, phase])
            -- spawnType: 1 = Creature, 2 = GameObject. save (default false) persists to DB. Returns the spawned object.
AddVendorItem(...)  /  VendorRemoveItem(...)  /  VendorRemoveAllItems(...)  /  AddTaxiPath(...)
```

### Lookups / templates
```
ItemTemplate GetItemTemplate(itemId)
string       GetItemLink(itemId)
Quest        GetQuest(questId)
SpellInfo    GetSpellInfo(spellId)
Map          GetMapById(id)         x,y,z,o GetMapEntrance(mapId)
string       GetAreaName(areaOrZoneId [, locale])
Guild        GetGuildByName(name)  /  GetGuildByLeaderGUID(guid)
             LookupEntry(store, id)   -- raw DBC store lookup
```

### Core / engine info
```
string  GetCoreName()  /  GetCoreVersion()  /  GetLuaEngine()
number  GetCoreExpansion()  /  GetRealmID()
string  GetConfigValue(name)         -- worldserver.conf value as string
        ReloadALE()                  -- reload all Lua scripts (was ReloadEluna)
boolean IsCompatibilityMode()        -- true = single-state, false = multistate
```
Multistate context (when scripts run per-map): `GetStateMap()`, `GetStateMapId()` (-1 for World), `GetStateInstanceId()` (0 for continents/World).

### GUID helpers
```
number  GetGUIDLow(guid)  /  GetGUIDType(guid)  /  GetGUIDEntry(guid)
        GetPlayerGUID(lowguid)  /  GetItemGUID(lowguid)  /  GetObjectGUID(lowguid, entry)  /  GetUnitGUID(lowguid, entry)
number  GetPackedGUIDSize(guid)
```

### Game events / world state
```
table   GetActiveGameEvents()
boolean IsGameEventActive(eventId)
        StartGameEvent(eventId [, force])  /  StopGameEvent(eventId [, force])
```

### Misc / bitwise / position checks
```
boolean IsInventoryPos(bag, slot)  /  IsEquipmentPos(bag, slot)  /  IsBagPos(...)  /  IsBankPos(...)
        bit_and(a,b)  /  bit_or(a,b)  /  bit_xor(a,b)  /  bit_not(a)  /  bit_lshift(a,b)  /  bit_rshift(a,b)
WorldPacket CreatePacket(opcode, size)
        CreateLongLong(...)  /  CreateULongLong(...)   -- 64-bit value objects
        HttpRequest(...)     -- non-blocking HTTP
```

## Quick conversions & constants worth knowing
- **Money:** 1 gold = 100 silver = 10000 copper. All money APIs are in copper.
- **Languages** (for `Say`/`SendUnitSay`): `0` = LANG_UNIVERSAL (everyone reads it). Use 0 for scripted NPC speech unless you specifically want faction-locked language.
- **Teams:** `GetTeam()` → `0` Alliance, `1` Horde (or use `IsAlliance()`/`IsHorde()`).
- **Common map IDs:** 0 Eastern Kingdoms, 1 Kalimdor, 530 Outland, 571 Northrend.
- `triggered = true` on `CastSpell` ignores cost, cooldown, and cast time — the usual choice for scripted casts.
