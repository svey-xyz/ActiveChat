--[[
  Placeholder vocabulary pools + their selectRandom* accessors.

  Pure data and stateless helpers, split out of logic/chatter.lua so the engine file stays
  about *logic* -- editing chatter selection/scoring never needs this vocabulary in
  view, and retuning vocabulary never touches the engine. Loaded via require("data.tokens");
  returns a table P of selectRandom* functions (the raw tables stay module-private --
  the engine only ever picks from them, never indexes them directly).

  Token <-> accessor mapping lives in renderTokens (logic/chatter.lua); every accessor here
  is wired to a %token% there.

  Tagged token pools (Part A). A few pools where context clearly matters (food, drink,
  weather, activity, critter) use a string-first tagged shape, the SAME vocabulary the
  chatter file uses for line tags: a bare string fits any context; a table is
  { value=..., times=..., seasons=..., events=... } (and `proper=true` for proper-named
  entries that must never take an article). selectTagged() biases the pick by the live
  ctx, hard-excluding off-context entries and keeping untagged ones at weight 1.

  The scoring itself is OWNED by the engine (logic/chatter.lua) -- it injects a single
  scoreTokenEntry(tags, ctx) via P.setTagScorer so token entries and chatter lines share
  one time/season/event factor implementation. With no scorer set, or context off / ctx
  unavailable, every entry scores 1 -> selection is exactly today's uniform random
  (the fallback invariant).

  Articles (Part B). Countable-noun pools (food/drink/companion/toy/currency/...) store
  values with NO leading article; the chatter supplies one via the combined %afood%/
  %adrink%/%acompanion%/%atoy%/%acritter% tokens (vowel-aware a/an in one step, so no
  look-ahead) or authors "some %food%". withArticle() never prefixes a proper name.
]]--

local P = {}

-- Tagged-pool machinery -----------------------------------------------------
-- Engine-injected per-entry scorer: f(tags, ctx) -> weight (>=1 keep, 0 exclude).
-- nil until logic/chatter.lua calls setTagScorer; until then every entry scores 1.
local tagScorer = nil
function P.setTagScorer(fn) tagScorer = fn end

-- An entry is either a bare string (untagged value) or a table with `value` + tags.
-- Normalize to (value, tags|nil, proper). tags=nil => untagged => always weight 1.
local function splitEntry(entry)
    if (type(entry) == "string") then return entry, nil, false end
    return entry.value, entry, (entry.proper == true)
end

-- selectTagged(pool, ctx) -> a single value, biased by ctx. Weighted-random over
-- survivors: untagged entries weigh 1; tagged entries weigh scoreTokenEntry(tags,ctx)
-- (0 hard-excludes). No scorer / no ctx => every weight is 1 (uniform fallback). An
-- all-excluded pool falls back to a uniform pick so a token never resolves empty.
local function selectTagged(pool, ctx)
    local n = #pool
    if (n == 0) then return "" end
    local weights, total = {}, 0
    for i = 1, n do
        local _, tags = splitEntry(pool[i])
        local w = 1
        if (tags ~= nil) and (tagScorer ~= nil) then w = tagScorer(tags, ctx) or 0 end
        if (w < 0) then w = 0 end
        weights[i] = w
        total = total + w
    end
    if (total <= 0) then                              -- everything excluded: uniform fallback
        local v = select(1, splitEntry(pool[math.random(n)]))
        return v
    end
    local r = math.random() * total
    for i = 1, n do
        r = r - weights[i]
        if (r <= 0) then return (select(1, splitEntry(pool[i]))) end
    end
    return (select(1, splitEntry(pool[n])))           -- float-rounding guard
end

-- Vowel-aware "a"/"an" for the %a...% combined tokens. Proper names pass through
-- untouched (the entry's `proper` flag, decided by the caller). Empty -> "".
local function articleFor(value)
    local c = value:sub(1, 1):lower()
    if (c:match("[aeiou]")) then return "an" end
    return "a"
end

-- Pick a value from a (possibly tagged) pool and prepend the correct article unless
-- the chosen entry is a proper name. Returns the article-bearing phrase in one step.
local function selectWithArticle(pool, ctx)
    local n = #pool
    if (n == 0) then return "" end
    -- Re-run the weighted selection but keep the proper flag of the WINNER. Cheapest
    -- correct form: reuse selectTagged to choose the value, then look the value's
    -- proper flag back up (values are unique within these pools).
    local value = selectTagged(pool, ctx)
    for i = 1, n do
        local v, _, proper = splitEntry(pool[i])
        if (v == value) then
            if (proper) then return value end
            return articleFor(value) .. " " .. value
        end
    end
    return articleFor(value) .. " " .. value
end

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
    "herbing", "prospecting", "farming mats", "digging for ore",
    "cooking up a feast", "grinding for leather",
    "milling herbs", "disenchanting greens", "hunting for rare spawns",
    "smelting bars", "chasing gathering nodes",
    { value="looking for fishing pools", times={"dawn","morning"} },
    { value="picking herbs",             times={"dawn","morning"} },
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
    "Stone Keeper's Shards", "Champion's Seal", "Venture Coins",
    "Dalaran Cooking Awards", "Dalaran Jewelcrafter's Tokens",
    "Spirit Shards", "Sidereal Essence"
}

