--[[
Guild chat content, faction-gated AND typed. Same shape as npc_text.lua:
  <faction> = { lines = {...}, duos = {...}, groups = {...} }
Add one-liners to `lines`, 2-person banter to `duos`, big multi-voice threads to `groups`.
The same placeholders as npc_text.lua work here too (%zone% %instance% %role%
%class% %bg% %profession% %city% %race% %boss% %consumable% %item% %rep% %mount%
%spell% %rare% %pvptitle% %emote% %difficulty% %gold% %level% %gearscore%
%event% %season% %timeofday% %shop% %route% %tale% %weather%).

Tone: members of an adventuring company talking among themselves. Warm, familiar,
a little chaotic -- the way a guild that's been through a hundred dungeons together
talks. Stay in-world: Azeroth is real to these characters. No real-world references,
no out-of-character meta, no breaking the fourth wall.
]]--

return {

  shared = {
    -- standalone one-liners (single speaker)
    lines = {
      -- Guild logistics, in-character
      "Crafters, I've dumped a stack of ore in the guild vault. The city forge is calling. Make me something shiny.",
      "At the city enchanter's table if anyone needs vellums. Also I'm out of dust again. It's a problem.",
      "Running everyone's city errands today: mail, auction house, repairs. I am the guild's unpaid intern and I accept this.",
      "Whoever needs flasks for tonight, I'm at the city alchemy lab cooking a batch. Tips accepted in cookies.",
      "The city tailor finally finished my robe. I look incredible. I will be standing in the bank for compliments.",
      "Guild vault's restocked with potions and food. Grab what you need before tonight, it's all in the city.",
      "I'll be at the city mailbox if anyone needs to trade. Yes, the one the kodo's sitting on. Just reach under it.",
      "Standing at the auction house posting guild gear cheap for our newer members. First come first served, no flipping it.",
      "Reminder: guild tabards are stocked in the city vault. Wear the colors, scare the rivals, look fantastic.",
      "Spent the morning sorting the guild vault. Found four 'Mystery' crates and a fortune in vendor trash. Living the dream.",
      "City repair run for the whole guild on me today, the coffers came in. Get those bills cleared, you magnificent broke heroes.",
      "In the city cooking feasts for tonight. If you want the good food before the run, be near the bank when I lay it out.",
      "Who's the guild's city contact today? I need mats moved and I'm stuck out in %zone% with no flight path.",
      "Anyone heading to the city? I need a summon and I refuse to walk. I have walked enough for three lifetimes.",
      -- Raid & dungeon talk, in-character
      "Summons going out from the city gates in 15 for tonight's run. Repair, restock, and hit the road, team.",
      "Meeting at the Dalaran fountain before we head to Icecrown. Last call for flasks and cold-weather complaining.",
      "Forming up at the Shattrath portals. Anyone not in the city in 10 gets volunteered as off-tank. Don't test me.",
      "Quick city stop before the delve: bank, repair, breathe. You have five minutes. The clock is merciless.",
      "Big congratulations to Bromli for reaching his prime as a warrior. The drinks at the city inn are on the guild!",
      "Looking for a steady %role% and a sharp %class% to round out tonight's run into %instance%. Whisper me.",
      "Last night's run was a glorious mess. We lost three of us to the same trap. We're framing the memory.",
      "Anyone up for %bg% before the raid? I've a grudge to settle and honor to earn.",
      "The guild's tackling %instance% tonight. Bring your courage, your potions, and a story for afterward.",
      "We wiped on that boss four times and beat it on the fifth by sheer stubbornness. That's the guild motto, really.",
      -- Lines using the expanded placeholders
      "We finally dropped %boss% in %instance% on %difficulty% tonight. Everyone earned their %consumable% costs back and then some.",
      "%item% dropped and it went to our %class%. Cheered so loud in %city% the guards came to check on us.",
      "Min %gearscore% gearscore for tonight's %difficulty% run, and bring %consumable%. No exceptions, I love you all.",
      "Our newest %race% recruit just hit %level%. Drinks at the %city% inn are on the guild.",
      "Whoever's grinding %profession%, the vault's stocked. Make us something worth %gold%.",
      "Reminder: we're pushing %rep% rep as a guild this week. Tabard on, let's go.",
      "Saw our raid leader finally win %mount% off %boss%. He's done nothing but %emote% since.",
      "%event% guild meetup at %shop% in %city% this %timeofday%. Be there, costumes encouraged.",
      "Taking %route% to the raid tonight. Leaving at %timeofday%, don't make me wait in this %weather%.",
      "Slow %season% night at %shop% — someone got us all retelling %tale% over drinks. Best kind of evening.",
      -- City meetups & camaraderie (in-character, no meta)
      "Anyone else just stand in the capital and people-watch between runs? Best free entertainment in Azeroth.",
      "I keep my hearthstone set to the city tavern. It's the closest thing I've got to a home and I'm at peace with that.",
      "Took the long walk from the city gates to %zone% today. Forgot how pretty the road is when you're not being chased.",
      "The city bard played our company's 'anthem' tonight. We don't have an anthem. We do now.",
      "Saw some Alliance folk in neutral Booty Bay. We nodded. They nodded. Diplomacy achieved.",
      "Took the boat from Menethil to the city. Spent the whole trip fishing off the side. Recommend it to anyone.",
      "Got the full capital tour done today. My hearthstone's confused and my feet are filing a grievance.",
      "The zeppelin pilot did a barrel roll on the way to the city. I have never gripped a railing so hard in my life.",
      "Crossed paths with a rival company at the city gates. We exchanged glares. Very mature. Very us.",
      "Met up with half the guild in the tavern tonight. No raid, no plan, just laughs. Best night in weeks.",
      "New recruit got lost trying to find our meetup. We found her three districts away befriending a guard. She fits right in.",
      "One of you absolute legends paid off my repair bill at the city vendor without a word. I will find you. To hug you.",
      "Watched a guildmate teach a total stranger how the auction house works in the middle of the city. We're good people, mostly.",
      "The city feels less lonely knowing one of you is probably standing at the same bank somewhere. Sappy, I know.",
      "Tried to look cool leaning on the city fountain. Fell in. A guard slow-clapped. I deserved that.",
      "The guild's unofficial meeting spot is now 'the third lamppost from the bank.' We have our own little legend now.",
      "Watched our raid leader get lost in the city for ten full minutes. This is the man who memorizes every boss's tricks.",
      "Spent an hour just reorganizing the guild vault. It's therapeutic. Don't judge me.",
      -- Festivals, with the guild
      "Brewfest's on. Guild meetup at the city brewery tents. We're getting the achievement OR getting carried home. Either works.",
      "Winter Veil in the city is gorgeous this year. Guild gift exchange at the great tree in 20. No re-gifting the lump of coal.",
      "Hallow's End candy run through the city tonight. Costumes mandatory, dignity optional.",
      "Lunar Festival fireworks over the capital. Guild's gathering on the rooftops. Don't fall. Looking at you.",
      "Midsummer bonfire in the city square. We're defending our home flame and raiding theirs. For honor. And bragging rights.",
      "Darkmoon Faire's in town. Half the guild's already lost their coin to the ring toss. I'm about to make it worse.",
      "Pilgrim's Bounty feast at the city tables tonight. The guild's bringing the whole spread. Come hungry.",
      -- Quiet, heartfelt, in-character
      "Lit a candle in the Cathedral for the guildmates who stopped riding with us. Hope they're well, wherever the road took them.",
      "Sat at the city moonwell after a rough run. Felt better. Funny how a quiet corner can do that.",
      "Some nights I just walk to the city tavern and watch the guild's words scroll by. That's enough. That's plenty.",
      "The capital at dawn before the crowds wake is the most peaceful place I know. Just me, the guards, and a hot drink.",
      "Rough week on the road. Came back to the city tavern, listened to you lot bicker about loot, felt steady again. Thanks, team.",
      "There's something about everyone hearthing back to the same city after a run that feels like family coming home for supper.",
      "Caught the city sunrise with two of you saying nothing in particular. Best kind of nothing there is.",
      "Whatever shape the world's in, gathering back at the city hearth each night keeps me steady. Don't tell anyone I got sappy.",
      "Last one in the city tonight, just me and the night watch. Locking up the guild's corner of the world. See you all tomorrow.",
      "Welcomed a returning member back at the city gates today. Picked up like no time had passed. That's the good stuff.",
      "Initiated a new recruit the proper way: bought them a drink at the city inn and told them which of us never to trust with loot.",
      "Three years riding with this company and we still meet at the same city tavern table. Some traditions are worth keeping.",
      "Reminder that you're all welcome at the city meetup anytime, raid or no raid, talkative or quiet. The bench is big enough.",
      "The cities change banners and kings, but the company stays the company. That's the only home address I really need.",
      "Locking up our corner of the capital for the night. Lamps low, guild chat quiet, all of us safe behind the walls. Rest well.",
      -- Light guild humor, in-world
      "I have been 'right back' in the city for two hours. My character's put down roots. The guards consider me furniture.",
      "Tried to jump from the city rooftops to the fountain. Made it. Then a guard fined me for 'reckless tourism.'",
      "The city auctioneer and I are on a first-name basis now. This is either an achievement or a cry for help.",
      "Someone keeps setting off fireworks inside the bank. I'm not naming names. (We all know who it is.)",
      "Got into a dance-off with a guildmate outside the city inn. The crowd that gathered was the real treasure.",
      "Counted six guildies standing in the city doing nothing. A quorum. I declare this an official meeting. Motion to keep standing: passed.",
      "Tried to show off a new mount in the city and immediately rode it into the fountain in front of the whole guild. Peaked.",
      "Our raid leader got distracted by a transmog vendor mid-summons. We're now twenty minutes late and he looks MAGNIFICENT.",
      "I left my character resting in the city to step away, came back to forty guild messages and a marriage proposal. Eventful.",
      "Tried fishing in the lava at Blackrock Depths on a dare. Caught a pair of crispy boots. Worth it.",
    },
    -- two-person back-and-forth (speakers alternate A / B)
    duos = {
      {"Just tried fishing in the lava at Blackrock Depths.", "Catch anything good?", "A pair of crispy boots and a fireproof rod.", "That's some hot gear.", "Fishing level: Inferno."},
      {"Anyone seen my pet? Last spotted chasing a squirrel in Elwynn Forest.", "I saw a critter stampede headed for Westfall.", "Your pet leading the pack?", "He's now a certified critter herder.", "Lost and found: pet edition."},
      {"I challenged a mage to a duel and all I got was this block of ice.", "Hope you packed a pickaxe.", "I used it as a chance to grab a snack.", "Cool strategy.", "Chill out, they said. It'll be fun, they said."},
      {"Just finished organizing the guild vault. It's a masterpiece of chaos.", "Did you label the mystery potions?", "Of course. They're under 'Surprise Me.'", "I always find the best stuff in the 'Random Junk' crate.", "The vault: where items go for an identity crisis."},
      {"Remember when we tried to take a guild portrait and summoned a boss instead?", "Who knew that gesture was a summoning ritual?", "Best portrait we ever took.", "At least we looked heroic. Briefly.", "Guild portraits, now with more dragons."},
      {"I think our guild mascot should be a murloc.", "Can it be one that doesn't aggro from a mile away?", "Only if it comes with an off switch.", "Mrglrlglr for guild master.", "Murlocs: the unofficial face of chaos."},
      {"Whoever left their mount parked in front of the guild meetup, it's being 'relocated.'", "Was it the one with the flaming hooves?", "It's currently eating the city flowerbed.", "It's just asserting dominance over the petunias.", "The fountain square: no parking for epic mounts."},
      {"Lost in a delve again. Can we get guild breadcrumbs?", "Only if they lead to treasure and not traps.", "I'll trade you a breadcrumb for a map.", "Dungeon mazes: the true endgame.", "Guild breadcrumbs: better than a flight path."},
      {"If our company had a motto, it'd be 'We came, we saw, we got distracted.'", "Isn't that our plan for every raid?", "It's not distraction, it's 'alternative focus.'", "Our specialty: the accidental detour.", "Easily sidetracked, somehow unstoppable."},
      {"I think our guild's favorite spell is 'Conjure Food.'", "Is that before or after 'Resurrect the Whole Party'?", "Definitely before. Can't eat as a ghost.", "Our raids are basically dinner parties with combat.", "Guild priorities: food first, loot second."},
      {"Just spilled my ale across the war table mid-strategy.", "Did it at least improve the plan?", "It made the map of Icecrown look more dramatic.", "So, no.", "The boots are sticky now. The plan stands."},
      {"I named my new pet fish after our guild leader.", "Does it lead all the other fish?", "No, but it keeps swimming into the glass. Very headstrong.", "...checks out, honestly.", "Bold. Loyal. Slightly concussed."},
      {"Why do we always end up back in the city?", "Bank, mail, auction house, repair, and the good tavern. The holy pilgrimage.", "You forgot 'stand around for forty minutes deciding what to do.'", "That's the most sacred step of all."},
      {"Who left their kodo blocking the city mailbox?", "...define 'blocking.'", "It is physically sitting on the mailbox.", "Ah. Yeah. That's mine. He likes the warmth."},
      {"You okay? You've been quiet in guild chat.", "Yeah. Just one of those weeks. The city's a nice place to disappear for a bit.", "We're here if you want company. Or silence. Both are on the menu."},
      {"Anyone selling cloth in the city? Need a stack for the guild tabards.", "Got you. Meet at the auction house.", "You're a hero. A boring, reliable, deeply appreciated hero."},
      {"Why do we ALWAYS stage in the city?", "Because half of us forget our flasks and the auction house is right there.", "...okay that's fair. I forgot my flasks.", "Every. Single. Week."},
      {"Anyone else's hearthstone basically permanently set to the city?", "Mine's been on the same tavern for two years.", "The innkeeper knows me by name. We've been through things.", "We ALL have an innkeeper we'd die for, let's be honest."},
      {"How long have you been standing in the city today?", "Yes.", "That's not an answer.", "It's the only honest one I have."},
      {"Logging the night off. See you all in the city tomorrow?", "Same bench, same lamppost.", "Same wonderful waste of an evening. Wouldn't trade it.", "Rest well, company. Mind the goblins."},
      {"Can someone in the city repair me? I'm broke and broken.", "On my way with the gear.", "You are the guild's beating heart and also its only responsible adult."},
      {"Why is our meeting in the city again? We've got a whole hall... sort of.", "Because the city has the auction house, the bank, AND the good tavern.", "And because none of us can agree on anything that requires actually leaving.", "Democracy in action."},
      {"Who keeps mounting up inside the city bank?", "Not it.", "Not it.", "...there are three of us in this conversation and the kodo is still in the bank, so SOMEONE is lying."},
      {"You good? Quiet tonight.", "Yeah. Just parked in the city, watching the lamps. One of those nights.", "Want company or quiet?", "Company. Pull up a bench."},
      {"Anyone free to help a new guildie find the city trainers?", "On it. Meet at the gate.", "You're doing the Light's work. Or the Earth Mother's. Whichever's on shift."},
      {"Long day on the road. Mind if I just sit in the city with you all a bit?", "Always. Bench's right here.", "The good bench. With the view of the lamps.", "Best seat in Azeroth. Welcome home."},
      {"Heard a rumor the King's calling another muster north.", "Then some of us may be marching soon.", "...let's get one more quiet night at the tavern first.", "Agreed. The war can wait till morning."},
      {"We've spent more hours standing in the city than actually adventuring.", "And you'd change it?", "Not for all the loot in Azeroth.", "Then it was time well wasted. Same tomorrow."},
    },
    -- group discussions (many voices, rotating cast of 4-6)
    groups = {
      {"Alright, who's in for tonight's run? Summons go from the city gates in 15.", "I'm in. Repairing now, then I'm on the boat.", "Count me in, but someone remind me to grab flasks. I always forget the flasks.", "We KNOW you forget the flasks. I've got a spare stack in the vault for you. Again.", "Bless you. This is why you're my favorite.", "I'll heal, but I'm only patching up people who laugh at my jokes. Steep terms, I know.", "I'll be five minutes late. The city tailor's finally got my robe and I refuse to march underdressed.", "Priorities. Respect.", "Right, that's the band. Repair, restock, and to the road. Try not to die before the first boss this time.", "No promises. But I'll die heroically, which is basically the same thing."},
      {"Settle a guild debate: which capital do we actually call home base?", "Wherever the auction house and the good tavern are. So, the city.", "We've staged in a different one three weeks running because nobody agrees.", "That's tradition now. The Great Capital Confusion. I've been in the wrong city for an hour, can confirm.", "I vote we just plant our flag at the third lamppost from the bank and call it official.", "Seconded. The lamppost has served us well. It's seen things.", "Plaque pending. Someone's working on the plaque.", "...the plaque has been 'pending' for a year.", "It's the thought that counts. To the lamppost.", "To the lamppost. Our true and noble home."},
      {"Anyone else feel the guild's quieter since the call to march north?", "A few of ours signed on with the Argent Crusade. The hall feels emptier.", "My oldest friend in the company went. Said someone had to. I couldn't argue.", "Icecrown's a hard road. We light a candle for them at the Cathedral each night.", "They'll come back. Most of them. We keep their tavern stools warm till they do.", "That's the plan. Warm stools, full tankards, a place at the table held open.", "When they ride back through those city gates, we throw the loudest welcome the capital's ever heard.", "...Light keep them. Earth Mother hold them. Whatever you pray to, pray it loud.", "Aye. To absent company. May the road bring them home.", "To absent company. Same bench waiting."},
    },
  },

  alliance = {
    -- standalone one-liners (single speaker)
    lines = {
      "Anyone at the Stormwind bank? I'm dropping off mats for the crafters before we head out.",
      "Sitting in the Ironforge tavern with a full tankard and zero will to do my dailies. Join me in productive avoidance.",
      "Guild meetup at the Darnassus moonwell tonight. Bring your prettiest transmog, we're taking portraits.",
      "The Stormwind auction house ate my entire week's gold. I regret everything and nothing, all at once.",
      "Dropped off a stack of ore in the Ironforge vault for our smiths. Make something that'll make the rivals weep.",
      "At the Stormwind fountain if anyone needs a summon before the run. Yes, the fountain. We always meet at the fountain.",
      "The Lion's Pride bard learned a new verse about a dragon. Half of it's wrong but it's about US now, so. Honored.",
    },
    -- two-person back-and-forth (speakers alternate A / B)
    duos = {
      {"Where's everyone hanging out tonight?", "Stormwind, by the fountain.", "Naturally. We are creatures of habit and good benches."},
      {"Reminder: guild portrait at the Stormwind fountain at dusk.", "Last time someone summoned a boss instead.", "That was ONE time and the portrait was incredible.", "Fine, but I'm standing in the back this time."},
      {"Let's start a dance in the Ironforge commons.", "Can dwarves really dance?", "We're about to find out.", "Ironforge's got talent.", "A dwarven dance-off, coming right up."},
      {"Heard the muster's calling Stormwind's regiments north.", "Then some of us march soon. Icecrown waits for no one.", "...one more night at the Lion's Pride first.", "Aye. The war keeps till morning."},
    },
    -- group discussions (many voices, rotating cast of 4-6)
    groups = {
      {"Where should the guild stage tonight, before we ride out?", "Stormwind fountain. It's tradition and it's central.", "Ironforge, surely. Warm tavern, and the smiths can do last repairs.", "Darnassus if we want pretty portraits first. The moonwell's glowing tonight.", "...we're going to argue about this for twenty minutes and end up at the fountain anyway.", "We always end up at the fountain.", "The fountain it is. Summons going out. Don't fall in this time."},
    },
  },

  horde = {
    -- standalone one-liners (single speaker)
    lines = {
      "Meet at the Orgrimmar zeppelin tower in 10. Don't make me hold the boat. Again.",
      "I'm parked at the Undercity bank if anyone needs mats. Try not to get lost in the canals on the way down.",
      "Standing at the Thunder Bluff rise watching the sunset. A slot's open for anyone who wants to just... not raid for once.",
      "Saw the funniest thing in Orgrimmar: a goblin trying to sell a 'pre-owned' tabard to a Kor'kron guard.",
      "A Forsaken courier dropped a sealed letter at the Undercity bank and vanished. The whole company's curiosity is piqued.",
      "Dropped a stack of ore in the Orgrimmar vault for our smiths. Forge me something that'll make the Warchief jealous.",
      "Rumor in Orgrimmar: the Warchief's mustering for a march. Our war council (three of us in a tavern) is already debating.",
    },
    -- two-person back-and-forth (speakers alternate A / B)
    duos = {
      {"Meet at the Orgrimmar gates or the zeppelin tower tonight?", "Gates. The tower's a madhouse since the call-up.", "Gates it is. Bring your axe and your patience.", "I've got the axe. Patience is sold out."},
      {"The Warchief's banners went up across Orgrimmar overnight.", "Garrosh doesn't do quiet.", "Think we'll be called to march?", "Sharpen your blade and find out. We always end up where the war is."},
      {"A shaman warned me the elements are restless under the city.", "Aye, the earth's been grumbling for weeks.", "Omen, or just the forges?", "The old ones say omen. I've learned to listen to the old ones."},
    },
    -- group discussions (many voices, rotating cast of 4-6)
    groups = {
      {"Where's the company staging before tonight's run?", "Orgrimmar gates. Central, and the forge is close for repairs.", "Thunder Bluff, if we want a moment of quiet before the blood and noise.", "Undercity's closer to the road north, if that's where we're bound.", "...we'll argue, then end up at the Orgrimmar bank like always.", "The bank it is. Lok'tar. Restock, repair, and ride.", "To the run. May our axes stay sharp and our flasks stay full."},
    },
  },

}
