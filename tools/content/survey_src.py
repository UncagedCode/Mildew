import json, re
# Mildew Survey (CP4). (prompt, tier, grossness, extra_tags, [archive answers])
S = [
("What's the worst thing to discover underneath a hotel mattress?", 1, 2, ["household"], ["Another mattress", "A second, smaller guest", "Your own birth certificate", "A note saying 'turn it back over'", "Warmth"]),
("What's something you absolutely shouldn't lick?", 1, 2, [], ["The bus window", "A battery, again", "Grandad's war medal", "The Studio C floor", "Anything labelled 'specimen'"]),
("What's the least reassuring thing a surgeon can say?", 1, 1, ["medical"], ["Whose turn is it?", "Oh, it's a big one", "I'll just pop out for a bit", "Has anyone seen my watch?", "Nurse, the book"]),
("What shouldn't make a crunching sound?", 1, 2, ["food"], ["Soup", "A baby", "Your knee at the wedding", "Yoghurt", "The carpet in the Green Room"]),
("What's the worst thing to find in a jar at your nan's house?", 1, 2, ["household"], ["Teeth. Not hers.", "Pickled grandad", "Forty years of buttons and one eye", "Something still moving", "Her old tonsils, labelled"]),
("Name a smell that should be illegal.", 1, 2, ["body_fluids"], ["Hot dog water", "Wet Labrador in a Vauxhall", "The back of a minibus", "The canteen on a Friday", "Feet in tights"]),
("What's the worst name for a children's ice lolly?", 1, 1, ["food"], ["The Leaky Uncle", "Mr Damp", "Little Gristle", "Sweaty Pete", "The Lingerer"]),
("What would be the worst thing to hear from the next toilet cubicle?", 1, 3, ["scatological"], ["Applause", "'Oh, it's got legs'", "Your mum's voice", "Chewing", "'Hello? Is that the studio?'"]),
("What's the worst thing to say on a first date?", 1, 1, [], ["I've already named our children", "My mother is in the car", "Do you mind if I take my teeth out?", "This is my fourth today", "I've seen you before. On a tape."]),
("What should never be served warm?", 1, 2, ["food"], ["Milk from a stranger", "Prawns", "Trifle", "A handshake", "Toilet seats, but here we are"]),
("What's the most disappointing prize on a game show?", 1, 0, ["studio_world"], ["A tea towel with the host on it", "A voucher for this programme", "Another go", "A dead plant", "Graham's old coat"]),
("What's living in the bottom of your fridge right now?", 1, 2, ["food", "mould_fungi"], ["A cucumber that has given up", "A family", "Liquid lettuce", "An opinion", "Something from 1998"]),
("What's the worst thing to find in a second-hand coat pocket?", 1, 2, [], ["A warm sausage", "Somebody's toenail collection", "A wet tissue, folded with care", "Your own name and address", "A ticket to this show"]),
("What's the worst thing a dentist could find in your mouth?", 1, 2, ["teeth", "medical"], ["Another mouth", "A lost Lego man", "A small fern", "Somebody else's tooth", "Signs of life"]),
("What should a pub never put on the menu?", 1, 2, ["food"], ["Mystery Pie (Ask Barry)", "Soup of the Week", "Landlord's Leftovers", "Hot Gravy Shot", "The Floor Special"]),
("What's the worst thing to be the 'world's largest'?", 1, 2, [], ["Ingrowing toenail", "Scab", "Earwax candle", "Bin", "Damp patch"]),
("What do you never want to hear a plumber say?", 1, 2, ["scatological", "household"], ["It's come back up", "Well, there's your hamster", "That's not mine", "It's not a pipe problem, love", "I've seen this before. Once. It was bad."]),
("What's the worst flavour of crisp?", 1, 2, ["food"], ["Prawn Breath", "Damp Dog", "Gravy & Mint", "Old Penny", "Hospital Corridor"]),
("Name something you'd hate to step on barefoot in the dark.", 1, 2, ["household"], ["A cold wet slice of ham", "A slug, the big kind", "A plug", "A face", "Something that says 'ow' back"]),
("What's the worst thing to find in a bath when you get in?", 1, 3, ["body_fluids"], ["Someone else's warmth", "A lot of hair that isn't yours", "A pickled egg", "Your dad", "An eel, just resting"]),
("What would be the worst job at this studio?", 1, 1, ["studio_world"], ["Cleaning the Green Room sofa", "Graham's make-up", "Ham inventory", "Tape room nights", "Whatever Neil does"]),
("What's the worst thing to sneeze into your hand during a handshake?", 1, 3, ["body_fluids"], ["Something solid", "Your fillings", "A raisin you forgot about", "A whole cold", "An apology"]),
("What's the worst thing to find in a sandwich you've already bitten?", 1, 3, ["food"], ["The other half of a worm", "A plaster", "A ring that isn't yours", "Hair, braided", "Teeth marks that aren't yours"]),
("What's the least appealing thing to rub on your skin?", 1, 2, [], ["Cold soup", "Hot butter", "A cat's secret cream", "Pond", "Chip shop vinegar, warm"]),
("What's the worst thing your doctor could say while looking at an X-ray?", 1, 1, ["medical"], ["Is that a fork?", "Oh, that's a face", "I've never seen two of those", "Do you know what that is?", "That's not a bone"]),
("What would be the worst theme for a wedding?", 1, 1, [], ["Sewage", "Your ex", "The Black Death", "Graham Mildew", "Damp"]),
("What's the worst thing to be the smell of a new car?", 1, 2, [], ["Wet nan", "Egg", "Feet that have walked far", "Old crisps and fear", "The previous owner"]),
("What's the worst thing to find at the bottom of a ball pit?", 1, 3, [], ["A man named Roger", "Thirty years of socks", "A soft, warm ball", "A nest", "The exit"]),
("Name something you should never microwave.", 1, 1, ["food"], ["Fish at work", "A pet", "Eggs, in shells, in rage", "Your phone, again", "Anything still alive"]),
("What's the most upsetting thing to find in a bag of salad?", 1, 2, ["food", "animals"], ["A frog with no plans", "A slug in a little coat", "Another receipt", "A fingernail", "Soup"]),
("What's the worst sound a car can make?", 1, 0, [], ["A scream", "A cough", "A slow wet slap", "Someone in the boot knocking", "Your name"]),
("What's the worst thing to keep in your pocket all day?", 1, 2, ["food"], ["A hard-boiled egg, peeled", "A wet sock", "A prawn", "A small soup", "Somebody's baby tooth"]),
("What should never come in a can?", 1, 2, ["food"], ["Whole chicken", "Breakfast, all of it", "Pudding with the bits in", "Hair", "Tinned human advice"]),
("What's the worst thing to be greeted with at a party?", 1, 1, [], ["A hug from behind", "A wet kiss from the dog", "Everyone's coats, warm", "Your own photo", "Silence and an empty buffet"]),
("What's the most disgusting thing you could do in a library?", 1, 3, ["body_fluids"], ["Lick the large print section", "Clip toenails into an atlas", "Eat an egg very loudly", "Ask for 'the book'", "Undress in Reference"]),
("What's the worst thing a pet could bring into the house?", 1, 2, ["animals"], ["Half a rabbit", "A neighbour", "Another pet", "A sock that isn't ours", "A tooth"]),
("What's the worst thing to find on a seat on the night bus?", 2, 3, ["body_fluids"], ["A warm patch", "Some chips, used", "A man asleep under a coat", "A single wet glove", "A tooth with a filling"]),
("What would make the worst air freshener?", 2, 2, ["household"], ["Mature Cheddar", "Changing Room", "Uncle's Car", "Hot Bin Juice", "Studio C"]),
("What would be the worst thing to find in a hot dog?", 2, 3, ["food"], ["The dog", "A plaster from 1987", "A zip", "Hair, but long", "A message"]),
("What's the worst way to wake up?", 2, 1, [], ["Being licked by something with no tongue", "Already on TV", "In a bath of beans", "In a different house", "Graham at the foot of the bed"]),
("What's the worst thing someone could leave in a shared office fridge?", 2, 3, ["food", "body_fluids"], ["A labelled stool sample", "Breast milk, unlabelled", "Their teeth", "A head of cabbage, and a head", "A note: 'TAKE IT IF YOU DARE'"]),
("What's the worst thing to hear during a massage?", 2, 1, [], ["'Oh, there's a lump'", "Slurping", "'I'm not a masseur, I'm the cleaner'", "The masseur's stomach", "Clapping from the next room"]),
("What's the worst ingredient for a birthday cake?", 2, 3, ["food"], ["Grout", "Mince", "Tears", "Fish paste", "The birthday boy"]),
("What would be the worst job for a robot?", 2, 2, [], ["Proctologist", "Grandad's nails", "Licking stamps for the council", "Bins after a wedding", "Presenting this programme"]),
("Describe your last meal in three disgusting words.", 2, 2, ["food"], ["Wet. Brown. Warm.", "Chewy. Grey. Regret.", "Lukewarm. Gristle. Pain.", "Soft. Damp. Lonely.", "Pastry. Fluid. Why."]),
("What's the most horrible thing to find written on a toilet door?", 2, 2, ["scatological"], ["'IT'S BEHIND YOU'", "Your mum's number", "'HELP ME'", "'DON'T FLUSH. TRUST ME.'", "'CAROL WAS HERE'"]),
("What should never be described as 'moist'?", 2, 2, [], ["A handshake", "A sermon", "The vicar", "A sofa", "A hug from Graham"]),
("What do you think Graham keeps in his dressing room?", 2, 1, ["studio_world"], ["Forty identical ties", "A photo of himself, framed by himself", "A mini fridge of ham", "His other face", "Neil"]),
("What's the worst thing to hear over the tannoy in a supermarket?", 2, 1, [], ["'Clean up in aisle 4. Bring a shovel.'", "'Will the owner of the arm please...'", "Breathing", "Your full name and address", "'Everyone stay very still.'"]),
("What's the most disturbing thing to find growing in your shower?", 2, 3, ["mould_fungi"], ["A mushroom with a face", "Hair that isn't from your head", "A second, smaller shower", "Fur", "Teeth"]),
("If this studio had a smell, what would it be?", 3, 2, ["studio_world"], ["Burnt dust and aftershave", "Ham", "Damp carpet and cigarette", "Fear and hairspray", "Something under the floor"]),
("What's in the locked room?", 3, 1, ["studio_world", "unsettling_capable"], ["Old props", "More chairs", "Nothing. It's just a room.", "Don't.", "The 1998 Christmas special"]),
]
items = []
for i, (p, tier, g, tags, arch) in enumerate(S):
    slug = re.sub(r"[^a-z0-9]+", "_", p.lower()).strip("_")[:60].rstrip("_")
    modes = ["popularity", "popularity", "archive", "who_said"]
    items.append({
        "id": "sv." + slug, "enabled": True, "quality_status": "draft",
        "familiarity_tier": tier, "content_tags": ["social", "grossness_%d" % g] + tags,
        "min_players": 2, "max_players": 8, "prompt": p, "archive": arch, "modes": modes,
    })
pack = {"pack_id": "survey.core_cp4", "content_kind": "mildew_survey",
        "_comment": "Mildew Survey prompts (CP4). Original writing. 'archive' = authored Mildew archive answers used as filler for small groups and for ARCHIVE rounds.",
        "items": items}
pack["game_id"]="mildew_survey"
json.dump(pack, open("/home/claude/mildew/content/games/mildew_survey/core_cp4.json", "w"), indent=1, ensure_ascii=False)
print(len(items))
