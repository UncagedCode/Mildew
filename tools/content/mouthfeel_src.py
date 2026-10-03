import json, re
# Mouthfeel (CP4). describe: (prompt, tier, gross, tags, graham_answers, archive)
D = [
("COLD PORRIDGE + CARPET UNDERLAY", 1, 3, ["food", "household"], ["Firm at the edges. Forgiving in the middle. Like a vicar."], ["Like chewing a wet doormat that's had good news", "Spongy, then gritty, then personal", "A damp hug that won't end"]),
("A WARM TRIFLE LEFT IN A CAR", 1, 3, ["food"], ["Sad custard. Ambitious sponge. Strong notes of dashboard."], ["Soft layers of regret, separating", "Like a wet nap that tastes of vanilla", "It slides. Everything slides."]),
("THE SKIN ON HOT MILK", 1, 2, ["food"], ["A small edible curtain. Tasteful."], ["Like a tissue that's been crying", "Warm wet paper with ambitions", "A cling film of shame"]),
("A PICKLED EGG FROM A PUB JAR", 1, 3, ["food"], ["Rubbery. Vinegary. Has seen things. Like me."], ["Squeaks against the teeth like an old door", "Like biting a rubber ball full of chalk", "Bouncy, with a dry crumbly secret inside"]),
("A FLANNEL THAT'S BEEN IN THE BATH ALL WEEK", 1, 3, ["household"], ["Slippery cotton with a faint aftertaste of Sunday."], ["Slimy carpet tile, warmed", "Like sucking a sad sheep", "Gritty, heavy, lukewarm regret"]),
("A HANDFUL OF CANDLE WAX", 1, 2, ["household"], ["Waxy. Unhelpful. Romantic, briefly."], ["Like chewing a crayon's ghost", "Clings to your molars like a bad marriage", "Soft then squeaky then forever"]),
("CANNED HOT DOG + THE BRINE", 1, 3, ["food"], ["A long pink thought, swimming."], ["A rubber finger in salty bathwater", "Squidge, then a pop, then cold juice", "Like chewing a wet balloon from a funeral"]),
("A MOUTHFUL OF HAIR FROM A PLUGHOLE", 2, 4, ["body_fluids", "household"], ["Fibrous, with pockets. Richer than you'd expect."], ["Slippery string with crunchy bits of soap", "Like flossing with someone's memories", "A wet nest that coughs back"]),
("A BOILED SWEET FOUND DOWN A SOFA", 1, 2, ["food", "household"], ["Sweet. Furry. Possibly mine."], ["Sticky glass with a woolly coat", "Like licking a tiny carpet that tastes of strawberry", "Crunch, then lint"]),
("CHEWING GUM FROM UNDER A SCHOOL DESK", 1, 4, ["body_fluids"], ["Historical. Tough. Still faintly mint."], ["Concrete with a memory of spearmint", "Grey rubber that crumbles like gravel", "It fights back, then gives up"]),
("A SLUG ON A CRACKER", 2, 4, ["animals", "food"], ["A canapé. Firm base, lively topping."], ["Crunch, then a cold snotty sigh", "Like a sneeze on a Jacob's", "Slick, then crispy, then it moves"]),
("TINNED SPAGHETTI LEFT OUT OVERNIGHT", 1, 2, ["food"], ["Orange worms in a quiet sauce."], ["Soft tubes in a skin of tomato glue", "Like eating a cold slinky", "It sets. Like jelly. Bad jelly."]),
("SOMEBODY ELSE'S RETAINER", 2, 4, ["teeth", "body_fluids"], ["Plastic. Intimate. You know too much now."], ["Smooth with a crust of someone's breakfast", "Like licking a stranger's yesterday", "Hard and slippy, with crumbs"]),
("A DEEP-FRIED FLANNEL", 2, 3, ["food", "household"], ["Crispy outside. Damp soul."], ["Crunchy batter, then soggy cotton", "Like biting into a hot wet nap", "A chip shop lie"]),
("AN OYSTER THAT WAS LEFT ON A RADIATOR", 2, 4, ["food", "animals"], ["Slippery. Warm. Fond of you."], ["A warm sneeze from the sea", "Like swallowing a loose tongue", "Gloopy, gritty, then it lingers"]),
("A BOWL OF HAM FAT", 2, 3, ["food", "studio_world"], ["The best bit. I won't hear otherwise."], ["White, soft, cold, like candles from a pig", "Melts like a dream you'd rather not have", "Slippery chunks of fridge"]),
("THE GLUE ON THE BACK OF AN ENVELOPE", 1, 1, ["household"], ["Faint sweetness. Postal. Bureaucratic."], ["Like licking a stamp's armpit", "Dry, then tacky, then lonely", "Tastes of Tuesdays"]),
("A CORN PLASTER", 2, 4, ["medical", "body_fluids"], ["Medicinal. Felt-like. Recently worn."], ["Spongy felt with a cheesy undernote", "Like a tiny shoe insole", "Gummy, with grit"]),
("A RAW EGG, SHELL AND ALL", 1, 3, ["food"], ["Crunchy and smooth. A complete meal."], ["Glassy crunch then cold snot", "Like chewing a lightbulb full of phlegm", "Shards in a slippery pool"]),
("A BATH SPONGE SOAKED IN GRAVY", 2, 3, ["food", "household"], ["Absorbent. Hearty. Sunday."], ["Squeezes gravy into every corner of your soul", "Like chewing a hot wet cloud", "Bouncy brown regret"]),
("A SPOONFUL OF POND", 2, 3, ["animals"], ["Earthy. Lively. Several textures at once."], ["Gritty water with surprises that swim", "Slimy bits with crunchy bits", "Like drinking a duck's opinion"]),
("FIVE-DAY-OLD BIRTHDAY CAKE", 1, 2, ["food"], ["Dry as a sermon. Icing like a roof tile."], ["Crumbles to sand, then sticks like cement", "Like eating a dusty pillow", "Stale sponge, angry icing"]),
("A FISHFINGER THAT'S BEEN IN A POCKET", 2, 3, ["food"], ["Warm. Bendy. Trusting."], ["Floppy crumb with lint seasoning", "Like a tiny warm wet book", "Soft, then fluff"]),
("YOUR OWN TONGUE, BUT SOMEONE ELSE'S", 4, 3, ["unsettling_capable"], ["Familiar. Warm. Not yours."], ["Like a slug that knows your secrets", "Wet velvet that disagrees with you", "It moves first"]),
("A JAR OF CHUTNEY FROM 1983", 3, 3, ["food", "mould_fungi"], ["Matured. Fermented. Vintage."], ["Chunky fizz with a furry top", "Like eating a compost heap's jam", "Sweet, sharp, and alive"]),
("THE FLUFF FROM A TUMBLE DRYER", 1, 2, ["household"], ["Warm, light, and full of your best socks."], ["Like chewing a cloud that's been to a laundrette", "Dry, then pasty, then everywhere", "Grey candyfloss"]),
("A SCOTCH EGG MADE BY A STRANGER", 2, 2, ["food"], ["Dense. Mysterious. Suspiciously warm."], ["Crumbly armour, rubbery heart", "Like biting a damp tennis ball", "Grit, gristle, then yolk"]),
("THE STUDIO C FLOOR", 3, 3, ["studio_world"], ["Firm. Sticky in the corners. Historic."], ["Varnish, crumbs and old applause", "Tacky, like a cinema floor with a past", "It tastes of 1998"]),
("A BAG OF WET CRISPS", 1, 2, ["food"], ["The crunch has left. Only the salt remains."], ["Floppy salt cards", "Like chewing a soggy beer mat", "Limp, cold, and still a bit cheesy"]),
("GRAVY THAT HAS FORMED A SKIN", 1, 2, ["food"], ["A brown blanket. Comforting, if you're a ghost."], ["Thick rubbery lid over brown lava", "Like peeling a scab off Sunday", "Wobbly sheet, then gloop"]),
]
CHAIN = [
("A CHEESE SANDWICH", 1), ("A CUP OF TEA", 1), ("A BOWL OF CORNFLAKES", 1), ("A SAUSAGE ROLL", 1),
("A BATH", 1), ("A KISS ON THE CHEEK", 1), ("A PRAWN COCKTAIL", 2), ("A FULL ENGLISH BREAKFAST", 1),
("A SLICE OF HAM", 2), ("A PAIR OF SOCKS", 1),
]
REVERSE = [
("Warm, slightly fibrous, initially soft but unexpectedly crunchy.", ["A cheese and onion pasty", "A bird's nest", "A Victorian wig", "A hot dog with the string on"], 0),
("Cold. Gelatinous. Wobbles when you look at it. Tastes faintly of the sea.", ["Fish jelly from a pork pie", "A jellyfish", "Frogspawn", "Contact lens fluid"], 0),
("Squeaks against the teeth. Salty. Faintly rubbery. Resists.", ["Halloumi", "A bath plug", "A pickled egg", "A squash ball"], 0),
("Powdery on the outside, then sticky, then it simply will not leave.", ["A Turkish delight", "Chalk", "A stamp", "Peanut butter on a moth"], 0),
("Slippery, then gritty, with a lingering note of seaside.", ["An oyster with sand in it", "A wet sandal", "A cockle", "A lifeguard's whistle"], 0),
("Fluffy, sweet, collapses into nothing, then sticks to your face.", ["Candyfloss", "Bath foam", "Cotton wool", "A sheep's eyebrow"], 0),
("Crisp at first. Then wet. Then a sort of hot rubber. Then grief.", ["A deep-fried Mars bar", "A microwaved pasty", "A fried egg on a radiator", "A battered sausage"], 1),
("Dense. Heavy. Grey. Slightly gritty. Served with pride.", ["Liver", "Chewing gum from 1979", "Black pudding", "A paving slab"], 0),
]
items = []
def slug(s): return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")[:32].rstrip("_")
for p, tier, g, tags, ga, arch in D:
    items.append({"id": "mf." + slug(p), "enabled": True, "quality_status": "draft", "familiarity_tier": tier,
        "content_tags": ["grossness_%d" % g] + tags, "min_players": 2, "max_players": 8,
        "format": "describe", "prompt": p, "hint": "DESCRIBE THE MOUTHFEEL.", "graham_answers": ga, "archive": arch})
