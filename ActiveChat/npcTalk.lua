--[[
  Lively World Chat -- faction-gated edition.

  Content lives in talk_text/npc_text.lua, returning three pools:
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
local enableFactionChat = true  -- true = gate alliance/horde lines by faction
                                 -- false = legacy: broadcast everything to everyone

if enableScript then

-- Spam intervals (ms). 1 second = 1000.
local talk_time              = {1000, 10000}   -- shared WORLD chat
local faction_talk_time      = {8000, 20000}   -- faction WORLD chat (per faction)

-- Roster / selection-engine config. All configurable; see README.md
-- "Config reference". The roster starts empty and grows lazily on demand up to
-- maxCharacters, then self-balances (reuses existing voices) at the cap.
local maxCharacters           = 128   -- cap on the lazily-grown roster
local maxCharactersPerFaction = nil   -- optional per-faction sub-cap (nil = share maxCharacters)
local newCharacterWeight      = 8     -- virtual "spawn a new character" weight vs existing chattiness
local lineCooldownTicks       = 8     -- default per-line repeat cooldown (ticks), in the line scorer
local homeCityBias            = true  -- bias %city% toward the speaker's home city
local roleMoodMatchStrength   = 3.0   -- how hard role/mood matching is weighted (1 = off)
local areaMatchStrength       = 3.0   -- how hard area matching is weighted (1 = off)

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

-- ---------------------------------------------------------------------------
-- Tagged-content parser (Phase 3).
-- ---------------------------------------------------------------------------
-- buildItems flattens one or more typed pools ({lines, duos, groups}) into a
-- single cursored item list. Every item is tagged with its `kind` so the state
-- machine knows how to cast it: "line" = single speaker, "duo" = 2 alternating
-- speakers, "group" = a rotating cast of several voices. Cursor [0] holds
-- {itemIndex, lineIndex, ...} and is preserved as before.
--
-- Each authored entry may be (BACK-COMPATIBLY — see CHARACTERS_PLAN
-- "Authoring shape" / "Migration mechanics"):
--   * a bare string                -> untagged item (global wildcard).
--   * a table with [1] and no chain -> a tagged one-liner; [1] is the text and
--                                      named keys (roles/moods/areas/weight/
--                                      cooldown) are metadata.
--   * a table with chain={...}      -> a tagged duo/group; data = the chain
--                                      array, plus optional tags.
--   * a legacy {"a","b",...} array  -> an UNTAGGED chain (no `chain` key); the
--                                      whole array IS the chain. Detected by:
--                                      it came from the duos/groups list AND its
--                                      [1] is a string.
--
-- NORMALIZED INTERNAL ITEM SHAPE (relied on by Phase 4 + Phase 5):
--   item = {
--     kind      = "line" | "duo" | "group",
--     data      = <string>            for kind=="line"
--               | <array of strings>  for kind=="duo"/"group" (the chain),
--     roles     = <array of role keys> or nil  (nil = any role),
--     moods     = <array of mood keys> or nil  (nil = any personality),
--     areaGlobal= <bool>,             true  => fits ANY area (areas omitted),
--     areas     = <map area->weight>, ALWAYS a map (never a list) when
--                                     areaGlobal is false; areas absent from the
--                                     map are EXCLUDED. When areaGlobal is true
--                                     this is an empty map {} (ignored).
--     weight    = <number>,           base pick weight (default 1),
--     cooldown  = <number>,           min ticks before repeat (default
--                                     lineCooldownTicks),
--   }
-- The `areas` field is normalized AT PARSE TIME from any of: omitted
-- (=> areaGlobal=true, areas={}), a list {"city","rural"} (=> uniform weight 1
-- per listed area, areaGlobal=false), or a map {battlefield=3, rural=1}
-- (=> copied as-is, areaGlobal=false). Phase 4 reads areaGlobal/areas
-- uniformly: global => areaFactor 1.0; otherwise areas[char.area] or EXCLUDE.

-- Normalize an authored `areas` field into {areaGlobal, areas-map}.
local function normalizeAreas(areas)
    if (areas == nil) then
        return true, {}                         -- omitted => global / any area
    end
    local map = {}
    if (areas[1] ~= nil) then
        -- list form: {"city","rural"} -> uniform weight 1 per listed area.
        for _, a in ipairs(areas) do map[a] = 1 end
    else
        -- map form: {battlefield=3, rural=1} -> copy graded weights as-is.
        for a, w in pairs(areas) do map[a] = w end
    end
    return false, map
end

-- Wrap one authored entry (of the given kind) into the normalized item shape.
-- `entry` is either a bare string (line) or a table; `forceChain` is true for
-- entries coming from the duos/groups lists (so a legacy bare {"a","b"} array
-- is read as the whole chain rather than a tagged one-liner).
local function makeItem(kind, entry, forceChain)
    -- Bare string -> untagged item (line text, or — only meaningful for the
    -- lines list — a single-string entry).
    if (type(entry) == "string") then
        return {
            kind = kind, data = entry,
            roles = nil, moods = nil,
            areaGlobal = true, areas = {},
            weight = 1, cooldown = lineCooldownTicks,
        }
    end

    -- Table entry. Decide whether it carries an explicit chain, an implicit
    -- legacy chain, or is a tagged one-liner.
    local data
    if (entry.chain ~= nil) then
        data = entry.chain                       -- explicit tagged chain
    elseif (forceChain) and (type(entry[1]) == "string") then
        data = entry                             -- legacy untagged {"a","b",...}
    else
        data = entry[1]                          -- tagged one-liner: [1] is text
    end

    local areaGlobal, areaMap = normalizeAreas(entry.areas)
    return {
        kind = kind, data = data,
        roles = entry.roles, moods = entry.moods,
        areaGlobal = areaGlobal, areas = areaMap,
        weight = entry.weight or 1,
        cooldown = entry.cooldown or lineCooldownTicks,
    }
end

local function buildItems(...)
    local items = {[0] = {1, 1}}
    for _, pool in ipairs({...}) do
        if pool then
            for _, s  in ipairs(pool.lines  or {}) do items[#items + 1] = makeItem("line",  s,  false) end
            for _, c  in ipairs(pool.duos   or {}) do items[#items + 1] = makeItem("duo",   c,  true)  end
            for _, gp in ipairs(pool.groups or {}) do items[#items + 1] = makeItem("group", gp, true)  end
        end
    end
    return items
end

-- ---------------------------------------------------------------------------
-- Per-faction CANDIDATE item lists (Phase 4, decision 5).
-- ---------------------------------------------------------------------------
-- The candidate set is keyed by SPEAKER faction, not by channel:
--   * Alliance speaker -> candidates = shared U alliance.
--   * Horde speaker    -> candidates = horde only.
-- Every candidate carries an `audience` ORIGIN tag ("shared"|"alliance"|"horde")
-- so emission can route to the right listeners regardless of which speaker
-- voiced it:
--   shared   -> SendWorldMessage (everyone)
--   alliance -> Alliance players only
--   horde    -> Horde players only
-- This is how an Alliance character can voice either an everyone-visible
-- (shared) line OR an Alliance-only line from the SAME candidate set: the
-- chosen item's `audience` tag decides who hears it.
--
-- Legacy enableFactionChat=false: everything (shared+alliance+horde) is merged
-- into one candidate list, all tagged audience="shared" so it broadcasts to
-- everyone -- the old "everything to everyone" behaviour, now over characters.
--
-- buildItems already returns a list with a [0] cursor; we flatten that into a
-- plain 1..N array (the per-channel chain cursor is replaced in Phase 4 by a
-- per-cast conversation state, so the old [0] slot is dropped here) and stamp
-- each item's audience.
local function taggedItems(pool, audience)
    local out = {}
    local built = buildItems(pool)              -- has a [0] cursor we discard
    for i = 1, #built do
        local it = built[i]
        it.audience = audience
        out[#out + 1] = it
    end
    return out
end

local function mergeCandidates(...)
    local out = {}
    for _, list in ipairs({...}) do
        for _, it in ipairs(list) do out[#out + 1] = it end
    end
    return out
end

local allianceCandidates, hordeCandidates
if enableFactionChat then
    -- Alliance voices shared (everyone) + alliance (Alliance-only) lines.
    allianceCandidates = mergeCandidates(
        taggedItems(world.shared,   "shared"),
        taggedItems(world.alliance, "alliance"))
    -- Horde voices horde (Horde-only) lines only.
    hordeCandidates = taggedItems(world.horde, "horde")
else
    -- Legacy: everything merged, broadcast to everyone (audience="shared").
    -- Both factions draw from the same everyone-visible pool.
    allianceCandidates = mergeCandidates(
        taggedItems(world.shared,   "shared"),
        taggedItems(world.alliance, "shared"),
        taggedItems(world.horde,    "shared"))
    hordeCandidates = allianceCandidates
end

-- ===========================================================================
-- Character system data tables -- the roster's vocabulary of identities.
-- ---------------------------------------------------------------------------
-- These feed the lazily-generated in-memory roster: generateCharacter draws a
-- role (weighted), personality, and area-affinity from them, and the line
-- scorer matches a character's role/personality/area against the tags authored
-- on each line (see docs/plans/CHARACTERS_PLAN.md and README.md).
--
-- EXTENSIBILITY: roles, personalities and areas are each defined in exactly
-- ONE table below. To add a role/personality/area, edit only the relevant
-- table here -- no engine changes required (that's the whole point of keeping
-- this as flat data).
-- ===========================================================================

-- Locale affinities. SIX areas (locked decision): characters and (later) lines
-- carry one of these. Untagged lines are global; tagged lines are area-scoped.
local AREAS = { "city", "rural", "battlefield", "coast", "wilderness", "road" }

-- Civic/occupation archetypes. Each entry:
--   prefixes -> name prefixes for the "{Role} {first}" name pattern (Phase 2)
--   weight   -> roster-frequency weight (higher = appears more often)
--   area     -> default area affinity (biases area assignment at generation)
-- `area` MUST be one of AREAS.
local ROLES = {
    guard      = { prefixes = {"Guardsman", "Sentinel", "Watchman"},      weight = 7, area = "city" },
    citizen    = { prefixes = {"Citizen", "Townsfolk", "Commoner"},       weight = 9, area = "city" },
    vendor     = { prefixes = {"Merchant", "Trader", "Peddler"},          weight = 7, area = "city" },
    innkeeper  = { prefixes = {"Innkeep", "Barkeep", "Host"},             weight = 6, area = "city" },
    adventurer = { prefixes = {"Adventurer", "Wanderer", "Seeker"},       weight = 6, area = "wilderness" },
    soldier    = { prefixes = {"Sergeant", "Private", "Trooper"},         weight = 5, area = "battlefield" },
    mage       = { prefixes = {"Magus", "Archmage", "Conjurer"},          weight = 4, area = "city" },
    priest     = { prefixes = {"Father", "Sister", "Brother"},            weight = 4, area = "city" },
    craftsman  = { prefixes = {"Smith", "Mason", "Tinker"},               weight = 5, area = "city" },
    farmer     = { prefixes = {"Farmer", "Goodman", "Goodwife"},          weight = 6, area = "rural" },
    sailor     = { prefixes = {"Sailor", "Deckhand", "Bosun"},            weight = 4, area = "coast" },
    noble      = { prefixes = {"Lord", "Lady", "Baron"},                  weight = 3, area = "city" },
    drunkard   = { prefixes = {"Old", "Sloshed", "Tipsy"},                weight = 4, area = "city" },
    urchin     = { prefixes = {"Little", "Ragged", "Street"},             weight = 4, area = "city" },
}

-- Personality descriptors. Each maps to an epithet pool for the
-- "{first}, {epithet}" name pattern (Phase 2) and doubles as a line-selection
-- mood tag (Phase 4). 2-4 "the X" epithets per mood.
local PERSONALITIES = {
    warm     = { epithets = {"the Kind", "the Gentle", "the Warm"} },
    gruff    = { epithets = {"the Gruff", "the Surly", "the Blunt"} },
    cheerful = { epithets = {"the Merry", "the Jolly", "the Bright"} },
    weary    = { epithets = {"the Weary", "the Tired", "the Worn"} },
    wry      = { epithets = {"the Sly", "the Quick-Tongued", "the Wry"} },
    boastful = { epithets = {"the Great", "the Mighty", "the Boastful"} },
    nervous  = { epithets = {"the Jittery", "the Anxious", "the Skittish"} },
    solemn   = { epithets = {"the Solemn", "the Grave", "the Stoic"} },
    greedy   = { epithets = {"the Grasping", "the Miser", "the Greedy"} },
    kindly   = { epithets = {"the Kindly", "the Good", "the Tender"} },
    bitter   = { epithets = {"the Bitter", "the Sour", "the Jaded"} },
    dreamy   = { epithets = {"the Dreamer", "the Wistful", "the Distant"} },
    brave    = { epithets = {"the Brave", "the Bold", "the Fearless"} },
    cowardly = { epithets = {"the Timid", "the Craven", "the Faint-Hearted"} },
    gossipy  = { epithets = {"the Talkative", "the Nosy", "the Gossip"} },
}
-- ===========================================================================

-- ===========================================================================
-- Roster state -- lazily-grown, in-memory ONLY.
-- ---------------------------------------------------------------------------
-- These tables live solely in Lua memory: they are NEVER persisted to any DB
-- or file, and are RESET on every server restart (the roster regrows lazily
-- from empty as chatter is emitted -- see CHARACTERS_PLAN.md "lazy growth").
--   roster          -> flat array of every generated character
--   rosterByFaction -> the same characters bucketed by faction for fast picks
--   usedNames       -> set of display names already in use (dedup guard)
-- generateCharacter fills them; resolveSpeaker/pickCharacter read them.
-- ===========================================================================
local roster          = {}
local rosterByFaction = { alliance = {}, horde = {} }
local usedNames       = {}

-- Home-city pools, split by faction (locked decision: neutral hubs like
-- Dalaran / Shattrath / Booty Bay are travel/sanctuary hubs, NOT a home city,
-- so they are deliberately excluded here even though they exist in `cities`).
local allianceCities = {"Stormwind", "Ironforge", "Darnassus", "The Exodar"}
local hordeCities     = {"Orgrimmar", "Thunder Bluff", "Undercity", "Silvermoon City"}

-- Pre-compute the list of role/personality keys once (cheap, stable) so
-- generation can index them uniformly. ROLES is weighted; PERSONALITIES is
-- picked uniformly.
local roleKeys = {}
for k in pairs(ROLES)         do roleKeys[#roleKeys + 1] = k end
local moodKeys = {}
for k in pairs(PERSONALITIES) do moodKeys[#moodKeys + 1] = k end

-- generateName(faction, role, personality) -> display string.
-- Builds one of four weighted name patterns (see CHARACTERS_PLAN "Name
-- generation"): {first last} ~55%, {Role first} ~20%, {first, epithet} ~15%,
-- {first} bare ~10%. First names come from t.d[faction] (alliance|horde),
-- surnames from t.d.surnames. Deduped against usedNames with a bounded retry;
-- after ~12 tries we accept a collision (only realistic once the pool is
-- exhausted). RNG is seeded once in t.init.
local function pickFrom(list)
    return list[math.random(#list)]
end

local function buildName(faction, role, personality)
    local firsts   = t.d[faction]
    if (not firsts) or (#firsts == 0) then firsts = t.d.surnames end
    local first    = pickFrom(firsts)
    local roll     = math.random(100)
    if (roll <= 55) then
        -- {first} {last} (~55%)
        return first .. " " .. pickFrom(t.d.surnames)
    elseif (roll <= 75) then
        -- {Role} {first} (~20%)
        local prefixes = ROLES[role] and ROLES[role].prefixes
        if (prefixes) and (#prefixes > 0) then
            return pickFrom(prefixes) .. " " .. first
        end
        return first .. " " .. pickFrom(t.d.surnames)  -- defensive fallback
    elseif (roll <= 90) then
        -- {first}, {epithet} (~15%)
        local epithets = PERSONALITIES[personality] and PERSONALITIES[personality].epithets
        if (epithets) and (#epithets > 0) then
            return first .. ", " .. pickFrom(epithets)
        end
        return first  -- defensive fallback
    else
        -- {first} bare (~10%)
        return first
    end
end

local function generateName(faction, role, personality)
    local name, guard = nil, 0
    repeat
        name  = buildName(faction, role, personality)
        guard = guard + 1
    until (not usedNames[name]) or (guard >= 12)
    return name
end

-- Weighted roulette over ROLES by their .weight field -> a role key.
local function pickRoleWeighted()
    local total = 0
    for _, k in ipairs(roleKeys) do total = total + (ROLES[k].weight or 1) end
    local r, acc = math.random() * total, 0
    for _, k in ipairs(roleKeys) do
        acc = acc + (ROLES[k].weight or 1)
        if (r <= acc) then return k end
    end
    return roleKeys[#roleKeys]  -- float-rounding fallback
end

-- generateCharacter(faction) -> a full character table (see CHARACTERS_PLAN
-- "The character model"), registered into roster / rosterByFaction with its
-- name marked used. faction is "alliance" | "horde".
--
-- The maxCharacters cap is enforced in resolveSpeaker (which decides whether to
-- spawn at all); generateCharacter here unconditionally builds and registers a
-- character -- it does NOT enforce the cap.
local function generateCharacter(faction)
    local role        = pickRoleWeighted()
    local personality = moodKeys[math.random(#moodKeys)]

    -- area: a locale AFFINITY biased toward the role's default area (~65%),
    -- else a uniformly random AREAS member -- so the roster reads as roughly
    -- role-typed without being rigid (see CHARACTERS_PLAN "area is a locale
    -- affinity ... plus randomness").
    -- FUTURE HOOK: derive effective area from a real player's current zone for
    -- true zone-specific chatter (see CHARACTERS_PLAN decision 3). v1 uses
    -- this static affinity only.
    local area
    if (math.random() < 0.65) and (ROLES[role].area) then
        area = ROLES[role].area
    else
        area = AREAS[math.random(#AREAS)]
    end

    local homeCity = (faction == "horde")
        and pickFrom(hordeCities)
        or  pickFrom(allianceCities)

    local character = {
        name         = generateName(faction, role, personality),
        faction      = faction,
        role         = role,
        personality  = personality,
        area         = area,
        homeCity     = homeCity,
        chattiness   = math.random(),   -- 0..1 selection weight (RNG seeded in t.init)
        friendliness = math.random(),   -- 0..1 likelihood to join a duo/group
        color        = t.cc[math.random(#t.cc)],  -- stable per-character name colour
    }

    -- Register. (rosterByFaction[faction] is guaranteed for alliance/horde.)
    roster[#roster + 1] = character
    local bucket = rosterByFaction[faction]
    bucket[#bucket + 1] = character
    usedNames[character.name] = true
    return character
end

-- ===========================================================================
-- Roster-query seam (Phase 3) -- decision 9.
-- ---------------------------------------------------------------------------
-- Two thin functions funnel all speaker selection so the future
-- player-interaction responder (PLAYER_INTERACTION_PLAN.md) can reuse them and
-- draw a KNOWN recurring resident from this same roster:
--
--   pickCharacter(weightField, filters) -> character | nil
--       Picks an EXISTING character only (never spawns). Weighted-random by the
--       numeric `weightField` ("chattiness" | "friendliness"); returns nil when
--       no candidate matches.
--   resolveSpeaker(faction) -> character
--       Weighted pick over existing characters (weight=chattiness) PLUS one
--       virtual "new character" slot (weight=newCharacterWeight); lazily spawns
--       under the cap. This is the ambient-initiator entry point.
-- ===========================================================================

-- pickCharacter(weightField, filters) -- EXISTING-ONLY weighted pick.
--   weightField : "chattiness" | "friendliness" (the numeric roulette weight).
--   filters (all optional):
--     faction     -- restrict to rosterByFaction[faction] (else the whole roster)
--     role        -- char.role must equal this
--     mood        -- char.personality must equal this
--     area        -- char.area must equal this
--     excludeName -- skip the character with this display name (dedup vs initiator)
--     allowSpawn  -- IGNORED here: pickCharacter NEVER spawns; it is the
--                    existing-only primitive. The flag is consumed by CALLERS
--                    (e.g. cast assembly / a player responder) and by
--                    resolveSpeaker, which decide whether to fall back to a
--                    spawn when pickCharacter returns nil. Documented so callers
--                    can pass a uniform filter table.
-- Returns a character, or nil if no existing character matches.
local function pickCharacter(weightField, filters)
    filters = filters or {}
    local source = filters.faction and rosterByFaction[filters.faction] or roster
    if (not source) then return nil end

    -- Build the candidate list + summed weight in one pass.
    local candidates, total = {}, 0
    for _, c in ipairs(source) do
        if  ((not filters.role)        or (c.role == filters.role))
        and ((not filters.mood)        or (c.personality == filters.mood))
        and ((not filters.area)        or (c.area == filters.area))
        and ((not filters.excludeName) or (c.name ~= filters.excludeName)) then
            local w = c[weightField] or 0
            if (w > 0) then
                candidates[#candidates + 1] = c
                total = total + w
            end
        end
    end
    if (#candidates == 0) or (total <= 0) then return nil end

    -- Weighted roulette.
    local r, acc = math.random() * total, 0
    for _, c in ipairs(candidates) do
        acc = acc + (c[weightField] or 0)
        if (r <= acc) then return c end
    end
    return candidates[#candidates]  -- float-rounding fallback
end

-- Cap helpers. maxCharacters is the global cap; maxCharactersPerFaction (when
-- non-nil) is an additional per-faction sub-cap counted over
-- rosterByFaction[faction].
local function rosterAtCap(faction)
    if (#roster >= maxCharacters) then return true end
    if (maxCharactersPerFaction ~= nil)
        and (#rosterByFaction[faction] >= maxCharactersPerFaction) then
        return true
    end
    return false
end

-- resolveSpeaker(faction) -- ambient initiator (decision 6). Weighted roulette
-- over each existing same-faction character (weight = chattiness) PLUS one
-- virtual "new character" slot (weight = newCharacterWeight):
--   * pick == virtualNew and roster under cap -> spawn + register + speak now.
--   * pick == virtualNew at the cap           -> fall back to reuse an existing
--                                                 character (pickCharacter).
--   * else                                     -> return the picked existing char.
-- Cold start (empty roster) ALWAYS spawns: the virtual slot is the only
-- candidate. Spawning is self-balancing -- as summed chattiness grows the
-- virtual slot wins less often, so growth tapers and halts at the cap.
--
-- For `shared` (everyone-visible) ticks the alliance-driver calls
-- resolveSpeaker("alliance"), so an everyone-visible line is always
-- Alliance-voiced (decision 5).
local function resolveSpeaker(faction)
    local bucket = rosterByFaction[faction] or {}

    -- Summed chattiness of existing same-faction characters + the virtual slot.
    local total = newCharacterWeight
    for _, c in ipairs(bucket) do total = total + (c.chattiness or 0) end

    local r, acc = math.random() * total, 0
    -- Roll across existing characters first; whatever is left of the roulette
    -- range belongs to the virtual "new character" slot.
    for _, c in ipairs(bucket) do
        acc = acc + (c.chattiness or 0)
        if (r <= acc) then return c end
    end

    -- Virtual "new character" slot won.
    if (not rosterAtCap(faction)) then
        return generateCharacter(faction)              -- spawn, register, speak now
    end
    -- At the cap: reuse an existing same-faction character.
    return pickCharacter("chattiness", { faction = faction })
end

-- ===========================================================================
-- Line scoring + weighted picker (Phase 4) -- CHARACTERS_PLAN "Line scoring".
-- ---------------------------------------------------------------------------
-- A global, monotonically-increasing tick counter advances on every emission
-- (one per spoken conversation item, NOT per chained line). Each item records
-- the tick it was last used on, on the item itself (`lastTick`), so recency
-- penalties are per-item with no extra bookkeeping table.
local globalTick = 0

-- scoreLine(item, char, tick) -> number >= 0. A score of 0 means EXCLUDE
-- (only areaFactor can hard-exclude). Factors:
--   base         = item.weight (default 1, normalized at parse time)
--   roleFactor   = roleMoodMatchStrength when char.role matches item.roles;
--                  1.0 when item.roles is nil (untagged = any role);
--                  1/roleMoodMatchStrength (a low floor, NOT zero) on mismatch.
--   moodFactor   = same rule against char.personality / item.moods.
--   areaFactor   = 1.0 when item.areaGlobal (untagged = any area);
--                  else item.areas[char.area] * areaMatchStrength when the
--                  character's area IS in the line's area map;
--                  else 0  -> HARD EXCLUDE (the "wouldn't make sense here" guard:
--                  a city character never draws a battlefield-only line).
--   recencyPenalty = 0 within item.cooldown ticks of its last use, then ramps
--                  linearly back to 1.0 over the following `cooldown` ticks
--                  (so a just-used line is suppressed, not permanently banned).
-- Untagged role/mood -> 1.0 and untagged area -> global, so every character
-- ALWAYS has eligible fallback lines and never goes silent.
local function listContains(list, value)
    if (not list) then return false end
    for _, v in ipairs(list) do
        if (v == value) then return true end
    end
    return false
end

local function matchFactor(list, value)
    if (list == nil) then return 1.0 end                 -- untagged = neutral
    if (listContains(list, value)) then
        return roleMoodMatchStrength                      -- preferred match: boost
    end
    return 1.0 / roleMoodMatchStrength                    -- mismatch: low floor (not 0)
end

local function areaFactor(item, char)
    if (item.areaGlobal) then return 1.0 end              -- untagged = any area
    local w = item.areas[char.area]
    if (not w) then return 0 end                          -- HARD EXCLUDE
    return w * areaMatchStrength
end

local function recencyPenalty(item, tick)
    local last = item.lastTick
    if (not last) then return 1.0 end                     -- never used
    local cd   = item.cooldown or lineCooldownTicks
    if (cd <= 0) then return 1.0 end
    local since = tick - last
    if (since >= 2 * cd) then return 1.0 end              -- fully recovered
    if (since <= cd) then return 0 end                    -- within cooldown: suppressed
    -- ramp 0 -> 1 over the second cooldown window.
    return (since - cd) / cd
end

local function scoreLine(item, char, tick)
    local af = areaFactor(item, char)
    if (af <= 0) then return 0 end                        -- area is the only hard-exclude
    local base = item.weight or 1
    local rf   = matchFactor(item.roles, char.role)
    local mf   = matchFactor(item.moods, char.personality)
    local rp   = recencyPenalty(item, tick)
    return base * rf * mf * af * rp
end

-- pickLine(candidates, char, tick) -> item | nil.
-- Scores every candidate, then weighted-random picks among score>0 items.
-- Because untagged role/mood score 1.0 and untagged area is global, every
-- character always has eligible fallback lines, so this returns non-nil for any
-- non-empty candidate set with at least one global item. If somehow ALL
-- candidates are excluded (e.g. a pathological all-area-tagged set with none
-- matching the character), fall back to ANY global item so the speaker is never
-- silent.
local function pickLine(candidates, char, tick)
    local scored, total = {}, 0
    for _, item in ipairs(candidates) do
        local s = scoreLine(item, char, tick)
        if (s > 0) then
            scored[#scored + 1] = { item = item, score = s }
            total = total + s
        end
    end

    if (#scored == 0) or (total <= 0) then
        -- Hard-exclusion fallback: any global item (ignores recency/role/mood).
        for _, item in ipairs(candidates) do
            if (item.areaGlobal) then return item end
        end
        return nil                                         -- truly nothing to say
    end

    local r, acc = math.random() * total, 0
    for _, s in ipairs(scored) do
        acc = acc + s.score
        if (r <= acc) then return s.item end
    end
    return scored[#scored].item                            -- float-rounding fallback
end

-- ===========================================================================
-- Cast assembly (Phase 4) -- CHARACTERS_PLAN "Cast assembly".
-- ---------------------------------------------------------------------------
-- For a duo/group, the resolved initiator is voice A / the first speaker. The
-- remaining co-speakers are drawn from the SAME-faction roster (for a
-- shared-audience line that faction is Alliance, since shared is Alliance-voiced)
-- weighted by `friendliness`, preferring role/mood/area compatibility with the
-- chosen line, deduped against everyone already cast. If the roster is too thin
-- to fill the cast, co-speakers are lazily generated (subject to maxCharacters).
-- Each cast member is a full CHARACTER (name + stable color), not a bare name.
--
-- `castFaction` is the faction the co-speakers are drawn from (the initiator's
-- faction; for shared lines this is "alliance").
local function assembleCast(initiator, item, castFaction)
    if (item.kind == "line") then
        return { initiator }                               -- single voice
    end

    local size = (item.kind == "duo") and 2 or math.random(4, 6)
    -- A group never needs more voices than its chain has lines.
    if (item.kind == "group") and (size > #item.data) then size = #item.data end
    if (size < 2) then size = 2 end

    local cast = { initiator }
    local used = { [initiator.name] = true }

    while (#cast < size) do
        -- Prefer a friendly same-faction resident matching the line's tags.
        -- We try progressively looser filters so a thin roster still fills:
        --   1) role+mood+area match, 2) area only, 3) any same-faction char.
        local pick
        local wantRole = item.roles and item.roles[1] or nil
        local wantMood = item.moods and item.moods[1] or nil
        local wantArea = (not item.areaGlobal) and next(item.areas) or nil
        -- next() on the area map yields one tagged area key (good enough as a
        -- soft preference; scoring already enforces hard area rules on the LINE).

        pick = pickCharacter("friendliness", {
            faction = castFaction, role = wantRole, mood = wantMood,
            area = wantArea, excludeName = nil })
        if (pick) and (used[pick.name]) then pick = nil end

        if (not pick) then
            -- Looser: drop role/mood, keep faction (area optional).
            pick = pickCharacter("friendliness", { faction = castFaction })
            -- dedup against the existing cast.
            if (pick) and (used[pick.name]) then
                pick = pickCharacter("friendliness",
                    { faction = castFaction, excludeName = initiator.name })
            end
        end

        if (not pick) or (used[pick.name]) then
            -- Roster too thin / only dupes available -> lazily spawn (cap-aware).
            if (not rosterAtCap(castFaction)) then
                pick = generateCharacter(castFaction)
            else
                break                                      -- at cap, can't fill more
            end
        end

        if (pick) and (not used[pick.name]) then
            cast[#cast + 1] = pick
            used[pick.name] = true
        else
            break                                          -- give up; emit a shorter cast
        end
    end

    return cast
end

-- Choose which cast member voices line `ti` of a conversation (1-based).
-- Duos strictly alternate A/B/A/B; groups pick a random member, never the same
-- voice twice in a row. Operates over CHARACTERS (cast is a list of characters).
local function speakerForLine(cast, kind, ti, prevName)
    if (#cast == 1) then return cast[1] end
    if (kind == "duo") then
        return (ti % 2 == 1) and cast[1] or cast[2]
    end
    -- group
    local pick, guard = cast[math.random(#cast)], 0
    while (pick.name == prevName) and (#cast > 1) and (guard < 12) do
        pick = cast[math.random(#cast)]
        guard = guard + 1
    end
    return pick
end

-- Name colour palette (class-ish colours).
t.cc = {"C79C6E","F58CBA","ABD473","FFF569","FFFFFF","C41F3B","0070DE","69CCF0","9482C9","FF7d0A"}

t.init = function(s)
    -- Seed the RNG ONCE, at startup. (The original reseeded on every line, which
    -- tied variety to the wall clock and made same-second bursts repeat.)
    math.randomseed(os.time())
    math.random(); math.random(); math.random()  -- discard first low-entropy values
    s.d = require("npc_name") or {}
    -- Backwards-compat: if a flat name list is supplied (no faction keys), treat
    -- it as the surname pool. Generation reads alliance/horde first names +
    -- surnames (see generateName).
    if (s.d[1] ~= nil) then s.d = {surnames = s.d} end
    s.d.surnames = s.d.surnames or {}
    s.d.alliance = s.d.alliance or {}
    s.d.horde    = s.d.horde    or {}
    if (ns ~= "") then
        -- Optional DB name source: feed it into the faction-agnostic SURNAME
        -- pool so generated "{first} {last}" names can use DB-sourced surnames.
        local q = WorldDBQuery(ns)
        if (q) then
            repeat
                table.insert(s.d.surnames, q:GetString(0))
            until not q:NextRow()
        end
    end
end
t:init()

-- ===========================================================================
-- Conversation state machine over CHARACTERS.
-- ---------------------------------------------------------------------------
-- Speakers are drawn from the generated roster via resolveSpeaker, lines chosen
-- by scoreLine/pickLine, and duo/group casts assembled by friendliness
-- (assembleCast). The distinct-speaker guard lives in speakerForLine (above),
-- operating over characters.
--
-- A "channel" here is the driver of a candidate set; conversation state is kept
-- per channel in `t.conv[channel]` so a started duo/group finishes line-by-line
-- with its FIXED cast before a new item is begun. State fields:
--   item     -> the in-progress item (nil = start a fresh one next emit)
--   cast     -> the fixed cast of characters for this item
--   ti       -> next line index within item.data (chains)
--   prevName -> last speaker's name (group no-immediate-repeat guard)
--   speaker  -> the character who voiced the most recent line
--   audience -> the item's audience tag (drives emission routing)
-- A `line` item is a one-shot (single emit). A duo/group runs its chain to the
-- end, then the next emit starts a fresh item.
t.conv = {}

-- Resolve %city% for the CURRENT speaking character.
--   homeCityBias = true  -> %city% defaults to that speaker's own homeCity, so a
--                           line reads as self-reference ("things are quiet in
--                           %city%" = the speaker's home). Because homeCity is
--                           drawn at generation from the speaker's OWN faction
--                           capital list (allianceCities / hordeCities), this is
--                           automatically faction-correct: a Horde speaker biases
--                           to a Horde capital, an Alliance speaker to an Alliance
--                           one. Neutral hubs (Dalaran/Shattrath/Booty Bay) are
--                           NEVER home cities, so they only appear via the random
--                           path below.
--   homeCityBias = false -> random over ALL cities (capitals + neutral hubs).
-- Called per LINE with that line's actual speaker, so in a duo/group each cast
-- member self-references THEIR OWN home, not just the conversation initiator.
local function cityFor(speaker)
    if (homeCityBias) and (speaker) and (speaker.homeCity) then
        return speaker.homeCity
    end
    return selectRandomCity()
end

-- Begin (or continue) the conversation on `channel`, drawing from `candidates`
-- voiced by `initiator` of `castFaction`. Returns rawText, speaker, audience.
-- Advances the per-channel conversation state and the global recency tick.
local function nextLine(channel, candidates, initiator, castFaction)
    local st = t.conv[channel]
    if (not st) then st = {}; t.conv[channel] = st end

    -- Continue an in-progress duo/group chain with its FIXED cast first.
    if (st.item) and (st.item.kind ~= "line") and (st.ti <= #st.item.data) then
        local item = st.item
        local ti   = st.ti
        local speaker = speakerForLine(st.cast, item.kind, ti, st.prevName)
        st.ti       = ti + 1
        st.prevName = speaker.name
        st.speaker  = speaker
        if (st.ti > #item.data) then st.item = nil end       -- chain finished
        return item.data[ti], speaker, st.audience
    end

    -- Start a fresh item for this speaker.
    globalTick = globalTick + 1
    local item = pickLine(candidates, initiator, globalTick)
    if (not item) then return nil end                        -- nothing to say
    item.lastTick = globalTick                                -- record recency

    if (item.kind == "line") then
        st.item     = nil
        st.cast     = { initiator }
        st.audience = item.audience
        st.speaker  = initiator
        st.prevName = initiator.name
        return item.data, initiator, item.audience
    end

    -- Duo/group: fix the cast now and emit its first line.
    local cast = assembleCast(initiator, item, castFaction)
    st.cast     = cast
    st.audience = item.audience
    local speaker = speakerForLine(cast, item.kind, 1, nil)
    st.prevName = speaker.name
    st.speaker  = speaker
    st.ti       = 2
    st.item     = (#item.data > 1) and item or nil           -- chain or one-line
    return item.data[1], speaker, item.audience
end

-- Run the full %token% substitution on `txt` for `speaker`. (Same ~44 gsubs as
-- before; only %city% gained the homeCity bias.)
local function renderTokens(txt, speaker)
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
    txt = string.gsub(txt, "%%city%%",       cityFor(speaker))
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

-- Formatting helper ---------------------------------------------------------
-- Wraps a line in the colored [World] name prefix. The COLOR is now the
-- speaking character's STABLE per-character color (set once at generation),
-- not a fresh random color per line -- so a recurring voice keeps its identity.
local function formatWorld(speaker, body)
    local name  = speaker.name
    -- color is assigned ONCE per character at generation (generateCharacter) and
    -- never changes, so every line a character speaks keeps the same name color.
    -- No random-color path remains here -- a recurring voice is a stable identity.
    local color = speaker.color
    return string.format("|cFFFFC0C0[World] |r|cff%s|Hplayer:%s|h[%s]|h|r: |cFFFFC0C0%s|r",
        color, name, name, body)
end

-- Route a rendered message to the right listeners by the line's audience tag:
--   shared   -> SendWorldMessage (everyone)
--   alliance -> Alliance players only (team 0)
--   horde    -> Horde players only    (team 1)
local function emit(audience, msg)
    if (audience == "shared") then
        SendWorldMessage(msg)
        return
    end
    local team = (audience == "horde") and 1 or 0
    local players = GetPlayersInWorld(team)
    if (not players) or (next(players) == nil) then return end
    for _, p in pairs(players) do
        p:SendBroadcastMessage(msg)
    end
end

-- Drive one emission on `channel`: resolve a speaker for `castFaction`, pick &
-- render a line from `candidates`, and route it by the line's audience tag.
-- Returns silently if nothing can be said. The speaker color stays stable.
local function speak(channel, candidates, castFaction)
    local initiator = resolveSpeaker(castFaction)
    if (not initiator) then return end                       -- no character available
    local raw, speaker, audience = nextLine(channel, candidates, initiator, castFaction)
    if (not raw) then return end
    local body = renderTokens(raw, speaker)
    emit(audience, formatWorld(speaker, body))
end

-- Events --------------------------------------------------------------------
-- TIMER-MAPPING DESIGN (Phase 4, decision 5). The candidate set is per SPEAKER
-- faction, not per channel, so we map timers to FACTIONS rather than to
-- audiences:
--   * "alliance-driver" timer  -> an ALLIANCE speaker over allianceCandidates
--       (shared U alliance). Each chosen line is routed by its OWN audience tag:
--       a shared-origin line -> SendWorldMessage (everyone); an alliance-origin
--       line -> Alliance only. This single timer therefore covers BOTH the
--       everyone-visible chatter AND the Alliance-only chatter, voiced by
--       Alliance characters (decision 5: shared is Alliance-voiced).
--   * "horde-driver" timer     -> a HORDE speaker over hordeCandidates (horde),
--       always Horde-only audience.
-- WHY drop the old separate alliance-only timer: with the per-faction candidate
-- model, Alliance-only lines are simply alliance-origin items inside the
-- Alliance speaker's set, already emitted (to Alliance only) by the
-- alliance-driver timer. A separate alliance timer would DOUBLE-voice the
-- alliance pool. So we keep exactly two drivers (Alliance, Horde), avoiding any
-- duplication while preserving every audience path. The alliance-driver runs on
-- the faster `talk_time` interval (it carries the everyone-visible volume the
-- old shared timer did); the horde-driver runs on `faction_talk_time`.
--
-- Legacy enableFactionChat=false: hordeCandidates == allianceCandidates and all
-- items are tagged audience="shared", so BOTH timers broadcast everything to
-- everyone -- the original "everything to everyone" behaviour.

-- Alliance-driver (also carries everyone-visible shared lines).
CreateLuaEvent(function()
    speak("alliance", allianceCandidates, "alliance")
end, {talk_time[1], talk_time[2]}, 0)

if enableFactionChat then
    -- Horde-driver: Horde speakers, Horde-only audience.
    CreateLuaEvent(function()
        speak("horde", hordeCandidates, "horde")
    end, {faction_talk_time[1], faction_talk_time[2]}, 0)
else
    -- Legacy: a second everyone-visible driver over the merged pool (kept so the
    -- total chatter cadence matches the original two-timer setup). Voiced by an
    -- Alliance character; audience="shared" routes it to everyone.
    CreateLuaEvent(function()
        speak("horde", hordeCandidates, "alliance")
    end, {faction_talk_time[1], faction_talk_time[2]}, 0)
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
