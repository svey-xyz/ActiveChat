# ALE / Eluna class method reference

Method **names** are verbatim from `azerothcore.org/eluna`. Signatures follow the documented ALE convention `obj:Method(args)`; optional args in `[brackets]`. For a method's exact arguments and return values, the per-method page is `https://www.azerothcore.org/eluna/<Class>/<Method>.html`. **Don't invent methods** — if it isn't here or on the live docs, it doesn't exist.

## Inheritance chain
`Player` → inherits `Unit` → `WorldObject` → `Object`.
`Creature` → inherits `Unit` → `WorldObject` → `Object`.
`GameObject` → inherits `WorldObject` → `Object`. `Item` → inherits `Object`.

So a method you can't find on `Player`'s own page is probably on `Unit`/`WorldObject`/`Object`. `GetEntry`/`GetGUID` live on `Object`; positions/distance/`GetMap` on `WorldObject`; health/combat/movement/`GetVictim`/`SetFaction` on `Unit`.

---

## Object (base)
Identity & casting:
```
number    obj:GetEntry()
string    obj:GetGUID()            -- packed 64-bit GUID string
number    obj:GetGUIDLow()         -- numeric low GUID (use as DB key)
number    obj:GetTypeId()
number    obj:GetScale()  /  obj:SetScale(scale)
boolean   obj:IsInWorld()  /  obj:IsPlayer()
Player    obj:ToPlayer()           -- downcasts; nil if not that type
Unit      obj:ToUnit()
Creature  obj:ToCreature()
GameObject obj:ToGameObject()
Corpse    obj:ToCorpse()
boolean   obj:HasFlag(index, flag)  /  obj:SetFlag(index, flag)  /  obj:RemoveFlag(index, flag)
```
Raw UpdateField access (rarely needed): `GetUInt32Value/SetUInt32Value(index[, value])`, plus `Byte/Int16/UInt16/Int32/UInt64/Float` variants.

## WorldObject (anything with a position)
Location:
```
Map     wo:GetMap()
number  wo:GetMapId()  /  wo:GetInstanceId()  /  wo:GetAreaId()  /  wo:GetZoneId()
number  wo:GetPhaseMask()  /  wo:SetPhaseMask(mask)
string  wo:GetName()
number  wo:GetX()  /  GetY()  /  GetZ()  /  GetO()
x,y,z,o wo:GetLocation()
```
Distance / facing / LoS: `GetDistance(targetOr x,y,z)`, `GetDistance2d`, `GetExactDistance`, `GetAngle`, `IsInFront(target, arc)`, `IsInBack`, `IsInMap`, `IsInRange/2d/3d`, `IsWithinDist/2d/3d`, `IsWithinDistInMap`, `IsWithinLoS(x,y,z)`.
Nearby queries:
```
Player    wo:GetNearestPlayer([range, hostile])
Creature  wo:GetNearestCreature([range, entry, hostile, dead])
GameObject wo:GetNearestGameObject([range, entry, hostile])
table     wo:GetPlayersInRange([range, hostile])
table     wo:GetCreaturesInRange([range, entry, hostile, dead])
table     wo:GetGameObjectsInRange([range, entry, hostile])
Object    wo:GetNearObject(...)  /  table wo:GetNearObjects(...)
```
Spawning / sound / timers:
```
Creature  wo:SpawnCreature(entry, x, y, z, o [, spawnType, despawnTimer])
GameObject wo:SummonGameObject(entry, x, y, z, o [, respawnDelay])
          wo:PlayDirectSound(soundId [, player])  /  PlayDistanceSound  /  PlayMusic
          wo:SendPacket(packet)
number    wo:RegisterEvent(function, delay, repeats)   -- per-object timer; callback (eventId, delay, repeats, worldobject); auto-removed on destroy
          wo:RemoveEventById(eventId)  /  wo:RemoveEvents()
```

