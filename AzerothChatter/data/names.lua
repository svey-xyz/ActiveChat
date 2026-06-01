--[[
  NPC display names -- the name-generation source pools for the character roster.

  Shape: { alliance = <first-name list>, horde = <first-name list>, surnames = <list> }
    alliance -> per-faction FIRST names (human / dwarf / night elf / draenei / gnome flavor).
    horde    -> per-faction FIRST names (orc / tauren / troll / forsaken / blood elf flavor).
    surnames -> faction-agnostic SURNAME pool (Stormbringer, Frostguard, ...), used by the
                "{first} {last}" name pattern in generateName (see logic/chatter.lua).

  generateName draws a first name from the speaker's faction pool and (for most
  patterns) a surname from the shared surnames pool. The optional DB-name source
  (the `ns` query in logic/chatter.lua) appends into `surnames`.
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

  alliance = {
    -- Alliance
    "Aldric", "Reginald", "Eleanor", "Godfrey", "Gwendolyn", "Tobias",
    "Seraphine", "Cedric", "Rowena", "Bartholomew", "Lucian", "Mirabelle",
    "Percival", "Annelise", "Edmund", "Beatrix", "Galen", "Thaddeus",
    "Isolde", "Adelaide", "Roderick", "Cordelia", "Benedict", "Evelyn",
    "Alistair", "Rosalind", "Wilhelmina", "Florian", "Marguerite", "Ferdinand",
    "Cassia", "Brigitte", "Leopold", "Ophelia", "Crispin", "Henrietta",
    "Thorgrim", "Brommir", "Durgan", "Bromli", "Khazgar", "Hjaldi",
    "Borin", "Dagran", "Faldran", "Grimbrow", "Durnan", "Bofgar",
    "Keldran", "Thaldrin", "Morgran", "Brogan", "Elandriel", "Maelara",
    "Shaldris", "Faewyn", "Lunariel", "Thaelis", "Mirelle", "Aelwyn",
    "Cyndrethil", "Naelith", "Aerithil", "Sariel", "Theloria", "Faelan",
    "Elsendir", "Mairiel", "Naariel", "Velarian", "Iridi", "Karaan",
    "Nuala", "Vendaeli", "Orelis", "Makaan", "Yreliana", "Aureon",
    "Fizzlebang", "Cogwhistle", "Nixiebolt", "Sprocket", "Tinkerwick", "Wizzlebang",
    "Gimblewick", "Bizzlefuse", "Whirlgear", "Sprocketta",
  },

  horde = {
    -- Horde
    "Grosh", "Karg", "Drogath", "Morka", "Gruna", "Thrakka",
    "Urtok", "Ronkar", "Durtan", "Brakka", "Korgath", "Throm",
    "Nazgar", "Rexa", "Gorta", "Maku", "Gorehk", "Mokvar",
    "Drogka", "Sharga", "Urzog", "Brakgul", "Stonehoof", "Windhoof",
    "Stomphoof", "Skychaser", "Thunderhorn", "Earthbinder", "Mooncloud", "Ragehoof",
    "Hahko", "Tamala", "Holac", "Maako", "Pawa", "Una",
    "Grimtide", "Mull", "Jektha", "Ruljara", "Senzir", "Volkaru",
    "Maijin", "Ghazul", "Nyoka", "Trezzahn", "Bwemba", "Zinjara",
    "Rakaza", "Mauari", "Vanira", "Zulmara", "Hirjin", "Sannze",
    "Mortwood", "Grimsby", "Ravenscar", "Morgaine", "Gravesend", "Mortis",
    "Ashbury", "Coldwood", "Sorrowmoss", "Bonechill", "Wraithe", "Gallows",
    "Belmont", "Vellum", "Ravensworn", "Cadelle", "Aelthalas", "Dawnblade",
    "Sinduun", "Valdris", "Belastra", "Auralan", "Sanaria", "Vaeloria",
    "Felthier", "Maethon", "Aurelias", "Liadrel", "Queldaris", "Theronas",
    "Sunwhisper", "Selastra",
  },

}

return names
