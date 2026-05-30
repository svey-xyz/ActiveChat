--[[
  Lively World & Guild Chat -- faction-gated edition.

  Content lives in talk_text/npc_text.lua and talk_text/npc_text_guild.lua,
  each returning three pools:
      shared   -> broadcast to EVERYONE        (SendWorldMessage)
      alliance -> sent only to Alliance players (GetPlayersInWorld(0))
      horde    -> sent only to Horde players    (GetPlayersInWorld(1))

  Set enableFactionChat = false to fall back to the old behaviour, where every
  line (shared + alliance + horde merged) is broadcast to all players.

  Voice: this is CIVILIAN / GUARD / NPC ambience, not an imitation of real
  players. Lines should sound like a living city -- gossip, weather, work, rumor,
  lore -- never LFG/LFM, grouping requests, or gearscore/parse talk. The
  %role%/%difficulty%/%gearscore% tokens exist only for the rare adventurer
  voice; prefer the world/flavor tokens. See talk_text/npc_text.lua header.
]]--

local enableScript      = true  -- master on/off
local enableGuildChat   = true  -- guild channel on/off
local enableFactionChat = true  -- true = gate alliance/horde lines by faction
                                 -- false = legacy: broadcast everything to everyone

if enableScript then

-- Spam intervals (ms). 1 second = 1000.
local talk_time              = {1000, 10000}   -- shared WORLD chat
local guild_talk_time        = {10000, 30000}  -- shared GUILD chat
local faction_talk_time      = {8000, 20000}   -- faction WORLD chat (per faction)
local guild_faction_time     = {20000, 45000}  -- faction GUILD chat (per faction)

local ns = ""
-- Optional: a WorldDBQuery string to source NPC names from the DB.
-- If blank, names come from npc_name.lua.

local t = {}

-- Placeholder source tables -------------------------------------------------
local zones = {
    "Elwynn Forest", "Westfall", "Redridge Mountains", "Duskwood", "Loch Modan",
    "Wetlands", "Dun Morogh", "Searing Gorge", "Burning Steppes", "The Hinterlands",
    "Silverpine Forest", "Tirisfal Glades", "Western Plaguelands", "Eastern Plaguelands",
    "Hillsbrad Foothills", "Arathi Highlands", "Stranglethorn Vale", "Badlands",
    "Swamp of Sorrows", "The Blasted Lands", "Alterac Mountains", "Deadwind Pass",
    "Kalimdor", "Durotar", "Mulgore", "The Barrens", "Stonetalon Mountains",
    "Ashenvale", "Thousand Needles", "Desolace", "Dustwallow Marsh", "Feralas",
    "Tanaris", "Azshara", "Felwood", "Un'Goro Crater", "Moonglade", "Silithus",
    "Winterspring", "Darkshore", "Teldrassil", "Bloodmyst Isle", "Azuremyst Isle",
    "Ghostlands", "Eversong Woods", "Isle of Quel'Danas", "Hellfire Peninsula",
    "Zangarmarsh", "Terokkar Forest", "Nagrand", "Blade's Edge Mountains", "Netherstorm",
    "Shadowmoon Valley", "Borean Tundra", "Howling Fjord", "Dragonblight",
    "Grizzly Hills", "Zul'Drak", "Sholazar Basin", "The Storm Peaks", "Icecrown",
    "Crystalsong Forest", "Wintergrasp", "Mount Hyjal", "Vashj'ir", "Deepholm",
    "Uldum", "Twilight Highlands", "Tol Barad"
}

local instances = {
    -- Vanilla
    "RFC", "WC", "VC", "SFK", "BFD", "Stocks", "Gnomer", "RFK", "SM", "RFD",
    "Ulda", "ZF", "Mara", "ST", "BRD", "LBRS", "UBRS", "DM", "Strat", "Scholo",
    "MC", "Ony", "BWL", "ZG", "AQ20", "AQ40", "Naxx40", "Ony40",
    -- The Burning Crusade
    "Ramps", "BF", "SP", "UB", "MT", "AC", "Sethekk", "SLabs", "SV", "SH",
    "Bot", "Mech", "Arc", "MgT", "Kara", "Gruul's", "Maggi", "SSC", "TK",
    "Hyjal", "BT", "SWP",
    -- Wrath of the Lich King
    "UK", "Nexus", "AN", "AK", "DTK", "VH", "Gun", "HoS", "HoL", "Ocu", "UP",
    "ToC", "FoS", "PoS", "HoR", "Naxx", "OS", "EoE", "Uldu", "ToGC", "ICC", "RS",
    -- Full names
    "Ragefire Chasm", "Wailing Caverns", "The Deadmines", "Shadowfang Keep", "Blackfathom Deeps",
    "The Stockade", "Gnomeregan", "Razorfen Kraul", "Scarlet Monastery", "Razorfen Downs",
    "Uldaman", "Zul'Farrak", "Maraudon", "Temple of Atal'Hakkar", "Blackrock Depths",
    "Lower Blackrock Spire", "Upper Blackrock Spire", "Dire Maul", "Stratholme", "Scholomance",
    "Molten Core", "Onyxia's Lair", "Blackwing Lair", "Zul'Gurub", "Ruins of Ahn'Qiraj",
    "Temple of Ahn'Qiraj",
    "Hellfire Ramparts", "The Blood Furnace", "The Slave Pens", "The Underbog", "Mana-Tombs",
    "Auchenai Crypts", "Sethekk Halls", "Shadow Labyrinth", "The Steamvault", "The Shattered Halls",
    "The Botanica", "The Mechanar", "The Arcatraz", "Magisters' Terrace", "Karazhan",
    "Gruul's Lair", "Magtheridon's Lair", "Serpentshrine Cavern", "The Eye", "Battle for Mount Hyjal",
    "Black Temple", "Sunwell Plateau",
    "Utgarde Keep", "The Nexus", "Azjol-Nerub", "Ahn'kahet: The Old Kingdom", "Drak'Tharon Keep",
    "The Violet Hold", "Gundrak", "Halls of Stone", "Halls of Lightning", "The Oculus",
    "Utgarde Pinnacle", "Trial of the Champion", "The Forge of Souls", "Pit of Saron", "Halls of Reflection",
    "Naxxramas", "The Obsidian Sanctum", "The Eye of Eternity", "Ulduar", "Trial of the Crusader",
    "Onyxia's Lair", "Icecrown Citadel", "The Ruby Sanctum"
}

