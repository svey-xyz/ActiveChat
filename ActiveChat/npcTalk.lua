--[[
  Lively World Chat -- faction-gated edition.

  Content lives in talk_text/npc_text.lua, returning three pools:
      shared   -> everyone (SendWorldMessage)   alliance -> team 0   horde -> team 1
  enableFactionChat = false merges all three and broadcasts to everyone (legacy).

  Voice: civilian/guard/NPC ambience -- gossip, weather, work, rumor, lore. Never
  LFG/LFM or gearscore talk. %role%/%difficulty%/%gearscore% are for the rare
  adventurer voice only; prefer world/flavor tokens. See npc_text.lua header.
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

-- Context-aware chatter config. When a flag is off (or its API is missing) that
-- dimension falls back to random behaviour -- no silent characters, no errors.
local enableContextAware   = true    -- master switch for the whole feature
local enableTimeContext    = true    -- in-game-clock-aware times + %timeofday%
local enableEventContext   = true    -- active-event gating + %event% (Phase 3+)
local enableSeasonContext  = true    -- in-game-month season + %season% (Phase 5)
local timeMatchStrength    = 3.0     -- like areaMatchStrength; 1 = off (Phase 2)
local seasonMatchStrength  = 3.0     -- like areaMatchStrength; 1 = off (Phase 5)
local contextRefreshMs     = 60000   -- ctx cache TTL (ms)
local eventApproachDays    = 5       -- "approach" window before an event starts (Phase 4)
local eventAfterDays       = 3       -- "after" window once an event ends (Phase 4)
local enableEventBurst     = false   -- one-shot "festival has begun" burst on activation

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

-- Context vocabulary/maps from context_map.lua (eventIdToName, monthToSeason,
-- eventNeutral, eventBurst). Guarded so a missing/broken file falls back to random.
local ctxMap = {}
do
    local ok, m = pcall(require, "context_map")
    if (ok and type(m) == "table") then ctxMap = m end
end

-- Single module-level cache of "what's true right now", refreshed on a slow TTL
-- (never recomputed per candidate line). Fields default to neutral values.
local ctx = {
    hour      = 0,          -- in-game hour 0..23 (from GetGameTime)
    timeKey   = "night",    -- bucketed: "dawn"|"morning"|"midday"|"afternoon"|"dusk"|"night"
    season    = "spring",   -- derived from in-game month
    active    = {},         -- set-like ACTIVE event names
    nextEvent = nil,        -- { name=..., daysAway=N } soonest upcoming
    lastEvent = nil,        -- { name=..., daysAgo=N }  most recently ended
    refreshed = 0,          -- ms tick of last refresh
}

-- Event-burst state (dead unless enableEventBurst). ctxActivePrev = last refresh's
-- active-event set, diffed against the fresh set to fire once per activation;
-- ctxActiveSeeded guards the first refresh (snapshot only, no startup burst flood).
-- fireEventBurst is forward-declared so refreshCtx can call it; its body (needs
-- t.conv/assembleCast/makeItem) is assigned later in the file.
local ctxActivePrev   = {}
local ctxActiveSeeded = false
local fireEventBurst                 -- assigned after the conversation machinery

-- Coarse, fiction-friendly hour buckets; tune freely. The bucket is the
-- tag/selection vocabulary; the display pool below is the wording vocabulary.
local function bucketHour(h)
    if h < 5  then return "night"     end
    if h < 8  then return "dawn"      end
    if h < 11 then return "morning"   end
    if h < 14 then return "midday"    end
    if h < 18 then return "afternoon" end
    if h < 21 then return "dusk"      end
    return "night"
end

-- month (1..12) -> season name, from ctxMap.monthToSeason with a northern-hemisphere
-- inline fallback. Nil-safe: a bad/out-of-range month returns nil (ctx.season stays neutral).
local monthToSeasonMap = (type(ctxMap.monthToSeason) == "table")
    and ctxMap.monthToSeason
    or {
        [1]="winter", [2]="winter", [3]="spring", [4]="spring", [5]="spring",
        [6]="summer", [7]="summer", [8]="summer", [9]="autumn", [10]="autumn",
        [11]="autumn", [12]="winter",
    }
local function monthToSeason(month)
    if (type(month) ~= "number") then return nil end
    return monthToSeasonMap[month]
end

-- Holiday -> season cross-check: an active seasonal holiday overrides the month-
-- derived season so calendar and holiday never disagree (Winter Veil => winter).
-- Keys are EXACT eventIdToName display names; season-neutral holidays are omitted.
local holidayToSeason = {
    ["Winter Veil"]                 = "winter",
    ["the Midsummer Fire Festival"] = "summer",
    ["the Harvest Festival"]        = "autumn",
    ["Pilgrim's Bounty"]            = "autumn",
    ["Noblegarden"]                 = "spring",
    ["the Lunar Festival"]          = "spring",
}

-- timeKey -> display-string pool for %timeofday%, agreeing with the clock.
-- IMPORTANT: bare nouns, NO leading article -- lines supply their own ("this
-- %timeofday%", "at %timeofday%"). "the evening" would render "this the evening".
local timeKeyDisplay = {
    night     = { "midnight", "nightfall", "night" },
    dawn      = { "dawn", "first light" },
    morning   = { "morning", "first light" },
    midday    = { "midday" },
    afternoon = { "afternoon", "midday" },
    dusk      = { "dusk", "twilight", "evening" },
}

-- ms tick source for the refresh TTL. Prefer GetGameTime() (seconds on ALE),
-- fall back to os.time(). Capability-guarded -- always returns a sane value.
local function nowMs()
    if (type(GetGameTime) == "function") then
        local ok, secs = pcall(GetGameTime)
        if (ok and type(secs) == "number") then return secs * 1000 end
    end
    return os.time() * 1000
end

-- Set { [displayName]=true } of currently-active events, via GetActiveGameEvents()
-- mapped through ctxMap.eventIdToName (unmapped IDs skipped). Returns {} if the API
-- is absent (engine then never excludes on events and %event% goes random).
local function activeEventNameSet()
    local set = {}
    if (type(GetActiveGameEvents) ~= "function") then return set end
    local ok, ids = pcall(GetActiveGameEvents)
    if (not ok) or (type(ids) ~= "table") then return set end
    local map = ctxMap.eventIdToName or {}
    for _, id in pairs(ids) do
        local name = map[id]
        if (name) then set[name] = true end
    end
    return set
end

-- Nearest-event scheduling. Read the game_event schedule once at startup, then
-- compute soonest-upcoming / most-recently-ended per refresh as cheap arithmetic
-- over the snapshot. game_event cols (AC 3.3.5): start_time (sec, via
-- UNIX_TIMESTAMP), length (min), occurence (min between repeats; 0 = one-shot).
-- Only IDs mapping to a display name are kept.

local DAY_SECONDS = 86400

-- Days past which an event is no longer surfaced as "near" -- beyond this the slot
-- stays nil and %event% uses the neutral pool rather than naming a far-off holiday.
local NEAREST_HORIZON_DAYS = 30

-- Schedule snapshot: array of { id, name, startSec, lengthSec, occurSec }. Empty
-- when WorldDBQuery is absent/fails -> nearestEvents() returns nil/nil.
local eventSchedule = {}

-- One-shot startup read of the game_event schedule. Guarded on WorldDBQuery and
-- wrapped in pcall so an absent API or odd result shape leaves the snapshot empty
-- rather than erroring. ALEQuery API: GetRowCount/GetUInt32/NextRow, 0-indexed cols.
local function readEventSchedule()
    if (type(WorldDBQuery) ~= "function") then return {} end
    local map = ctxMap.eventIdToName or {}
    local out = {}
    local ok = pcall(function()
        local q = WorldDBQuery(
            "SELECT eventEntry, UNIX_TIMESTAMP(start_time), length, occurence FROM game_event")
        if (not q) then return end
        -- GetRowCount() bounds the loop so an empty/odd result can't spin; we
        -- still guard NextRow() for engines that only support row-walking.
        local rows = (type(q.GetRowCount) == "function") and q:GetRowCount() or nil
        local n = 0
        repeat
            local id        = q:GetUInt32(0)
            local name      = map[id]
            if (name) then
                local startSec  = q:GetUInt32(1)        -- UNIX_TIMESTAMP -> seconds
                local lengthMin = q:GetUInt32(2)        -- minutes
                local occurMin  = q:GetUInt32(3)        -- minutes (0 = non-recurring)
                out[#out + 1] = {
                    id        = id,
                    name      = name,
                    startSec  = startSec,
                    lengthSec = (lengthMin or 0) * 60,
                    occurSec  = (occurMin or 0) * 60,
                }
            end
            n = n + 1
            if (rows ~= nil) and (n >= rows) then break end
        until (type(q.NextRow) ~= "function") or (not q:NextRow())
    end)
    if (not ok) then return {} end
    return out
end

eventSchedule = readEventSchedule()

-- nearestEvents(now_sec) -> nextEvent, lastEvent (each {name=, daysAway/daysAgo=}
-- or nil). Projects each holiday's recurrence cycle around `now` (recurring events
-- repeat every occurSec, which handles the year-wrap; occurence > length so windows
-- never overlap), keeps the soonest future start and most recent past end, both
-- capped to NEAREST_HORIZON_DAYS (else nil -> neutral).
local function nearestEvents(now)
    if (type(now) ~= "number") or (#eventSchedule == 0) then return nil, nil end
    local horizonSec = NEAREST_HORIZON_DAYS * DAY_SECONDS

    local nextName, nextStart                     -- soonest future start
    local lastName, lastEnd                        -- most recent past end

    for _, ev in ipairs(eventSchedule) do
        local nextS, prevS                         -- this event's bracketing starts
        if (ev.occurSec and ev.occurSec > 0) then
            -- Recurring: locate the cycle around `now`. k = how many whole cycles
            -- have elapsed since the very first start (clamped at >= 0).
            local elapsed = now - ev.startSec
            local k = math.floor(elapsed / ev.occurSec)
            if (k < 0) then k = 0 end
            prevS = ev.startSec + k * ev.occurSec      -- start of the current/just-past cycle
            nextS = prevS + ev.occurSec                -- start of the next cycle (WRAP case)
            -- If we're still BEFORE this event's first ever start, prevS would be
            -- in the future; in that case there is no past occurrence yet.
            if (prevS > now) then nextS = prevS; prevS = nil end
        else
            -- Non-recurring single window.
            if (ev.startSec >= now) then nextS = ev.startSec else prevS = ev.startSec end
        end

        -- Upcoming start candidate.
        if (nextS) and (nextS >= now) then
            if (not nextStart) or (nextS < nextStart) then
                nextStart = nextS; nextName = ev.name
            end
        end

        -- Most-recent past END candidate (start of the past cycle + its length).
        if (prevS) and (prevS <= now) then
            local endS = prevS + (ev.lengthSec or 0)
            if (endS <= now) then
                if (not lastEnd) or (endS > lastEnd) then
                    lastEnd = endS; lastName = ev.name
                end
            end
        end
    end

    local nextEvent, lastEvent
    if (nextName) then
        local away = nextStart - now
        if (away <= horizonSec) then                   -- horizon cap: don't surface far-off events
            nextEvent = { name = nextName, daysAway = math.floor(away / DAY_SECONDS) }
        end
    end
    if (lastName) then
        local ago = now - lastEnd
        if (ago <= horizonSec) then
            lastEvent = { name = lastName, daysAgo = math.floor(ago / DAY_SECONDS) }
        end
    end
    return nextEvent, lastEvent
end

-- TTL-guarded refresh of ctx (time, events, season). Each dimension is flag- and
-- API-guarded; a missing clock/API leaves that field neutral and falls back to random.
local function refreshCtx()
    local now = nowMs()
    if (now - ctx.refreshed < contextRefreshMs) then return end   -- common path: cheap early-exit
    ctx.refreshed = now

    if (not enableContextAware) then return end

    -- Time + season share ONE os.date decomposition of the GetGameTime() timestamp
    -- (a decomposition of the game clock, never a real date). API-guarded so an
    -- absent clock leaves both neutral. t.hour drives time; t.month drives season.
    local t
    if ((enableTimeContext or enableSeasonContext)
        and type(GetGameTime) == "function" and type(os.date) == "function") then
        local ok, decomposed = pcall(function() return os.date("*t", GetGameTime()) end)
        if (ok and type(decomposed) == "table") then t = decomposed end
    end

    -- Time: derive the in-game hour -> timeKey bucket.
    if (enableTimeContext and t and type(t.hour) == "number") then
        ctx.hour    = t.hour
        ctx.timeKey = bucketHour(ctx.hour)
        -- else: leave ctx.timeKey at its prior/neutral value; %timeofday% falls back.
    end

    -- Active events: set { ["Hallow's End"]=true, ... }, empty when the API is
    -- absent. Populated BEFORE the season block so its holiday cross-check sees it.
    if (enableEventContext) then
        ctx.active = activeEventNameSet()

        -- Burst: diff the fresh active set against the previous snapshot to fire a
        -- one-shot festival burst for each newly-active event (once per activation,
        -- since a still-active event sits in both sets). First refresh only seeds
        -- the snapshot (ctxActiveSeeded) so startup holidays don't all burst at once.
        if (enableEventBurst and fireEventBurst) then
            if (ctxActiveSeeded) then
                for name, _ in pairs(ctx.active) do
                    if (not ctxActivePrev[name]) then       -- newly active this refresh
                        fireEventBurst(name)
                    end
                end
            end
            ctxActiveSeeded = true
            local snap = {}
            for name, _ in pairs(ctx.active) do snap[name] = true end
            ctxActivePrev = snap                            -- store AFTER diffing
        end

        -- Nearest events over the cached schedule. nil-safe (absent schedule ->
        -- neutral pool). Uses raw game-time seconds when available, else os.time.
        local nowSec
        if (type(GetGameTime) == "function") then
            local ok, secs = pcall(GetGameTime)
            if (ok and type(secs) == "number") then nowSec = secs end
        end
        if (not nowSec) and (type(os.time) == "function") then nowSec = os.time() end
        ctx.nextEvent, ctx.lastEvent = nearestEvents(nowSec)
    end

    -- Season: derive from the in-game month, then let any active seasonal holiday
    -- override it (Winter Veil active => winter even in a summer month). Absent clock
    -- or unmapped month leaves ctx.season neutral (%season% goes random).
    if (enableSeasonContext and t and type(t.month) == "number") then
        local season = monthToSeason(t.month)
        if (season) then ctx.season = season end
        if (ctx.active) then
            for name, _ in pairs(ctx.active) do
                local s = holidayToSeason[name]
                if (s) then ctx.season = s break end
            end
        end
    end
end

-- FORWARD-COMPAT no-op: the emit path calls this so wiring a real chat-topic
-- buffer later is a one-function change.
local function recordTopic(line) end

-- Resolve %timeofday% from context (flags on + a pool for ctx.timeKey), else random.
local function resolveTimeOfDay(c)
    if (enableContextAware and enableTimeContext and c and c.timeKey) then
        local pool = timeKeyDisplay[c.timeKey]
        if (pool and #pool > 0) then return pool[math.random(#pool)] end
    end
    return selectRandomTimeOfDay()                          -- fallback: today's behaviour
end

-- Resolve %season% from context (flags on + ctx.season set), else random. ctx.season
-- is already a fiction word ("spring"|...) so it substitutes directly.
local function resolveSeason(c)
    if (enableContextAware and enableSeasonContext and c and c.season) then
        return c.season
    end
    return selectRandomSeason()                             -- fallback: today's behaviour
end

-- Festival-agnostic phrases used when no real holiday is active/near, so a character
-- never names a specific holiday out of context. From context_map.lua + inline fallback.
local eventNeutralPool = (type(ctxMap.eventNeutral) == "table" and #ctxMap.eventNeutral > 0)
    and ctxMap.eventNeutral
    or { "the next festival", "the holidays", "the coming festivities" }
local function selectNeutralEvent()
    return eventNeutralPool[math.random(#eventNeutralPool)]
end

-- Resolve %event% to the most relevant real event, in priority order:
--   1. the line's `events` tag (tag WINS so token & eligibility agree; prefer an
--      active tagged event, else the first tagged name).
--   2. else something live now (c.active).
--   3. else the nearest event in time: c.nextEvent then c.lastEvent.
--   4. else a neutral phrase -- NEVER a random specific holiday.
local function resolveEvent(item, c)
    if (enableContextAware and enableEventContext) then
        -- 1. tagged line: the tag's event wins (prefer an active one).
        if (item) and (not item.eventsGlobal) and (item.events) and (#item.events > 0) then
            if (c and c.active) then
                for _, name in ipairs(item.events) do
                    if (c.active[name]) then return name end
                end
            end
            return item.events[1]
        end
        -- 2. else something live right now.
        if (c and c.active) then
            for name in pairs(c.active) do return name end
        end
        -- 3. else the nearest event in time (upcoming preferred, then just-past).
        if (c) then
            if (c.nextEvent and c.nextEvent.name) then return c.nextEvent.name end
            if (c.lastEvent and c.lastEvent.name) then return c.lastEvent.name end
        end
    end
    -- 4. neutral phrase -- never a random specific holiday.
    return selectNeutralEvent()
end

-- Resolve %nextevent% / %lastevent% to the soonest-upcoming / most-recently-ended
-- holiday; both fall back to the neutral pool when scheduling is unknown.
local function resolveNextEvent(c)
    if (enableContextAware and enableEventContext and c and c.nextEvent and c.nextEvent.name) then
        return c.nextEvent.name
    end
    return selectNeutralEvent()
end
local function resolveLastEvent(c)
    if (enableContextAware and enableEventContext and c and c.lastEvent and c.lastEvent.name) then
        return c.lastEvent.name
    end
    return selectNeutralEvent()
end

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

-- Tagged-content parser. buildItems flattens typed pools ({lines, duos, groups})
-- into one cursored item list, each tagged with its `kind`: "line" (single
-- speaker), "duo" (2 alternating), "group" (rotating cast). Cursor [0] preserved.
--
-- Authored entries (back-compatible):
--   * bare string            -> untagged line (global wildcard)
--   * table {[1]=text, ...}   -> tagged one-liner; named keys are metadata
--   * table {chain={...}, ...} -> tagged duo/group
--   * legacy {"a","b",...}    -> untagged chain (from the duos/groups list, [1] a string)
--
-- Normalized item shape: { kind, data (string for line / array for chain), roles,
-- moods (nil = any), areaGlobal+areas, timesGlobal+times, seasonsGlobal+seasons,
-- eventsGlobal+events+eventWindow, notTimes/notSeasons/notEvents, weight, cooldown }.
-- The *Global flags mean "untagged = matches any"; a tagged dimension hard-excludes
-- off-tag context at score time. All normalization happens at parse time below.

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

-- Normalize `times` into {timesGlobal, times-map} -- exact mirror of normalizeAreas.
-- Unlisted buckets are hard-excluded at score time (timeFactor).
local function normalizeTimes(times)
    if (times == nil) then
        return true, {}                         -- omitted => global / any time
    end
    local map = {}
    if (times[1] ~= nil) then
        -- list form: {"night","dusk"} -> uniform weight 1 per listed bucket.
        for _, k in ipairs(times) do map[k] = 1 end
    else
        -- map form: {night=3, dusk=1} -> copy graded weights as-is.
        for k, w in pairs(times) do map[k] = w end
    end
    return false, map
end

-- Normalize `seasons` into {seasonsGlobal, seasons-map} -- mirror of normalizeTimes.
-- Unlisted seasons are hard-excluded at score time (seasonFactor).
local function normalizeSeasons(seasons)
    if (seasons == nil) then
        return true, {}                         -- omitted => global / any season
    end
    local map = {}
    if (seasons[1] ~= nil) then
        -- list form: {"autumn","winter"} -> uniform weight 1 per listed season.
        for _, k in ipairs(seasons) do map[k] = 1 end
    else
        -- map form: {autumn=3, winter=1} -> copy graded weights as-is.
        for k, w in pairs(seasons) do map[k] = w end
    end
    return false, map
end

-- Normalize `events` into {eventsGlobal, events-list}. events is BINARY (no graded
-- boost): omitted => fires regardless; a list of display-names => fires ONLY while
-- one is active, else hard-excluded. Map form accepted (keys = names, weights
-- ignored). Returns names as a plain array (also used to resolve %event%).
local function normalizeEvents(events)
    if (events == nil) then
        return true, {}                         -- omitted => global / any/no event
    end
    local list = {}
    if (events[1] ~= nil) then
        -- list form: {"Hallow's End", "the Day of the Dead"} -> names as-is.
        for _, name in ipairs(events) do list[#list + 1] = name end
    else
        -- map form: {["Hallow's End"]=anything} -> keys are the names (weights
        -- ignored; events is binary).
        for name, _ in pairs(events) do list[#list + 1] = name end
    end
    return false, list
end

-- Normalize `eventWindow`: "active" (default, live only), "approach" (also the
-- N-day run-up, keys off ctx.nextEvent), "after" (also the N-day wind-down,
-- ctx.lastEvent). Unrecognised -> "active" so a typo never widens eligibility.
local function normalizeEventWindow(w)
    if (w == "approach") or (w == "after") then return w end
    return "active"
end

-- Normalize an exclusion field (notTimes/notSeasons/notEvents) into a set { key=true }.
-- The NEGATIVE gate: "fires in ANY context EXCEPT these" (mirror of the positive
-- tags). List or map form accepted (binary, no weights); omitted => no exclusions.
-- Applies even to global lines, so a universal line can carve out one context.
local function normalizeExcludeSet(field)
    local set = {}
    if (field == nil) then return set end       -- omitted => no exclusions
    if (field[1] ~= nil) then
        for _, k in ipairs(field) do set[k] = true end   -- list form
    else
        for k, _ in pairs(field) do set[k] = true end    -- map/set form
    end
    return set
end

-- Wrap one authored entry into the normalized item shape. `forceChain` (true for
-- duos/groups) reads a legacy bare {"a","b"} array as the chain, not a one-liner.
local function makeItem(kind, entry, forceChain)
    -- Bare string -> untagged item.
    if (type(entry) == "string") then
        return {
            kind = kind, data = entry,
            roles = nil, moods = nil,
            areaGlobal = true, areas = {},
            timesGlobal = true, times = {},
            seasonsGlobal = true, seasons = {},
            eventsGlobal = true, events = {}, eventWindow = "active",
            notTimes = {}, notSeasons = {}, notEvents = {},
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

    local areaGlobal, areaMap     = normalizeAreas(entry.areas)
    local timesGlobal, timesMap   = normalizeTimes(entry.times)
    local seasonsGlobal, seasonsMap = normalizeSeasons(entry.seasons)
    local eventsGlobal, eventsList = normalizeEvents(entry.events)
    return {
        kind = kind, data = data,
        roles = entry.roles, moods = entry.moods,
        areaGlobal = areaGlobal, areas = areaMap,
        timesGlobal = timesGlobal, times = timesMap,
        seasonsGlobal = seasonsGlobal, seasons = seasonsMap,
        eventsGlobal = eventsGlobal, events = eventsList,
        eventWindow = normalizeEventWindow(entry.eventWindow),
        notTimes   = normalizeExcludeSet(entry.notTimes),
        notSeasons = normalizeExcludeSet(entry.notSeasons),
        notEvents  = normalizeExcludeSet(entry.notEvents),
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

-- Per-faction CANDIDATE item lists, keyed by SPEAKER faction: Alliance speaker ->
-- shared + alliance; Horde speaker -> horde. Each item carries an `audience` origin
-- tag (shared|alliance|horde) that decides routing at emit time, so one Alliance
-- speaker can voice either an everyone-visible or an Alliance-only line from the
-- same set. Legacy (enableFactionChat=false): all merged, all audience="shared".
-- taggedItems flattens buildItems' [0]-cursored list into a plain array (the cursor
-- is replaced by per-cast conversation state) and stamps each item's audience.
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

-- Character system data tables -- the roster's vocabulary of identities, feeding
-- generateCharacter (role/personality/area) and the line scorer. Each of roles,
-- personalities and areas is defined in exactly ONE table here -- add to the
-- relevant table, no engine change needed.

-- The six locale affinities. Characters and tagged lines carry one; untagged = global.
local AREAS = { "city", "rural", "battlefield", "coast", "wilderness", "road" }

-- Civic/occupation archetypes. prefixes -> "{Role} {first}" name prefixes;
-- weight -> roster frequency; area -> default affinity (must be one of AREAS).
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

-- Personality descriptors -> epithet pool for the "{first}, {epithet}" name pattern;
-- also doubles as a line-selection mood tag.
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

-- Roster state -- in-memory ONLY, never persisted, reset every restart (regrows
-- lazily as chatter is emitted). roster = all characters; rosterByFaction = the
-- same bucketed by faction; usedNames = dedup guard. generateCharacter fills them.
local roster          = {}
local rosterByFaction = { alliance = {}, horde = {} }
local usedNames       = {}

-- Home-city pools by faction. Neutral hubs (Dalaran/Shattrath/Booty Bay) are
-- travel hubs, not home cities, so they're excluded here despite being in `cities`.
local allianceCities = {"Stormwind", "Ironforge", "Darnassus", "The Exodar"}
local hordeCities     = {"Orgrimmar", "Thunder Bluff", "Undercity", "Silvermoon City"}

-- Pre-compute role/personality key lists once so
-- generation can index them uniformly. ROLES is weighted; PERSONALITIES is
-- picked uniformly.
local roleKeys = {}
for k in pairs(ROLES)         do roleKeys[#roleKeys + 1] = k end
local moodKeys = {}
for k in pairs(PERSONALITIES) do moodKeys[#moodKeys + 1] = k end

-- generateName -> display string via four weighted patterns: {first last} ~55%,
-- {Role first} ~20%, {first, epithet} ~15%, {first} ~10%. First names from
-- t.d[faction], surnames from t.d.surnames. Deduped vs usedNames (12-try cap).
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

-- generateCharacter(faction) -> a full character table, registered into roster /
-- rosterByFaction with its name marked used. Does NOT enforce maxCharacters --
-- the cap is checked by resolveSpeaker before calling this.
local function generateCharacter(faction)
    local role        = pickRoleWeighted()
    local personality = moodKeys[math.random(#moodKeys)]

    -- area: biased to the role's default area (~65%), else a random AREAS member,
    -- so the roster reads roughly role-typed without being rigid.
    -- FUTURE HOOK: derive area from a real player's current zone; v1 is static.
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

-- Roster-query seam: two functions funnel all speaker selection.
--   pickCharacter(weightField, filters) -> EXISTING character | nil (never spawns).
--   resolveSpeaker(faction) -> ambient initiator; weighted over existing chars plus
--       one virtual "new character" slot, lazily spawning under the cap.

-- pickCharacter -- existing-only weighted pick. weightField = "chattiness" |
-- "friendliness". filters (all optional): faction, role, mood, area, excludeName.
-- (allowSpawn is ignored here -- spawning is a caller decision.) Returns nil if none match.
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

-- maxCharacters is the global cap; maxCharactersPerFaction (if set) is a per-faction sub-cap.
local function rosterAtCap(faction)
    if (#roster >= maxCharacters) then return true end
    if (maxCharactersPerFaction ~= nil)
        and (#rosterByFaction[faction] >= maxCharactersPerFaction) then
        return true
    end
    return false
end

-- resolveSpeaker(faction) -- ambient initiator. Weighted roulette over same-faction
-- characters (weight = chattiness) PLUS a virtual "new character" slot (weight =
-- newCharacterWeight): if the virtual slot wins and we're under cap -> spawn; at cap
-- -> reuse an existing char; else return the picked char. Self-balancing: as summed
-- chattiness grows the virtual slot wins less, so growth tapers and halts at the cap.
-- (Shared lines call resolveSpeaker("alliance") -> always Alliance-voiced.)
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

-- Line scoring + weighted picker. globalTick advances once per emitted item (not
-- per chained line); each item records its lastTick for per-item recency.
local globalTick = 0

-- scoreLine(item, char, tick) -> score >= 0; 0 means EXCLUDE. Final score is the
-- product of these factors:
--   base         = item.weight
--   role/mood    = matchStrength on match, 1.0 if untagged, 1/matchStrength on mismatch
--   area         = 1.0 if global; else weight*strength if char.area is tagged, else 0 (EXCLUDE)
--   time/season  = like area, but also 1.0 when context is off/unavailable (never exclude blindly)
--   event        = binary 1.0/0 (see eventFactor)
--   exclude      = 0 if context lands in a notTimes/notSeasons/notEvents set (see excludeFactor)
--   recency      = 0 within cooldown ticks of last use, ramping back to 1.0 over the next cooldown
-- Untagged role/mood/area always score >0, so a character is never left silent.
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

-- timeFactor -> parallel to areaFactor: 1.0 if timesGlobal; weight*strength if
-- ctx.timeKey is tagged; 0 (EXCLUDE) if not. Forced 1.0 when flags off or
-- ctx.timeKey unavailable, so a tagged line never excludes itself blindly.
local function timeFactor(item, c)
    if (item.timesGlobal) then return 1.0 end             -- untagged = any time
    -- Context off or unknown -> behave like today's random selection (no exclude).
    if (not enableContextAware) or (not enableTimeContext) then return 1.0 end
    if (not c) or (not c.timeKey) then return 1.0 end
    local w = c.timeKey and item.times[c.timeKey]
    if (not w) then return 0 end                          -- HARD EXCLUDE (off-bucket)
    return w * timeMatchStrength
end

-- seasonFactor -> parallel to timeFactor: 1.0 if seasonsGlobal; weight*strength if
-- ctx.season is tagged; 0 (EXCLUDE) if not. Forced 1.0 when flags off or ctx.season
-- unavailable.
local function seasonFactor(item, c)
    if (item.seasonsGlobal) then return 1.0 end           -- untagged = any season
    -- Context off or unknown -> behave like today's random selection (no exclude).
    if (not enableContextAware) or (not enableSeasonContext) then return 1.0 end
    if (not c) or (not c.season) then return 1.0 end
    local w = c.season and item.seasons[c.season]
    if (not w) then return 0 end                          -- HARD EXCLUDE (off-season)
    return w * seasonMatchStrength
end

-- eventFactor -> 1.0 or 0, BINARY (an event-tagged line is ABOUT that event, so it
-- applies or it doesn't). 1.0 if untagged, flags off, or nothing knowable (empty
-- ctx.active AND no schedule -- never exclude on a guess). Otherwise 1.0 when a
-- tagged event is live, or within eventWindow: "approach" (== ctx.nextEvent within
-- eventApproachDays) / "after" (== ctx.lastEvent within eventAfterDays); else 0.
local function eventFactor(item, c)
    if (item.eventsGlobal) then return 1.0 end            -- untagged = any/no event
    if (not enableContextAware) or (not enableEventContext) then return 1.0 end

    local active   = c and c.active
    local liveKnown = active and (next(active) ~= nil)
    local window   = item.eventWindow or "active"
    -- If neither the active set nor the relevant nearest-event slot is known, we
    -- can't judge -> don't exclude (fallback invariant).
    local nearKnown = false
    if (window == "approach") then nearKnown = (c and c.nextEvent) ~= nil
    elseif (window == "after") then nearKnown = (c and c.lastEvent) ~= nil end
    if (not liveKnown) and (not nearKnown) then return 1.0 end  -- nothing to judge on

    -- Active now (any window includes the live event).
    if (liveKnown) then
        for _, name in ipairs(item.events) do
            if (active[name]) then return 1.0 end
        end
    end

    -- Approach window: the line's event is the soonest-upcoming, within the lead.
    if (window == "approach") and (c and c.nextEvent) then
        if (c.nextEvent.daysAway <= eventApproachDays) then
            for _, name in ipairs(item.events) do
                if (name == c.nextEvent.name) then return 1.0 end
            end
        end
    end

    -- After window: the line's event is the most-recently-ended, within the tail.
    if (window == "after") and (c and c.lastEvent) then
        if (c.lastEvent.daysAgo <= eventAfterDays) then
            for _, name in ipairs(item.events) do
                if (name == c.lastEvent.name) then return 1.0 end
            end
        end
    end

    return 0                                              -- HARD EXCLUDE (out of window)
end

-- excludeFactor -> 1.0 or 0. The NEGATIVE gate over notTimes/notSeasons/notEvents,
-- checked for EVERY line (even global ones) so a universal line can carve out one
-- context. Returns 0 when ctx.timeKey/ctx.season is in the set, or a notEvents event
-- is active. Each dimension respects its sub-flag and only excludes when ctx is known.
local function excludeFactor(item, c)
    if (not enableContextAware) then return 1.0 end       -- feature off => no exclusions
    if (not c) then return 1.0 end

    -- Time-of-day exclusion.
    if (enableTimeContext) and (c.timeKey) and (item.notTimes) then
        if (item.notTimes[c.timeKey]) then return 0 end
    end
    -- Season exclusion.
    if (enableSeasonContext) and (c.season) and (item.notSeasons) then
        if (item.notSeasons[c.season]) then return 0 end
    end
    -- Active-event exclusion (binary, keyed off the live event set).
    if (enableEventContext) and (item.notEvents) and (c.active) then
        for name, _ in pairs(item.notEvents) do
            if (c.active[name]) then return 0 end
        end
    end

    return 1.0
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
    if (af <= 0) then return 0 end                        -- area can hard-exclude
    local tf = timeFactor(item, ctx)
    if (tf <= 0) then return 0 end                        -- times can hard-exclude (off-bucket)
    local sf = seasonFactor(item, ctx)
    if (sf <= 0) then return 0 end                        -- seasons can hard-exclude (off-season)
    local ef = eventFactor(item, ctx)
    if (ef <= 0) then return 0 end                        -- events can hard-exclude (none active)
    local xf = excludeFactor(item, ctx)
    if (xf <= 0) then return 0 end                        -- notTimes/notSeasons/notEvents can hard-exclude
    local base = item.weight or 1
    local rf   = matchFactor(item.roles, char.role)
    local mf   = matchFactor(item.moods, char.personality)
    local rp   = recencyPenalty(item, tick)
    return base * rf * mf * af * tf * sf * ef * xf * rp
end

-- pickLine -> item | nil. Scores every candidate, weighted-random picks among
-- score>0 items. If all are excluded, falls back to any global item so the speaker
-- is never silent; returns nil only when there is truly nothing to say.
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

-- Cast assembly. For a duo/group the initiator is voice A; co-speakers are drawn
-- from the castFaction roster (Alliance for shared lines) weighted by friendliness,
-- preferring role/mood/area match, deduped, lazily spawned if the roster is thin
-- (cap-aware). Each member is a full character (name + stable color).
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

-- Pick which cast member voices line `ti` (1-based). Duos alternate A/B/A/B;
-- groups pick a random member, never the same voice twice in a row.
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
    -- Seed the RNG ONCE at startup (reseeding per line tied variety to the wall clock).
    math.randomseed(os.time())
    math.random(); math.random(); math.random()  -- discard first low-entropy values
    s.d = require("npc_name") or {}
    -- Back-compat: a flat name list (no faction keys) is treated as the surname pool.
    if (s.d[1] ~= nil) then s.d = {surnames = s.d} end
    s.d.surnames = s.d.surnames or {}
    s.d.alliance = s.d.alliance or {}
    s.d.horde    = s.d.horde    or {}
    if (ns ~= "") then
        -- Optional DB name source -> fed into the surname pool.
        local q = WorldDBQuery(ns)
        if (q) then
            repeat
                table.insert(s.d.surnames, q:GetString(0))
            until not q:NextRow()
        end
    end
end
t:init()

-- Conversation state machine over characters. A "channel" drives a candidate set;
-- per-channel state in t.conv[channel] lets a started duo/group finish line-by-line
-- with its FIXED cast before a new item begins. State fields: item (in-progress, nil
-- = start fresh), cast, ti (next chain line index), prevName (no-repeat guard),
-- speaker, audience (routing tag). A `line` is one-shot; a duo/group runs to the end.
t.conv = {}

-- Resolve %city% for the current speaker. homeCityBias=true -> the speaker's own
-- homeCity (faction-correct, since homeCity is drawn from that faction's capitals;
-- neutral hubs never appear here). false -> random over all cities. Called per LINE
-- so each cast member in a duo/group self-references their own home.
local function cityFor(speaker)
    if (homeCityBias) and (speaker) and (speaker.homeCity) then
        return speaker.homeCity
    end
    return selectRandomCity()
end

-- Begin or continue the conversation on `channel`. Returns rawText, speaker,
-- audience, item (item lets the renderer honour the line's `events` tag for
-- %event%). Advances the per-channel state and global tick.
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
        return item.data[ti], speaker, st.audience, item
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
        return item.data, initiator, item.audience, item
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
    return item.data[1], speaker, item.audience, item
end

-- Event-activation burst (behind enableEventBurst; default off = dead code). When
-- refreshCtx detects an event flipping active it calls fireEventBurst once: a short
-- duo item is built with makeItem (tagged with the event so %event% agrees), a cast
-- assembled, and the item SEEDED into t.conv so the next speak() tick plays it like
-- an ambient duo. Voiced everyone-visible (audience="shared") by an Alliance cast.
-- Fully nil-/flag-guarded: never errors, never clobbers an in-progress chain.

-- Burst content pool from context_map.lua + inline fallback. Each entry is a
-- two-line duo chain; %event% is filled at render time.
local eventBurstPool = (type(ctxMap.eventBurst) == "table" and #ctxMap.eventBurst > 0)
    and ctxMap.eventBurst
    or {
        { "Word is %event% has begun -- did you hear?", "Aye, just now. Best get to the city." },
        { "%event% starts today, friend.", "Then what are we waiting for? Let's go." },
    }

fireEventBurst = function(eventName)               -- assigns the forward-declared local
    if (not enableEventBurst) then return end                -- flag guard (belt & braces)
    if (type(eventName) ~= "string") or (eventName == "") then return end
    if (type(eventBurstPool) ~= "table") or (#eventBurstPool == 0) then return end

    local channel = "alliance"                               -- shared lines are Alliance-voiced
    local st = t.conv[channel]
    -- Don't clobber an in-progress chain -- only seed when the channel is idle.
    if (st) and (st.item) and (st.item.kind ~= "line") then return end

    -- Build a duo burst item tagged with the event (forceChain so {a,b} is a chain).
    local chain = eventBurstPool[math.random(#eventBurstPool)]
    if (type(chain) ~= "table") or (#chain < 1) then return end
    local item = makeItem("duo", { chain = chain, events = { eventName } }, true)
    item.audience = "shared"                                 -- everyone-visible
    item.lastTick = globalTick

    -- Assemble a same-faction cast around a resolved Alliance speaker.
    local initiator = resolveSpeaker("alliance")
    if (not initiator) then return end                       -- no character available -> skip
    local cast = assembleCast(initiator, item, "alliance")
    if (type(cast) ~= "table") or (#cast < 1) then return end

    -- Seed the state so the next speak("alliance") tick plays the chain from line 1
    -- (same shape nextLine leaves behind for a duo).
    t.conv[channel] = {
        item     = item,
        cast     = cast,
        ti       = 1,
        prevName = nil,
        speaker  = initiator,
        audience = "shared",
    }
end

-- Run the full %token% substitution on `txt`. `ctx`/`item` are optional; when
-- absent (or context off) the context-aware tokens fall back to random helpers.
-- `item` lets %event% honour the line's `events` tag (see resolveEvent).
local function renderTokens(txt, speaker, ctx, item)
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
    -- Context-aware tokens (resolve from ctx when enabled, else random):
    -- %event% honours a line's tag, else live, else nearest; %nextevent%/%lastevent%
    -- name the upcoming/just-past holiday; %season%/%timeofday% agree with the clock.
    txt = string.gsub(txt, "%%event%%",      resolveEvent(item, ctx))
    txt = string.gsub(txt, "%%nextevent%%",  resolveNextEvent(ctx))
    txt = string.gsub(txt, "%%lastevent%%",  resolveLastEvent(ctx))
    txt = string.gsub(txt, "%%season%%",     resolveSeason(ctx))
    txt = string.gsub(txt, "%%timeofday%%",  resolveTimeOfDay(ctx))
    txt = string.gsub(txt, "%%shop%%",       selectRandomShop())
    txt = string.gsub(txt, "%%route%%",      selectRandomRoute())
    txt = string.gsub(txt, "%%tale%%",       selectRandomTale())
    txt = string.gsub(txt, "%%weather%%",    selectRandomWeather())
    return txt
end

-- Wrap a line in the colored [World] name prefix. The color is the speaker's stable
-- per-character color (set once at generation), so a recurring voice keeps its identity.
local function formatWorld(speaker, body)
    local name  = speaker.name
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

-- Drive one emission on `channel`: resolve a speaker, pick & render a line, route
-- it by the line's audience tag. Returns silently if nothing can be said.
local function speak(channel, candidates, castFaction)
    refreshCtx()                                             -- cheap (TTL-guarded); keeps ctx fresh
    local initiator = resolveSpeaker(castFaction)
    if (not initiator) then return end                       -- no character available
    local raw, speaker, audience, item = nextLine(channel, candidates, initiator, castFaction)
    if (not raw) then return end
    local body = renderTokens(raw, speaker, ctx, item)
    recordTopic(raw)                                         -- FORWARD-COMPAT no-op (chat-topic awareness)
    emit(audience, formatWorld(speaker, body))
end

-- Events --------------------------------------------------------------------
-- Two timers, mapped to FACTIONS (candidates are per-speaker-faction):
--   * alliance-driver -> an Alliance speaker over allianceCandidates (shared +
--       alliance). Each line routes by its OWN audience tag, so this one timer
--       carries both everyone-visible and Alliance-only chatter (on talk_time).
--   * horde-driver    -> a Horde speaker over hordeCandidates, Horde-only (faction_talk_time).
-- No separate alliance-only timer: Alliance-only lines are already alliance-origin
-- items in the Alliance set, so a third timer would double-voice them.
-- Legacy (enableFactionChat=false): both pools merged, all audience="shared", so
-- both timers broadcast everything to everyone.

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
    -- Legacy: a second everyone-visible driver over the merged pool (keeps the
    -- original two-timer cadence). Alliance-voiced; audience="shared" -> everyone.
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