## Unit (players, creatures, pets)
Health / power / level:
```
number  u:GetHealth()  /  u:SetHealth(amount)  /  u:GetMaxHealth()  /  u:SetMaxHealth(amount)
number  u:GetHealthPct()       boolean u:HealthAbovePct(pct) / HealthBelowPct(pct) / IsFullHealth()
number  u:GetPower([type])  /  u:SetPower(amount [, type])  /  u:ModifyPower  /  u:GetMaxPower  /  u:GetPowerType
number  u:GetLevel()  /  u:SetLevel(level)  /  u:GetStat(stat)
```
Identity / appearance:
```
number  u:GetClass()  / GetRace()  / GetGender()  / GetCreatureType()
string  u:GetClassAsString()  /  u:GetRaceAsString()
number  u:GetFaction()  /  u:SetFaction(factionId)
number  u:GetDisplayId()  /  u:SetDisplayId(modelId)  /  GetNativeDisplayId  /  SetNativeDisplayId  /  DeMorph()
        u:SetName(name)
        u:Mount(displayId)  /  u:Dismount()  /  boolean u:IsMounted()
```
Spells / auras:
```
        u:CastSpell(target, spellId, triggered)        -- triggered=true skips cost/cooldown/cast time
        u:CastCustomSpell(target, spellId, triggered, bp0, bp1, bp2, castItem, originalCaster)
        u:AddAura(spellId, target)
boolean u:HasAura(spellId)        Aura u:GetAura(spellId)
        u:RemoveAura(spellId)  /  u:RemoveAllAuras()  /  u:RemoveArenaAuras()
        u:InterruptSpell(type)  /  boolean u:IsCasting()
```
Combat / threat / movement:
```
        u:Attack(target [, meleeAttack])  /  u:AttackStop()
Unit    u:GetVictim()        table u:GetAttackers()
        u:Kill(target [, durabilityLoss])  /  u:DealDamage(target, amount)  /  u:DealHeal(...)
boolean u:IsAlive()  / IsDead()  / IsInCombat()
        u:ClearInCombat()  /  u:SetInCombatWith(enemy)
        u:AddThreat(target, amount)  /  GetThreat  /  GetThreatList  /  ClearThreatList  /  ModifyThreatPct
        u:MoveTo(id, x, y, z [, genPath])  /  MoveChase(target)  /  MoveFollow  /  MoveRandom  /  MoveHome  /  MoveStop  /  MoveClear
        u:NearTeleport(x, y, z, o)
        u:SetSpeed(moveType, rate [, forced])  /  number u:GetSpeed(type)
        u:SetRooted(bool)  /  SetConfused(bool)  /  SetFeared(bool)  /  SetWaterWalk(bool)
```
Chat / emotes / state:
```
        u:SendUnitSay(msg, language)  /  SendUnitYell(msg, language)  /  SendUnitEmote(...)  /  SendUnitWhisper(...)
        u:PerformEmote(emoteId)  /  u:EmoteState(emoteId)
        u:SetStandState(state)  /  number u:GetStandState()
        u:SetPvP(bool)  /  SetSanctuary(bool)  /  SetImmuneTo(...)
NPC-role checks: u:IsVendor() / IsTrainer() / IsBanker() / IsInnkeeper() / IsQuestGiver() / IsGossip() / IsAuctioneer() / IsBattleMaster() / IsGuildMaster() / IsTaxi() / IsSpiritHealer()
```