local roles        = {"Tank", "Healer", "DPS"}
local classes      = {"Warrior", "Mage", "Rogue", "Priest", "Hunter",
                      "Paladin", "Shaman", "Warlock", "Druid", "Death Knight"}
local battlegrounds = {"WG", "AV", "WSG", "AB", "Strand", "Isle of Conquest", "EoS"}

-- Expanded placeholder pools ------------------------------------------------
local professions = {
    "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism",
    "Inscription", "Jewelcrafting", "Leatherworking", "Mining", "Skinning",
    "Tailoring", "Cooking", "First Aid", "Fishing"
}

-- Gathering/profession activities as gerund phrases, so lines read naturally
-- (e.g. "Lots of folks out %activity% in %zone% cuz o' the %weather%").
local activities = {
    "fishing", "mining", "gathering", "collecting herbs", "skinning",
    "herbing", "prospecting", "farming mats", "picking herbs", "digging for ore",
    "cooking up a feast", "looking for fishing pools", "grinding for leather",
    "milling herbs", "disenchanting greens", "hunting for rare spawns",
    "smelting bars", "chasing gathering nodes"
}

-- Gathered goods --------------------------------------------------------------
-- Herbs (Herbalism), spanning Vanilla through WotLK.
local herbs = {
    "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn",
    "Stranglekelp", "Bruiseweed", "Kingsblood", "Liferoot", "Fadeleaf",
    "Goldthorn", "Khadgar's Whisker", "Dreamfoil", "Mountain Silversage",
    "Black Lotus", "Felweed", "Dreaming Glory", "Terocone", "Mana Thistle",
    "Goldclover", "Tiger Lily", "Talandra's Rose", "Adder's Tongue",
    "Lichbloom", "Icethorn", "Frost Lotus"
}

-- Ores & bars (Mining/Smelting), spanning Vanilla through WotLK.
local ores = {
    "Copper", "Tin", "Silver", "Iron", "Gold", "Mithril", "Truesilver",
    "Thorium", "Fel Iron", "Adamantite", "Khorium", "Cobalt", "Saronite",
    "Titanium"
}

-- Gems (cut/raw, via Mining & Jewelcrafting prospecting).
local gems = {
    "Cardinal Ruby", "King's Amber", "Majestic Zircon", "Dreadstone",
    "Ametrine", "Eye of Zul", "Scarlet Ruby", "Autumn's Glow", "Sky Sapphire",
    "Twilight Opal", "Monarch Topaz", "Forest Emerald", "Bloodstone",
    "Chalcedony", "Sun Crystal", "Shadow Crystal", "Huge Citrine",
    "Dark Jade", "Star of Elune", "Living Ruby"
}

-- Fish (Fishing & Cooking mats).
local fish = {
    "Deviate Fish", "Oily Blackmouth", "Firefin Snapper", "Stonescale Eel",
    "Nightfin Snapper", "Raw Glossy Mightfish", "Mottled Red Snapper",
    "Golden Darter", "Zangarian Sporefish", "Furious Crawdad", "Mr. Pinchy",
    "Dragonfin Angelfish", "Nettlefish", "Glacial Salmon", "Musselback Sculpin",
    "Fangtooth Herring", "Imperial Manta Ray", "Glassfin Minnow", "Pygmy Suckerfish"
}

-- World flavor ----------------------------------------------------------------
-- Famous lore figures (for gossip/rumor chatter: "Did you hear what %npc% did?").
local npcs = {
    "Thrall", "Jaina Proudmoore", "Sylvanas Windrunner", "Tirion Fordring",
    "Bolvar Fordragon", "Varian Wrynn", "Cairne Bloodhoof", "Vol'jin",
    "Garrosh Hellscream", "Magni Bronzebeard", "Tyrande Whisperwind",
    "Malfurion Stormrage", "Prophet Velen", "Lor'themar Theron",
    "Highlord Mograine", "Muradin Bronzebeard", "Genn Greymane",
    "Anduin Wrynn", "Brann Bronzebeard", "Highlord Fordragon"
}

