--[[
  NPC display names -- the name-generation source pools for the character roster.

  Shape: { alliance = <gendered first-name pools>, horde = <same>, surnames = <list> }
    alliance -> per-faction FIRST names, bucketed by gender { male, female, neutral }
                (human / dwarf / night elf / gnome flavor).
    horde    -> per-faction FIRST names, bucketed { male, female, neutral }
                (orc / tauren / troll / forsaken / blood elf flavor).
    surnames -> faction-agnostic SURNAME pool (Stormbringer, Frostguard, ...), used by the
                "{first} {last}" name pattern in generateName (see logic/chatter.lua).

  buildName rolls the character's gender first, then draws a first name from the
  matching sub-pool so the gendered role prefixes (data/traits.lua) agree -- no more
  "Sister Cedric". `neutral` holds genderless flavour (gnome/utility + surname-style
  names) and is the fallback when a gender bucket is empty.

  Back-compat: a flat first-name list (no male/female/neutral keys) is still accepted
  and treated as the neutral pool (buildName falls through to it for any gender);
  mirrors the flat-list-as-surnames fallback in t.init. The optional DB-name source
  (the `ns` query in logic/chatter.lua) appends into `surnames`, which stays flat.
]]--

local names = {

  surnames = {
    -- faction-agnostic surname pool. Used by the "{first} {last}" name pattern.
    "Aethersworn", "Blazebinder", "Crystalvein", "Duskweaver", "Emberstrider", "Frostguard",
    "Glimmerblade", "Hollowgaze", "Ironshaper", "Jadefury", "Kraghammer", "Lunarbloom",
    "Mysticwind", "Netherbraid", "Orchidshade", "Pridewalker", "Quartzfang", "Runebound",
    "Stormbringer", "Thunderheart", "Umbrafell", "Valewhisper", "Winterwisp", "Xenostar",
    "Yewshield", "Zephyrwing", "Arcaneforge", "Boulderclaw", "Cinderseeker", "Dreadflame",
    "Ebonwhisper", "Flametongue", "Galeforce", "Havocbringer", "Iceshard", "Joltspark",
    "Kindlethorn", "Leafmender", "Moonsorrow", "Nimbuslord", "Oblivionsong", "Plaguewielder",
    "Quicksilver", "Raveneye", "Solarflare", "Tidereaver", "Umbralight", "Vortexbinder",
    "Wildroot", "Xylostorm", "Zenithshadow", "Aurorafang", "Brinestone", "Chaosreign",
    "Dewcaller", "Eclipseheart", "Frostveil", "Graveldust", "Harbinger", "Infernofall",
    "Jademyst", "Keenshadow", "Luminash", "Mistveil", "Nightbloom", "Oathsworn",
    "Pyrebrand", "Quillthorn", "Runekeeper", "Shiverpine", "Tempesthowl", "Umbrawisp",
    "Viperstrike", "Willowgrace", "Xenocrest", "Yarrowfrost", "Zephyrspark", "Azurebane",
    "Blizzardfury", "Cragheart", "Dreamweave", "Embermoon", "Fatescribe", "Glacierfall",
    "Hearthstone", "Ironflame", "Jasperlight", "Kestrelwing", "Loreseeker", "Maelstrom",
    "Netherwhirl", "Opalflame", "Pandemonium", "Quartzheart", "Riftblade", "Stagrunner",
    "Thornbinder", "Umbravale", "Valkyrie", "Wildfire", "Xanadriel", "Yewbark",
    "Zodiacwhisper", "Aetherbloom", "Blightbringer", "Celestial", "Dawnstrider", "Elderfrost",
    "Frostborn", "Gloomshade", "Heartsong", "Ivorywing", "Jadebinder", "Kaleidostorm",
    "Lightwhisper", "Moonshadow", "Netherblade", "Oceanshaper", "Petalbreeze", "Quartzsong",
    "Ravenmoon", "Soulkeeper", "Thunderclaw", "Umbraclaw", "Valkyrion", "Whisperwind",
    "Xenoflame", "Yggdrasil", "Zephyrfall", "Aetherstorm", "Bloodthorn", "Crimsonwing",
    "Darkweaver", "Elvenstar", "Frostwalker", "Galeheart", "Hollowsoul", "Ironforge",
    "Jadefire", "Krakenheart", "Leafdancer", "Mistwarden", "Nightshade", "Oblivionheart",
    "Phoenixflare", "Quicksand", "Runechant", "Starcaller", "Thunderforge", "Undying",
    "Vortexheart", "Wildsoul", "Xenowind", "Yewspirit", "Zodiacblade", "Aurorastrike",
    "Baneclaw", "Coralheart", "Duskcaller", "Emberfury", "Frostwhisper", "Gloomfrost",
    "Hailstorm", "Ironwill", "Jadeclaw", "Kobold", "Lightforge", "Mysticflame",
    "Netherstorm", "Owlfeather", "Pyrewing", "Quillfire", "Runeclaw", "Shadowbinder",
    "Tidecaller", "Umbrasky", "Vinebinder", "Wraithfire", "Xenogaze", "Yellowmoon",
    "Zephyrblade", "Abysswalker", "Boulderfist", "Chillheart", "Drakefire", "Eldergrove",
    "Fangstrike", "Glimmermoon", "Hellfire", "Ironbark", "Jadeguard", "Kingstorm",
    "Leafshadow", "Mystwalker", "Necroflame", "Oceantide", "Pyromancer", "Quarrymaster",
    "Ravenstrike", "Starshard", "Thundermaw", "Undertow", "Veilshifter", "Windcaller",
    "Xenostone", "Yewleaf", "Zenithflame", "Aetherstone", "Blackthorn", "Crescentmoon",
    "Dragonclaw", "Elvenbane", "Frostshard", "Gloomblade", "Horizonwalker", "Ironclad",
    "Jadeheart", "Kingsbane", "Lunarglade", "Mistcaller", "Netherheart", "Oceanbreeze",
    "Pyrewalker", "Quicksight", "Ravenheart", "Shadowgale", "Thunderstrike", "Umbralord",
    "Valewatcher", "Wildstorm", "Xenoblade", "Yewblossom", "Zephyrheart",
  },

  -- Alliance first names (human / dwarf / night elf flavour, then gnome = neutral).
  alliance = {
    male = {
      -- human
      "Aldric", "Reginald", "Godfrey", "Tobias", "Cedric", "Bartholomew",
      "Lucian", "Percival", "Edmund", "Galen", "Thaddeus", "Roderick",
      "Benedict", "Alistair", "Florian", "Ferdinand", "Leopold", "Crispin",
      -- dwarf
      "Thorgrim", "Brommir", "Durgan", "Bromli", "Khazgar", "Hjaldi",
      "Borin", "Dagran", "Faldran", "Grimbrow", "Durnan", "Bofgar",
      "Keldran", "Thaldrin", "Morgran", "Brogan",
      -- night elf
      "Faelan", "Elsendir", "Velarian", "Karaan", "Makaan", "Aureon",
      "Shaldris", "Thaelis", "Orelis",
    },
    female = {
      -- human
      "Eleanor", "Gwendolyn", "Seraphine", "Rowena", "Mirabelle", "Annelise",
      "Beatrix", "Isolde", "Adelaide", "Cordelia", "Evelyn", "Rosalind",
      "Wilhelmina", "Marguerite", "Cassia", "Brigitte", "Ophelia", "Henrietta",
      -- night elf
      "Maelara", "Faewyn", "Lunariel", "Mirelle", "Aelwyn", "Cyndrethil",
      "Theloria", "Mairiel", "Nuala", "Yreliana", "Elandriel", "Naelith",
      "Aerithil", "Sariel", "Naariel", "Iridi", "Vendaeli",
    },
    neutral = {
      -- gnome / utility
      "Fizzlebang", "Cogwhistle", "Nixiebolt", "Sprocket", "Tinkerwick", "Wizzlebang",
      "Gimblewick", "Bizzlefuse", "Whirlgear", "Sprocketta",
    },
  },

  -- Horde first names (orc / troll / blood elf given names; tauren & forsaken
  -- surname-style names read as genderless, so they sit in neutral).
  horde = {
    male = {
      -- orc
      "Grosh", "Karg", "Drogath", "Urtok", "Ronkar", "Durtan", "Korgath",
      "Throm", "Nazgar", "Gorehk", "Mokvar", "Urzog", "Brakgul", "Maku",
      -- troll
      "Mull", "Senzir", "Ghazul", "Trezzahn", "Volkaru",
      -- blood elf
      "Aelthalas", "Valdris", "Felthier", "Maethon", "Aurelias", "Queldaris", "Theronas",
    },
    female = {
      -- orc
      "Morka", "Gruna", "Rexa", "Gorta", "Sharga", "Thrakka", "Brakka", "Drogka",
      -- tauren
      "Tamala", "Pawa", "Una",
      -- troll
      "Jektha", "Ruljara", "Nyoka", "Zinjara", "Rakaza", "Vanira", "Zulmara",
      -- forsaken / blood elf
      "Morgaine", "Belastra", "Sanaria", "Vaeloria", "Selastra",
    },
    neutral = {
      -- orc / troll ambiguous
      "Maijin", "Bwemba", "Mauari", "Hirjin", "Sannze", "Grimtide",
      -- tauren (surname-style)
      "Stonehoof", "Windhoof", "Stomphoof", "Skychaser", "Thunderhorn",
      "Earthbinder", "Mooncloud", "Ragehoof", "Hahko", "Holac", "Maako",
      -- forsaken (surname-style)
      "Mortwood", "Grimsby", "Ravenscar", "Gravesend", "Mortis", "Ashbury",
      "Coldwood", "Sorrowmoss", "Bonechill", "Wraithe", "Gallows", "Belmont",
      "Vellum", "Ravensworn", "Cadelle",
      -- blood elf ambiguous
      "Sinduun", "Auralan", "Liadrel", "Dawnblade", "Sunwhisper",
    },
  },

}

return names