## Player (adds to Unit/WorldObject/Object)
Account / identity: `GetAccountId()`, `GetAccountName()`, `GetPlayerIP()`, `GetLatency()`, `GetTeam()`, `IsAlliance()`, `IsHorde()`, `GetChatTag()`.
Money / XP / honor:
```
number  p:GetCoinage()                  -- copper (1 gold = 10000)
        p:ModifyMoney(copper)           -- +/- ; p:SetCoinage(copper)
        p:GiveXP(xp [, victim])         number p:GetXP()
        p:GetHonorPoints()  / SetHonorPoints  / ModifyHonorPoints  / GetArenaPoints  / ModifyArenaPoints
        p:GetLifetimeKills()  /  GetTotalPlayedTime()  /  boolean p:IsMaxLevel()
```
Items / inventory:
```
Item    p:AddItem(entry [, count])
boolean p:RemoveItem(entryOrItem, count)
boolean p:HasItem(entry [, count, checkBank])
number  p:GetItemCount(entry [, checkBank])
Item    p:GetItemByEntry(entry)  /  GetItemByGUID(guid)  /  GetItemByPos(bag, slot)  /  GetEquippedItemBySlot(slot)
        p:EquipItem(item, slot)   boolean p:CanEquipItem(...)  /  p:CanUseItem(...)
number  p:GetInventoryFreeSlots()  /  GetBankFreeSlots()
        p:DurabilityRepairAll(...)  /  DurabilityRepair(...)  /  DurabilityLossAll(...)
        p:SendListInventory(npc)  /  SendShowBank(npc)  /  SendShowMailBox(...)
```
Quests: `AddQuest(entry)`, `RemoveQuest(entry)`, `CompleteQuest(entry)`, `FailQuest(entry)`, `RewardQuest(entry)`, `HasQuest(entry)`, `GetQuestStatus(entry)`, `SetQuestStatus(entry, status)`, `KilledMonsterCredit(entry[, guid])`, `AreaExploredOrEventHappens(quest)`, `HasQuestForItem(entry)`.
Teleport / location: `Teleport(mapId, x, y, z, o)`, `TeleportTo(...)`, `SummonPlayer(summoner, map, x, y, z, zoneId[, delay])`, `SetBindPoint(x, y, z, mapId, areaId)`, `StartTaxi(pathId)`, `SetCanFly(bool)`.
Messaging / chat:
```
        p:SendBroadcastMessage(msg)     -- system chat line to this player
        p:SendNotification(msg)         -- yellow flash on screen
        p:SendAreaTriggerMessage(msg)   -- middle-of-screen text
        p:Say(text, language)  /  p:Yell(text, language)  /  p:Whisper(text, language, receiver [, guid])
        p:TextEmote(text)  /  p:Mute(seconds)
```
Spells / talents / skills / cooldowns: `LearnSpell(id)`, `RemoveSpell(id)`, `HasSpell(id)`, `LearnTalent(...)`, `ResetTalents([noCost])`, `HasSkill(id)`, `SetSkill(id, step, value, max)`, `GetSkillValue(id)`, `HasSpellCooldown(id)`, `ResetSpellCooldown(id[, update])`, `ResetAllCooldowns()`.
Groups / guild: `GetGroup()`, `IsInGroup()`, `GroupInvite(player)`, `RemoveFromGroup()`, `GetGuild()`, `GetGuildId()`, `GetGuildName()`, `GetGuildRank()`, `SetGuildRank(rank)`, `IsInGuild()`.
Gossip (build menus from Lua):
```
        p:GossipMenuAddItem(icon, msg, sender, intid [, code, popup, money])
        p:GossipSendMenu(npcTextId, sender [, menuId])
        p:GossipClearMenu()  /  p:GossipComplete()  /  p:GossipAddQuests(source)
```
Pets: `GetPet()`, `SummonPet(...)`, `RemovePet(...)`, `CreatePet(...)`.
Reputation / titles / achievements: `GetReputation(faction)`, `SetReputation(faction, value)`, `GetReputationRank(faction)`, `HasTitle(id)`, `SetKnownTitle(id)`, `HasAchieved(id)`, `SetAchievement(id)`.
GM / lifecycle: `IsGM()`, `SetGameMaster(on)`, `IsGMVisible()`, `SetGMVisible(on)`, `KickPlayer()`, `LogoutPlayer(save)`, `SaveToDB()`, `RunCommand(cmd)`, `GetSelection()` (returns the player's target Unit), `GetTrader()`.
Settings / flags: `GetPlayerSettingValue(source, index)`, `UpdatePlayerSetting(source, index, value)`, `IsAFK()`, `ToggleAFK()`, `SetAtLoginFlag(flag)`.

## Creature (adds to Unit)
AI / threat / combat:
```
Unit    c:GetAITarget(targetType [, playerOnly, position, distance, aura])
            -- targetType: 0 RANDOM, 1 TOPAGGRO, 2 BOTTOMAGGRO, 3 NEAREST, 4 FARTHEST
table   c:GetAITargets()        number c:GetAITargetsCount()
        c:AttackStart(target)  /  c:SelectVictim()
        c:SetReactState(state)         number c:GetReactState()   -- 0 passive, 1 defensive, 2 aggressive
        c:SetInCombatWithZone()        -- pull all players in the instance
        c:CallForHelp(radius)  /  c:CallAssistance()  /  c:FleeToGetAssistance()
boolean c:IsInEvadeMode()  /  c:CanAggro()  /  c:HasSpell(spellId)  /  c:HasSpellCooldown(spellId)
```
Movement (plus inherited Unit movement): `MoveWaypoint()`, `GetCurrentWaypointId()`, `SetWalk(enable)`, `SetDisableGravity(disable)` (enables flying), `SetHover(enable)`, `GetHomePosition()`, `SetHomePosition(x,y,z,o)`, `SetWanderRadius(dist)`.
Flags / type: `SetNPCFlags(flags)` / `GetNPCFlags()`, `SetUnitFlags(flags)`, `GetRank()`, `GetCreatureFamily()`, `IsElite()`/`IsWorldBoss()`/`IsDungeonBoss()`/`IsGuard()`/`IsCivilian()`/`IsTrigger()`, `UpdateEntry(entry)` (morph into another template).
Spawn / despawn / equip:
```
        c:DespawnOrUnsummon([delay [, respawnTime]])   -- delay ms
        c:Respawn([force])  /  c:RemoveCorpse()
        c:SetRespawnDelay(delay)  /  c:SetCorpseDelay(delay)
        c:SetEquipmentSlots(mainHand, offHand, ranged) -- item entries; 0 unequips
        c:SaveToDB()        number c:GetSpawnId()  /  c:GetDBTableGUIDLow()
```
Loot: `GetLoot()`, `GetLootRecipient()`, `GetLootRecipientGroup()`, `HasLootRecipient()`, `IsTappedBy(player)`, `SetLootMode(mode)`/`GetLootMode()`.

## GameObject (adds to WorldObject)
State / use: `GetGoState()`/`SetGoState(state)` (0 active, 1 ready, 2 active_alt), `GetLootState()`/`SetLootState(state)`, `UseDoorOrButton([delay])`, `GetDisplayId()`, `IsActive()`, `IsSpawned()`, `IsTransport()`.
Spawn: `Despawn()`, `Respawn()`, `RemoveFromWorld([deleteFromDB])`, `SetRespawnTime(t)`, `SetRespawnDelay(d)`, `SaveToDB()`, `GetSpawnId()`.
Loot / quest: `AddLoot(entry, count)` (needs GO with `loot_template = 0`), `GetLootRecipient()`, `HasQuest(questId)`.

## Item (adds to Object)
Identity / template: `GetEntry()` (from Object), `GetItemTemplate()` → ItemTemplate, `GetItemLink([locale])`, `GetName()`, `GetQuality()`, `GetItemLevel()`, `GetClass()`, `GetSubClass()`, `GetInventoryType()`, `GetDisplayId()`, `GetItemSet()`, `GetRequiredLevel()`, `GetBuyPrice()`, `GetSellPrice()`.
Count / owner: `GetCount()`, `SetCount(count)`, `GetMaxStackCount()`, `GetOwner()` → Player, `GetOwnerGUID()`, `SetOwner(player)`.
Slot / binding: `GetSlot()`, `GetBagSlot()`, `IsEquipped()`, `IsInBag()`, `IsSoulBound()`, `SetBinding(bound)`, `CanBeTraded()`, `SaveToDB()`.
Enchant: `GetEnchantmentId(slot)`, `SetEnchantment(enchantId, slot)` → bool, `ClearEnchantment(slot)`.

## ItemTemplate / SpellInfo / Quest / Group / Guild / Map
These have their own read-mostly accessor pages (`GetName`, `GetQuality`, etc. on ItemTemplate; member management on Group/Guild; `GetMembers`, etc.). Look them up at `https://www.azerothcore.org/eluna/<Class>/index.html` when needed — they follow the same `obj:Method()` convention.