-- Earned currencies (badges, emblems, marks). Civilian-safe: about reward/effort,
-- not gearscore. Spans TBC through WotLK.
local currencies = {
    "Emblem of Frost", "Emblem of Triumph", "Emblem of Conquest",
    "Emblem of Valor", "Emblem of Heroism", "Badge of Justice", "Honor",
    "Stone Keeper's Shards", "a Champion's Seal", "Venture Coins",
    "Dalaran Cooking Awards", "Dalaran Jewelcrafter's Tokens",
    "Spirit Shards", "Sidereal Essence"
}

-- Tavern food (pairs naturally with %shop% and %drink%).
local foods = {
    "a Dalaran Brownie", "Mulgore Spice Bread", "a Conjured Mana Strudel",
    "Spice Bread", "a Tasty Cupcake", "Delicious Chocolate Cake",
    "Baked Manta Ray", "Worg Tartare", "Roasted Quail", "Smoked Salmon",
    "Honey Bread", "a meat pie", "Cracker", "Mead Basted Caribou",
    "a Bobbing Apple", "Spiced Beef Jerky"
}

-- Tavern drinks.
local drinks = {
    "Thunder Ale", "Dwarven Stout", "Junglevine Wine", "Moonberry Juice",
    "Sweet Nectar", "Honeymint Tea", "Cherry Grog", "Rhapsody Malt",
    "a Bottle of Pinot Noir", "Conjured Crystal Water", "Skin of Dwarven Stout",
    "Ironforge Rations", "Gordok Green Grog", "a tankard of ale", "mulled wine"
}

-- Non-PvP / PvE titles (distinct from %pvptitle%: earned through deeds, not arenas).
local titles = {
    "the Explorer", "the Loremaster", "Jenkins", "the Seeker", "the Diplomat",
    "the Noble", "the Hallowed", "Brewmaster", "Chef", "the Pilgrim",
    "Master Angler", "the Astral Walker", "Twilight Vanquisher", "Elder",
    "Merrymaker", "the Magic Seeker", "Champion of the Frozen Wastes",
    "the Patient", "Salty", "Guardian of Cenarius"
}

-- Crafting mats other than the raw gatherables (cloth, leather, elementals, dusts).
local tradegoods = {
    "Frostweave Cloth", "Netherweave Cloth", "Heavy Borean Leather",
    "Borean Leather", "Arctic Fur", "Eternal Fire", "Eternal Water",
    "Eternal Life", "Eternal Earth", "Crystallized Earth", "Infinite Dust",
    "Greater Cosmic Essence", "Dream Shard", "Eternium Bar", "a Frozen Orb",
    "Primal Mooncloth", "Heavy Knothide Leather"
}

-- Vanity companion pets (sits nicely beside %critter%).
local companions = {
    "a Mechanical Squirrel", "Mini Diablo", "a Pandaren Monk",
    "an Onyxian Whelpling", "a Tiny Crimson Whelpling", "a Disgusting Oozeling",
    "a Sprite Darter Hatchling", "Lil' K.T.", "a Hyacinth Macaw",
    "a Calico Cat", "a Cockroach", "a Captured Firefly", "Pengu",
    "a Sinister Squashling", "an Albino Snake", "Speedy the turtle"
}

-- Gear enchantments (overheard crafting/enchanter chatter).
local enchants = {
    "Berserking", "Crusader", "Mongoose", "Icewalker", "Mighty Spellpower",
    "Blade Ward", "Blood Draining", "Greater Assault", "Superior Agility",
    "Tuskarr's Vitality", "Black Magic", "Accuracy", "Spellpower",
    "Titanweave", "Greater Inscription of the Pinnacle"
}

-- Novelty/fun items (joke toys and trinkets, not gear).
local toys = {
    "a Noggenfogger Elixir", "an Orb of Deception",
    "a Piccolo of the Flaming Fire", "a Gnomish Army Knife",
    "Decahedral Dwarven Dice", "Savory Deviate Delight",
    "a Carrot on a Stick", "the Robot Chicken", "a Hallowed Wand",
    "a Foam Sword Rack", "the Romantic Picnic Basket",
    "a Snowball", "a Faded Photograph", "a Spectral Tiger Cub figurine"
}

local cities = {
    "Stormwind", "Ironforge", "Darnassus", "The Exodar",
    "Orgrimmar", "Thunder Bluff", "Undercity", "Silvermoon City",
    "Shattrath City", "Dalaran", "Booty Bay"
}

local races = {
    "Human", "Dwarf", "Night Elf", "Gnome", "Draenei",
    "Orc", "Undead", "Tauren", "Troll", "Blood Elf"
}