-- Tavern food (pairs naturally with %shop% and %drink%). String-first tagged shape
-- (see "Tagged token pools" below): bare string = fits any context; a table carries
-- `value` + optional times/seasons/events tags. Articles are STRIPPED (Part B grammar
-- rule) -- the chatter supplies them via %afood% or "some %food%".
local foods = {
    "Dalaran Brownie", "Mulgore Spice Bread", "Conjured Mana Strudel",
    "Tasty Cupcake", "Delicious Chocolate Cake",
    "Baked Manta Ray", "Worg Tartare", "Roasted Quail", "Smoked Salmon",
    "Honey Bread", "meat pie", "Cracker", "Mead Basted Caribou",
    { value="eggs and bacon",  times={"dawn","morning"} },
    { value="porridge",        times={dawn=3, morning=3} },
    { value="Bobbing Apple",   events={"Hallow's End"} },   -- Hallow's End game item
    { value="Spice Bread",     seasons={"winter"} },
    { value="Spiced Beef Jerky", times={"night","dusk"} },
    { value="Pilgrim's pie",   events={"Pilgrim's Bounty"} },
}

-- Tavern drinks. Same tagged shape; articles stripped.
local drinks = {
    "Thunder Ale", "Dwarven Stout", "Junglevine Wine", "Moonberry Juice",
    "Sweet Nectar", "Cherry Grog", "Rhapsody Malt",
    "Bottle of Pinot Noir", "Conjured Crystal Water", "Skin of Dwarven Stout",
    "Ironforge Rations", "Gordok Green Grog", "tankard of ale",
    { value="Honeymint Tea", times={"dawn","morning"} },
    { value="mulled wine",   seasons={"winter"} },
    { value="hot cider",     seasons={"autumn"}, events={"Hallow's End"} },
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

-- Vanity companion pets (sits nicely beside %critter%). Common-noun pets carry NO
-- article (Part B); proper-named pets are flagged `proper=true` so %acompanion% never
-- prepends an article to a name (e.g. "a Pengu" is wrong). Seasonal-drop pets tagged.
local companions = {
    "Mechanical Squirrel", "Pandaren Monk",
    "Onyxian Whelpling", "Tiny Crimson Whelpling", "Disgusting Oozeling",
    "Sprite Darter Hatchling", "Hyacinth Macaw",
    "Calico Cat", "Cockroach", "Captured Firefly",
    "Albino Snake",
    { value="Sinister Squashling", events={"Hallow's End"} },  -- Hallow's End pet
    { value="Mini Diablo",         proper=true },
    { value="Lil' K.T.",           proper=true },
    { value="Pengu",               proper=true },
    { value="Speedy the turtle",   proper=true },
}

-- Gear enchantments (overheard crafting/enchanter chatter).
local enchants = {
    "Berserking", "Crusader", "Mongoose", "Icewalker", "Mighty Spellpower",
    "Blade Ward", "Blood Draining", "Greater Assault", "Superior Agility",
    "Tuskarr's Vitality", "Black Magic", "Accuracy", "Spellpower",
    "Titanweave", "Greater Inscription of the Pinnacle"
}

-- Novelty/fun items (joke toys and trinkets, not gear). Articles stripped (Part B) so
-- chatter supplies them via %atoy% or "some %toy%".
local toys = {
    "Noggenfogger Elixir", "Orb of Deception",
    "Piccolo of the Flaming Fire", "Gnomish Army Knife",
    "Decahedral Dwarven Dice", "Savory Deviate Delight",
    "Carrot on a Stick", "Robot Chicken", "Foam Sword Rack",
    "Romantic Picnic Basket", "Faded Photograph",
    "Spectral Tiger Cub figurine",
    { value="Hallowed Wand", events={"Hallow's End"} },
    { value="Snowball",      seasons={"winter"}, events={"Winter Veil"} },
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
-- Bare nouns throughout -- the call site supplies the article via %acritter%. A few
-- carry light seasonal tags where the wildlife clearly tracks the season.
local critters = {
    "deer", "skunk", "rabbit", "squirrel", "fox", "boar", "cat", "chicken",
    "frog", "sheep", "cow", "prairie dog", "mouse", "toad", "crab", "ram",
    "gazelle", "hare", "owl",
    { value="fawn", seasons={"spring"} },
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

-- Weather is descriptive (used bare, e.g. "cuz o' the %weather%"), so its baked
-- articles stay (Part B targets a/an-countable nouns, not these). Tagged by season
-- where the weather clearly tracks it; untagged ones fit anywhere.
local weathers = {
    "rain", "fog", "clear skies", "a thunderstorm", "heavy mist",
    "drizzle", "howling wind",
    { value="snow",            seasons={"winter"} },
    { value="a blizzard",      seasons={"winter"} },
    { value="sleet",           seasons={"winter","autumn"} },
    { value="warm sunshine",   seasons={"summer","spring"} },
    { value="an overcast sky", seasons={"autumn","winter"} },
}

-- Accessors -----------------------------------------------------------------
-- One picker per pool; each returns a single random member. Wired to %tokens% in
-- renderTokens (logic/chatter.lua).
function P.selectRandomZone()         return zones[math.random(#zones)] end
function P.selectRandomInstance()     return instances[math.random(#instances)] end
function P.selectRandomRole()         return roles[math.random(#roles)] end
function P.selectRandomClass()        return classes[math.random(#classes)] end
function P.selectRandomBattleground() return battlegrounds[math.random(#battlegrounds)] end
function P.selectRandomProfession()   return professions[math.random(#professions)] end
function P.selectRandomActivity(_, ctx) return selectTagged(activities, ctx) end
function P.selectRandomHerb()         return herbs[math.random(#herbs)] end
function P.selectRandomOre()          return ores[math.random(#ores)] end
function P.selectRandomGem()          return gems[math.random(#gems)] end
function P.selectRandomFish()         return fish[math.random(#fish)] end
function P.selectRandomNpc()          return npcs[math.random(#npcs)] end
function P.selectRandomCurrency()     return currencies[math.random(#currencies)] end
function P.selectRandomFood(_, ctx)   return selectTagged(foods, ctx) end
function P.selectRandomDrink(_, ctx)  return selectTagged(drinks, ctx) end
function P.selectRandomTitle()        return titles[math.random(#titles)] end
function P.selectRandomTradegood()    return tradegoods[math.random(#tradegoods)] end
function P.selectRandomCompanion(_, ctx) return selectTagged(companions, ctx) end
function P.selectRandomEnchant()      return enchants[math.random(#enchants)] end
function P.selectRandomToy(_, ctx)    return selectTagged(toys, ctx) end
function P.selectRandomCity()         return cities[math.random(#cities)] end
function P.selectRandomRace()         return races[math.random(#races)] end
function P.selectRandomMonster()      return monsters[math.random(#monsters)] end
function P.selectRandomCritter(_, ctx) return selectTagged(critters, ctx) end
function P.selectRandomBoss()         return bosses[math.random(#bosses)] end
function P.selectRandomConsumable()   return consumables[math.random(#consumables)] end
function P.selectRandomItem()         return items[math.random(#items)] end
function P.selectRandomRep()          return reps[math.random(#reps)] end
function P.selectRandomMount()        return mounts[math.random(#mounts)] end
function P.selectRandomSpell()        return spells[math.random(#spells)] end
function P.selectRandomRare()         return rares[math.random(#rares)] end
function P.selectRandomPvpTitle()     return pvptitles[math.random(#pvptitles)] end
function P.selectRandomEmote()        return emotes[math.random(#emotes)] end
function P.selectRandomDifficulty()   return difficulties[math.random(#difficulties)] end
function P.selectRandomEvent()        return events[math.random(#events)] end
function P.selectRandomSeason()       return seasons[math.random(#seasons)] end
function P.selectRandomTimeOfDay()    return timesofday[math.random(#timesofday)] end
function P.selectRandomShop()         return shops[math.random(#shops)] end
function P.selectRandomRoute()        return routes[math.random(#routes)] end
function P.selectRandomTale()         return tales[math.random(#tales)] end
function P.selectRandomWeather(_, ctx) return selectTagged(weathers, ctx) end

-- Article-combined accessors (Part B): pick a context-biased value AND prepend the
-- correct "a"/"an" in one step. Proper-named entries pass through with no article.
-- Wired to %afood%/%adrink%/%acompanion%/%atoy%/%acritter% in renderTokens.
function P.selectRandomAFood(_, ctx)      return selectWithArticle(foods, ctx) end
function P.selectRandomADrink(_, ctx)     return selectWithArticle(drinks, ctx) end
function P.selectRandomACompanion(_, ctx) return selectWithArticle(companions, ctx) end
function P.selectRandomAToy(_, ctx)       return selectWithArticle(toys, ctx) end
function P.selectRandomACritter(_, ctx)   return selectWithArticle(critters, ctx) end

-- Numeric placeholders. Returned as game-formatted strings.
-- %gold%: realistic magnitudes, suffixed "g" (WoW convention).
function P.selectRandomGold()
    local buckets = {{1, 50}, {25, 500}, {500, 5000}, {2000, 25000}}
    local b = buckets[math.random(#buckets)]
    return tostring(math.random(b[1], b[2])) .. "g"
end
-- %level%: a character level (low-end clamped so "level 1" is rare).
function P.selectRandomLevel()      return tostring(math.random(2, 80)) end
-- %gearscore%: WotLK-era GearScore range, rounded to a tidy ten.
function P.selectRandomGearscore()  return tostring(math.random(240, 600) * 10) end

return P