for b, tier in CHAIN:
    items.append({"id": "mf.chain." + slug(b), "enabled": True, "quality_status": "draft", "familiarity_tier": tier,
        "content_tags": ["grossness_2", "food"], "min_players": 3, "max_players": 8, "format": "chain", "base": b,
        "prompt": b})
for i, (desc, opts, correct) in enumerate(REVERSE):
    items.append({"id": "mf.rev.%d" % (i + 1), "enabled": True, "quality_status": "draft", "familiarity_tier": 1,
        "content_tags": ["grossness_2", "food"], "min_players": 2, "max_players": 8, "format": "reverse",
        "prompt": "WHAT IS GRAHAM DESCRIBING?", "description": desc, "options": opts, "correct": correct,
        "fact": "“%s”" % desc, "answer_label": opts[correct]})
pack = {"pack_id": "mouthfeel.core_cp4", "content_kind": "mouthfeel",
        "_comment": "Mouthfeel (CP4). Original writing. format: describe (write+vote on a category), chain (Make It Worse, 3+ players), reverse (Graham describes, players guess). graham_answers are entered anonymously by Graham.",
        "items": items}
pack["game_id"]="mouthfeel"
json.dump(pack, open("/home/claude/mildew/content/games/mouthfeel/core_cp4.json", "w"), indent=1, ensure_ascii=False)
print(len(items))