-- Hostile native creatures/mobs (for "watch out for that %monster%"-style chatter).
local monsters = {
    "wolf", "murloc", "goblin", "owlbeast", "kobold", "gnoll", "harpy",
    "naga", "troll", "ogre", "raptor", "basilisk", "yeti", "furbolg",
    "quilboar", "satyr", "wendigo", "crocolisk", "vrykul", "spider"
}

-- Passive wildlife/critters (for ambient "a %critter% wandered by"-style chatter).
local critters = {
    "deer", "skunk", "rabbit", "squirrel", "fox", "boar", "cat", "chicken",
    "frog", "sheep", "cow", "prairie dog", "mouse", "toad", "crab", "ram",
    "fawn", "gazelle", "hare", "owl"
}

local bosses = {
    -- Vanilla
    "Ragnaros", "Onyxia", "Nefarian", "C'Thun", "Kel'Thuzad", "Hakkar",
    -- The Burning Crusade
    "Illidan Stormrage", "Kael'thas Sunstrider", "Lady Vashj", "Magtheridon",
    "Gruul the Dragonkiller", "Archimonde", "Kil'jaeden", "Prince Malchezaar",
    -- Wrath of the Lich King
    "The Lich King", "Yogg-Saron", "Algalon the Observer", "Mimiron", "Anub'arak",
    "Malygos", "Sartharion", "Lord Marrowgar", "Lady Deathwhisper",
    "Professor Putricide", "Sindragosa", "Deathbringer Saurfang", "Loatheb",
    "Thaddius", "Sapphiron"
}

local consumables = {
    "Flask of the Frost Wyrm", "Flask of Endless Rage", "Flask of Stoneblood",
    "Flask of Pure Mojo", "Potion of Speed", "Potion of Wild Magic",
    "Indestructible Potion", "Runic Healing Potion", "Runic Mana Potion",
    "Fish Feast", "Dragonfin Filet", "Spiced Mammoth Treats",
    "Runescroll of Fortitude", "Elixir of Mighty Agility", "Snapper Extreme",
    "Mighty Rejuvenation Potion"
}

local items = {
    "Shadowmourne", "Val'anyr, Hammer of Ancient Kings",
    "Thunderfury, Blessed Blade of the Windseeker", "Sulfuras, Hand of Ragnaros",
    "Atiesh, Greatstaff of the Guardian", "Warglaive of Azzinoth", "Quel'Delar",
    "Bryntroll, the Bone Arbiter", "Deathbringer's Will", "Death's Choice",
    "Phylactery of the Nameless Lich", "Glorenzelg, High-Blade of the Silver Hand",
    "Lana'thel's Lament", "Cryptmaker", "Distant Land"
}

local reps = {
    "Argent Crusade", "Knights of the Ebon Blade", "Kirin Tor",
    "The Wyrmrest Accord", "The Sons of Hodir", "The Frenzyheart Tribe",
    "The Oracles", "Argent Dawn", "Cenarion Circle", "Timbermaw Hold",
    "The Aldor", "The Scryers", "The Sha'tar", "Cenarion Expedition",
    "Keepers of Time", "Lower City", "Netherwing", "Ashtongue Deathsworn"
}

local mounts = {
    "Invincible", "Mimiron's Head", "Reins of the Onyxian Drake",
    "Reins of the Blue Proto-Drake", "Reins of the Time-Lost Proto-Drake",
    "Reins of the Raven Lord", "Reins of the Azure Drake", "Bronze Drake",
    "Reins of the Albino Drake", "Swift Zhevra", "Headless Horseman's Mount",
    "X-51 Nether-Rocket X-TREME", "Traveler's Tundra Mammoth", "Mechano-hog",
    "Swift Spectral Tiger"
}

local spells = {
    "Pyroblast", "Frostbolt", "Lay on Hands", "Bloodlust", "Heroism",
    "Hand of Protection", "Innervate", "Chaos Bolt", "Shadow Word: Death",
    "Killing Spree", "Hammer of Wrath", "Tranquility", "Mind Control",
    "Pillar of Frost", "Mortal Strike", "Starfall", "Mind Flay", "Penance"
}

local rares = {
    "Time-Lost Proto-Drake", "King Krush", "Loque'nahak", "Aotona", "Skoll",
    "Gondria", "Vyragosa", "Putridus the Ancient", "Old Crystalweaver",
    "Tukemuth", "High Thane Jorfus", "Hildana Deathstealer", "Griegen",
    "Dirkee", "Crazed Indu'le Survivor"
}

local pvptitles = {
    "the Kingslayer", "of the Nightfall", "the Undying", "the Insane",
    "Conqueror", "Justicar", "Battlemaster", "the Argent Champion",
    "Grand Marshal", "High Warlord", "the Flawless Victor", "Death's Demise",
    "of the Ashen Verdict", "the Patient", "Salty"
}

-- Action verbs for /emote-style lines (e.g. "Half of %city% started to %emote%").
local emotes = {
    "dance", "cheer", "salute", "bow", "wave", "laugh", "flex", "facepalm",
    "shrug", "sigh", "clap", "kneel", "roar", "point", "applaud", "groan"
}

-- Difficulty tags for raid/dungeon LFM chatter.
local difficulties = {
    "10-man", "25-man", "10-man Heroic", "25-man Heroic",
    "Normal", "Heroic", "10N", "25H"
}

-- Holiday & world events. Articles are baked in where the name needs one, so
-- lines read naturally with a bare "%event%" (e.g. "Everyone's here for %event%").
local events = {
    "Hallow's End", "Winter Veil", "Brewfest", "the Midsummer Fire Festival",
    "Noblegarden", "the Lunar Festival", "Love is in the Air", "Pilgrim's Bounty",
    "Children's Week", "the Harvest Festival", "the Darkmoon Faire",
    "the Day of the Dead", "Pirates' Day", "the Stranglethorn Fishing Extravaganza",
    "the Kalu'ak Fishing Derby", "the Scourge Invasion", "the Elemental Invasion"
}

local seasons = {
    "spring", "summer", "autumn", "winter",
    "high summer", "early spring", "late autumn", "the depths of winter"
}

local timesofday = {
    "dawn", "first light", "the early morning", "midday", "the afternoon",
    "dusk", "twilight", "the evening", "nightfall", "midnight",
    "the small hours before dawn"
}

-- Named taverns, inns, and shops (mostly real Azerothian establishments).
local shops = {
    "the Pig and Whistle Tavern", "the Blue Recluse", "the Gilded Rose",
    "the Lion's Pride Inn", "the Scarlet Raven Tavern", "the Stonefire Tavern",
    "the Legerdemain Lounge", "A Hero's Welcome", "the Filthy Animal",
    "the Salty Sailor Tavern", "the Wayfarer's Rest", "the World's End Tavern",
    "the Wyvern's Tail", "Thunderbrew Distillery", "the Broken Keg"
}

-- Travel routes and methods between places.
local routes = {
    "the Deeprun Tram", "the road to Goldshire", "the boat to Auberdine",
    "the zeppelin to Grom'gol", "the gryphon to Light's Hope Chapel",
    "the flight to Theramore", "the Dark Portal", "the road through Duskwood",
    "the ferry from Menethil Harbor", "the wind rider to Thunder Bluff",
    "the bat to the Sepulcher", "the long road through the Barrens",
    "the boat to Northrend", "the portal to Dalaran", "the tram to Ironforge"
}

-- Famous legends and stories of Azeroth (for "remember %tale%?"-style chatter).
local tales = {
    "the fall of Lordaeron", "the Culling of Stratholme", "Arthas's betrayal",
    "the opening of the Dark Portal", "the War of the Ancients", "the Sundering",
    "the Third War", "the death of Cenarius", "the founding of Dalaran",
    "the fall of Gnomeregan", "Illidan's imprisonment", "the rise of the Lich King",
    "the Battle for Mount Hyjal", "the legend of the Ashbringer",
    "the betrayal of the Defias Brotherhood", "the curse of the worgen",
    "the fall of the Lich King"
}

local weathers = {
    "rain", "snow", "fog", "clear skies", "a thunderstorm", "heavy mist",
    "a blizzard", "drizzle", "warm sunshine", "an overcast sky",
    "howling wind", "sleet"
}

local function selectRandomZone()         return zones[math.random(#zones)] end
local function selectRandomInstance()     return instances[math.random(#instances)] end
local function selectRandomRole()         return roles[math.random(#roles)] end
local function selectRandomClass()        return classes[math.random(#classes)] end
local function selectRandomBattleground() return battlegrounds[math.random(#battlegrounds)] end
local function selectRandomProfession()   return professions[math.random(#professions)] end
local function selectRandomActivity()      return activities[math.random(#activities)] end
local function selectRandomHerb()          return herbs[math.random(#herbs)] end
local function selectRandomOre()           return ores[math.random(#ores)] end
local function selectRandomGem()           return gems[math.random(#gems)] end
local function selectRandomFish()          return fish[math.random(#fish)] end
local function selectRandomNpc()           return npcs[math.random(#npcs)] end
local function selectRandomCurrency()      return currencies[math.random(#currencies)] end
local function selectRandomFood()          return foods[math.random(#foods)] end
local function selectRandomDrink()         return drinks[math.random(#drinks)] end
local function selectRandomTitle()         return titles[math.random(#titles)] end
local function selectRandomTradegood()     return tradegoods[math.random(#tradegoods)] end
local function selectRandomCompanion()     return companions[math.random(#companions)] end
local function selectRandomEnchant()       return enchants[math.random(#enchants)] end
local function selectRandomToy()           return toys[math.random(#toys)] end
local function selectRandomCity()         return cities[math.random(#cities)] end
local function selectRandomRace()         return races[math.random(#races)] end
local function selectRandomMonster()      return monsters[math.random(#monsters)] end
local function selectRandomCritter()      return critters[math.random(#critters)] end
local function selectRandomBoss()         return bosses[math.random(#bosses)] end
local function selectRandomConsumable()   return consumables[math.random(#consumables)] end
local function selectRandomItem()         return items[math.random(#items)] end
local function selectRandomRep()          return reps[math.random(#reps)] end
local function selectRandomMount()        return mounts[math.random(#mounts)] end
local function selectRandomSpell()        return spells[math.random(#spells)] end
local function selectRandomRare()         return rares[math.random(#rares)] end
local function selectRandomPvpTitle()     return pvptitles[math.random(#pvptitles)] end
local function selectRandomEmote()        return emotes[math.random(#emotes)] end
local function selectRandomDifficulty()   return difficulties[math.random(#difficulties)] end
local function selectRandomEvent()        return events[math.random(#events)] end
local function selectRandomSeason()       return seasons[math.random(#seasons)] end
local function selectRandomTimeOfDay()    return timesofday[math.random(#timesofday)] end
local function selectRandomShop()         return shops[math.random(#shops)] end
local function selectRandomRoute()        return routes[math.random(#routes)] end
local function selectRandomTale()         return tales[math.random(#tales)] end
local function selectRandomWeather()      return weathers[math.random(#weathers)] end

-- Numeric placeholders. Returned as game-formatted strings.
-- %gold%: realistic magnitudes, suffixed "g" (WoW convention).
local function selectRandomGold()
    local buckets = {{1, 50}, {25, 500}, {500, 5000}, {2000, 25000}}
    local b = buckets[math.random(#buckets)]
    return tostring(math.random(b[1], b[2])) .. "g"
end
-- %level%: a character level (low-end clamped so "level 1" is rare).
local function selectRandomLevel()      return tostring(math.random(2, 80)) end
-- %gearscore%: WotLK-era GearScore range, rounded to a tidy ten.
local function selectRandomGearscore()  return tostring(math.random(240, 600) * 10) end

-- Load content pools --------------------------------------------------------
local world = require("npc_text")        -- { shared/alliance/horde = {lines,duos,groups} }
local guild = require("npc_text_guild")

-- Flatten one or more typed pools ({lines, duos, groups}) into a single cursored
-- item list. Every item is tagged with its kind so the state machine knows how to
-- cast it: "line" = single speaker, "duo" = 2 alternating speakers, "group" = a
-- rotating cast of several voices. Cursor [0] = {itemIndex, lineIndex, ...}.
local function buildItems(...)
    local items = {[0] = {1, 1}}
    for _, pool in ipairs({...}) do
        if pool then
            for _, s  in ipairs(pool.lines  or {}) do items[#items + 1] = {kind = "line",  data = s}  end
            for _, c  in ipairs(pool.duos   or {}) do items[#items + 1] = {kind = "duo",   data = c}  end
            for _, gp in ipairs(pool.groups or {}) do items[#items + 1] = {kind = "group", data = gp} end
        end
    end
    return items
end

if enableFactionChat then
    t.t = {
        talk        = buildItems(world.shared),
        talk_alli   = buildItems(world.alliance),
        talk_horde  = buildItems(world.horde),
        guild_talk  = buildItems(guild.shared),
        guild_alli  = buildItems(guild.alliance),
        guild_horde = buildItems(guild.horde),
    }
else
    -- Legacy: everything to everyone.
    t.t = {
        talk       = buildItems(world.shared, world.alliance, world.horde),
        guild_talk = buildItems(guild.shared, guild.alliance, guild.horde),
    }
end

-- Name colour palette (class-ish colours).
t.cc = {"C79C6E","F58CBA","ABD473","FFF569","FFFFFF","C41F3B","0070DE","69CCF0","9482C9","FF7d0A"}

t.init = function(s)
    -- Seed the RNG ONCE, at startup. (The original reseeded on every line, which
    -- tied variety to the wall clock and made same-second bursts repeat.)
    math.randomseed(os.time())
    math.random(); math.random(); math.random()  -- discard first low-entropy values
    s.d = require("npc_name") or {}
    -- Backwards-compat: if a flat name list is supplied, treat it as neutral.
    if (s.d[1] ~= nil) then s.d = {neutral = s.d} end
    s.d.neutral  = s.d.neutral  or {}
    s.d.alliance = s.d.alliance or {}
    s.d.horde    = s.d.horde    or {}
    if (ns ~= "") then
        local q = WorldDBQuery(ns)
        if (q) then
            repeat
                table.insert(s.d.neutral, q:GetString(0))
            until not q:NextRow()
        end
    end
end
t:init()

-- Pick one name from a faction pool ("neutral"/"alliance"/"horde").
-- Falls back to neutral if the pool is missing or empty.
local function nameFrom(faction)
    local pool = t.d[faction]
    if (not pool) or (#pool == 0) then pool = t.d.neutral end
    return pool[math.random(#pool)]
end

-- Two DISTINCT names from the same pool, so a duo reads as a real two-person
-- exchange rather than one person talking to themselves.
local function twoNames(faction)
    local a = nameFrom(faction)
    local b = nameFrom(faction)
    local guard = 0
    while (b == a) and (guard < 12) do
        b = nameFrom(faction)
        guard = guard + 1
    end
    return a, b
end

-- A cast of up to `n` distinct names for a group discussion.
local function manyNames(faction, n)
    local pool = t.d[faction]
    if (not pool) or (#pool == 0) then pool = t.d.neutral end
    if (n > #pool) then n = #pool end
    local cast, seen, guard = {}, {}, 0
    while (#cast < n) and (guard < n * 20) do
        local nm = pool[math.random(#pool)]
        if (not seen[nm]) then seen[nm] = true; cast[#cast + 1] = nm end
        guard = guard + 1
    end
    if (#cast == 0) then cast[1] = nameFrom(faction) end
    return cast
end

-- Assign the cast for a freshly-started conversation item, based on its kind.
local function castFor(st, item, faction)
    if (item.kind == "duo") then
        local a, b = twoNames(faction)
        st.cast = {a, b}
    elseif (item.kind == "group") then
        st.cast = manyNames(faction, math.random(4, 6))  -- 4-6 voices
    end
    st.prev = nil
end

-- Choose the speaker for line `ti` of the current conversation item.
local function speakerFor(st, item, ti)
    if (item.kind == "duo") then
        -- strict alternation: odd line -> A, even line -> B
        return (ti % 2 == 1) and st.cast[1] or st.cast[2]
    else
        -- group: random cast member, but never the same voice twice in a row
        local pick, guard = st.cast[math.random(#st.cast)], 0
        while (pick == st.prev) and (#st.cast > 1) and (guard < 12) do
            pick = st.cast[math.random(#st.cast)]
            guard = guard + 1
        end
        return pick
    end
end

-- Start the next item and decide who speaks the first line. Cursor [0] holds
-- {itemIndex, lineIndex, cast, prev, speaker}.
t.fg = function(s, talkType, faction)
    local items = s.t[talkType]
    local st = items[0]
    local i = math.random(#items)
    st[1] = i
    st[2] = 1
    local item = items[i]
    if (item.kind == "line") then
        st.speaker = nameFrom(faction)            -- a single, standalone remark
        return item.data
    else
        castFor(st, item, faction)                -- fix this exchange's cast
        st.speaker = speakerFor(st, item, 1)
        st.prev    = st.speaker
        st[2] = 2
        return item.data[1]
    end
end

-- Produce the current chat text, advancing through conversation chains. Duos
-- alternate two speakers; groups rotate a larger cast (no immediate repeats).
t.dt = function(s, talkType, faction)
    local items = s.t[talkType]
    local st = items[0]
    local i  = st[1]
    local ti = st[2]
    local item = items[i]
    local txt = ""
    if (item.kind == "line") then
        txt = s:fg(talkType, faction)
    else
        if (#item.data < ti) then
            txt = s:fg(talkType, faction)         -- conversation done; begin a new item
        else
            if (not st.cast) then castFor(st, item, faction) end  -- cold start
            txt = item.data[ti]
            st.speaker = speakerFor(st, item, ti)
            st.prev    = st.speaker
            st[2] = ti + 1
        end
    end

    txt = string.gsub(txt, "%%zone%%",       selectRandomZone())
    txt = string.gsub(txt, "%%instance%%",   selectRandomInstance())
    txt = string.gsub(txt, "%%role%%",       selectRandomRole())
    txt = string.gsub(txt, "%%class%%",      selectRandomClass())
    txt = string.gsub(txt, "%%bg%%",         selectRandomBattleground())
    txt = string.gsub(txt, "%%profession%%", selectRandomProfession())
    txt = string.gsub(txt, "%%activity%%",   selectRandomActivity())
    txt = string.gsub(txt, "%%herb%%",       selectRandomHerb())
    txt = string.gsub(txt, "%%ore%%",        selectRandomOre())
    txt = string.gsub(txt, "%%gem%%",        selectRandomGem())
    txt = string.gsub(txt, "%%fish%%",       selectRandomFish())
    txt = string.gsub(txt, "%%npc%%",        selectRandomNpc())
    txt = string.gsub(txt, "%%currency%%",   selectRandomCurrency())
    txt = string.gsub(txt, "%%food%%",       selectRandomFood())
    txt = string.gsub(txt, "%%drink%%",      selectRandomDrink())
    txt = string.gsub(txt, "%%title%%",      selectRandomTitle())
    txt = string.gsub(txt, "%%tradegood%%",  selectRandomTradegood())
    txt = string.gsub(txt, "%%companion%%",  selectRandomCompanion())
    txt = string.gsub(txt, "%%enchant%%",    selectRandomEnchant())
    txt = string.gsub(txt, "%%toy%%",        selectRandomToy())
    txt = string.gsub(txt, "%%city%%",       selectRandomCity())
    txt = string.gsub(txt, "%%race%%",       selectRandomRace())
    txt = string.gsub(txt, "%%monster%%",    selectRandomMonster())
    txt = string.gsub(txt, "%%critter%%",    selectRandomCritter())
    txt = string.gsub(txt, "%%boss%%",       selectRandomBoss())
    txt = string.gsub(txt, "%%consumable%%", selectRandomConsumable())
    txt = string.gsub(txt, "%%item%%",       selectRandomItem())
    txt = string.gsub(txt, "%%rep%%",        selectRandomRep())
    txt = string.gsub(txt, "%%mount%%",      selectRandomMount())
    txt = string.gsub(txt, "%%spell%%",      selectRandomSpell())
    txt = string.gsub(txt, "%%rare%%",       selectRandomRare())
    txt = string.gsub(txt, "%%pvptitle%%",   selectRandomPvpTitle())
    txt = string.gsub(txt, "%%emote%%",      selectRandomEmote())
    txt = string.gsub(txt, "%%difficulty%%", selectRandomDifficulty())
    txt = string.gsub(txt, "%%gold%%",       selectRandomGold())
    txt = string.gsub(txt, "%%level%%",      selectRandomLevel())
    txt = string.gsub(txt, "%%gearscore%%",  selectRandomGearscore())
    txt = string.gsub(txt, "%%event%%",      selectRandomEvent())
    txt = string.gsub(txt, "%%season%%",     selectRandomSeason())
    txt = string.gsub(txt, "%%timeofday%%",  selectRandomTimeOfDay())
    txt = string.gsub(txt, "%%shop%%",       selectRandomShop())
    txt = string.gsub(txt, "%%route%%",      selectRandomRoute())
    txt = string.gsub(txt, "%%tale%%",       selectRandomTale())
    txt = string.gsub(txt, "%%weather%%",    selectRandomWeather())
    return txt
end

-- Formatting helpers --------------------------------------------------------
-- Name of the character who "spoke" the most recent line of a talk type
-- (set by t:dt / t:fg). Used to keep the displayed name in sync with the line.
local function lastSpeaker(talkType)
    return t.t[talkType][0].speaker
end

local function formatWorld(name, body)
    return string.format("|cFFFFC0C0[World] |r|cff%s|Hplayer:%s|h[%s]|h|r: |cFFFFC0C0%s|r",
        t.cc[math.random(#t.cc)], name, name, body)
end

local function formatGuild(name, body)
    return string.format("|cFF40FF40[Guild] |Hplayer:%s|h[%s]|h: %s|r", name, name, body)
end

-- Send a freshly generated line of `talkType` to every player on `team`
-- (0 = Alliance, 1 = Horde). Only advances the conversation cursor when at
-- least one player of that faction is online, so chains stay in sync.
local function broadcastFaction(team, faction, talkType, formatter)
    local players = GetPlayersInWorld(team)
    if (not players) or (next(players) == nil) then return end
    local body = t:dt(talkType, faction)         -- advances cursor & sets the speaker
    local msg  = formatter(lastSpeaker(talkType), body)
    for _, p in pairs(players) do
        p:SendBroadcastMessage(msg)
    end
end

-- Events --------------------------------------------------------------------
-- Shared WORLD chat: everyone hears it.
CreateLuaEvent(function()
    local body = t:dt("talk", "neutral")
    SendWorldMessage(formatWorld(lastSpeaker("talk"), body))
end, {talk_time[1], talk_time[2]}, 0)

-- Shared GUILD chat: everyone hears it.
if enableGuildChat then
    CreateLuaEvent(function()
        local body = t:dt("guild_talk", "neutral")
        SendWorldMessage(formatGuild(lastSpeaker("guild_talk"), body))
    end, {guild_talk_time[1], guild_talk_time[2]}, 0)
end

-- Faction-specific chat: only the matching faction hears it.
if enableFactionChat then
    -- Alliance world
    CreateLuaEvent(function()
        broadcastFaction(0, "alliance", "talk_alli", formatWorld)
    end, {faction_talk_time[1], faction_talk_time[2]}, 0)

    -- Horde world
    CreateLuaEvent(function()
        broadcastFaction(1, "horde", "talk_horde", formatWorld)
    end, {faction_talk_time[1], faction_talk_time[2]}, 0)

    if enableGuildChat then
        -- Alliance guild
        CreateLuaEvent(function()
            broadcastFaction(0, "alliance", "guild_alli", formatGuild)
        end, {guild_faction_time[1], guild_faction_time[2]}, 0)

        -- Horde guild
        CreateLuaEvent(function()
            broadcastFaction(1, "horde", "guild_horde", formatGuild)
        end, {guild_faction_time[1], guild_faction_time[2]}, 0)
    end
end

--[[
-- Optional: echo nearby /whispers and declined invites into world chat.
-- Left disabled (as in the original). Uncomment to enable.
RegisterServerEvent(5, function(_, p, w)
    local c = p:GetOpcode()
    if (c == 0x095) then
        local typ = p:ReadULong()
        local lng = p:ReadULong()
        local n   = p:ReadString()
        local m   = p:ReadString()
        if (typ == 7 and n ~= w:GetName()) then
            SendWorldMessage(string.format("|cFFFF80FF|Hplayer:%s|h[%s]|h whispered quietly:%s|r", n, n, m))
        end
    end
    if (c == 0x06E) then
        local n = p:ReadString()
        SendWorldMessage(string.format("%s declined your invitation.", n))
    end
    if (c == 0x069) then
        local n = p:ReadString()
        SendWorldMessage(string.format("%s declined your invitation.", n))
    end
end)
]]--

end
