import json
# The Basement (CP7). Each case: setup, evidence (key clues support question answers), investigations,
# questions with option credits (partial credit), reveal, tone (hidden), unresolved flag, locations/characters.
def ev(id, text, kind="support", supports=None, sensitive=False):
    e = {"id": id, "text": text, "kind": kind}
    if supports: e["supports"] = supports
    if sensitive: e["sensitive"] = True
    return e

def q(id, ask, options, credits):
    return {"id": id, "ask": ask, "options": options, "credit": credits}

CASES = [
 {"id": "bas.birthday_cake", "title": "WHAT HAPPENED IN THE BASEMENT?", "location": "the basement", "tone": "mundane", "tier": 1,
  "setup": "A child's birthday party was being prepared in the studio basement. At 6pm the cake was found destroyed. The door was locked all afternoon.",
  "evidence": [
   ev("e1", "A small window near the ceiling is open. The latch was opened from the inside, days ago, for the damp.", "key", ["who", "how"]),
   ev("e2", "There are small muddy prints across the table. Four toes each. Very neat.", "key", ["who"]),
   ev("e3", "Only the icing and the sponge are gone. The candles have been carefully left in a pile.", "support", ["why"]),
   ev("e4", "The bins outside have been knocked over every night this week.", "key", ["who", "why"]),
   ev("e5", "There is a long reddish hair caught on the window frame.", "key", ["who", "how"]),
   ev("e6", "Neil had the only key to the basement. He was in the canteen all afternoon. Several witnesses.", "support", ["who"]),
   ev("e7", "The birthday boy's uncle 'hates cake' and 'hates that boy'.", "red_herring"),
   ev("e8", "A faint smell of wet dog. Or something like a dog.", "support", ["who"]),
   ev("e9", "The party bags are untouched. The cash box beside them is untouched.", "support", ["why"]),
   ev("e10", "Graham's dressing room is directly above. He says he heard 'a sort of yap'.", "unreliable", ["who"]),
  ],
  "investigations": [
   {"id": "i1", "label": "CHECK THE WINDOW", "text": "The gap is just big enough for something the size of a medium dog. There are claw marks on the sill."},
   {"id": "i2", "label": "SMELL THE CAKE PLATE", "text": "Icing, mud, and something musky and wild. Not a person."},
   {"id": "i3", "label": "ASK THE CARETAKER", "text": "'We've had a fox in the bins all week. Cheeky thing. Ginger.'"},
  ],
  "questions": [
   q("who", "WHO DID IT?", ["A FOX", "THE UNCLE", "NEIL", "GRAHAM"], [1, 0, 0, 0]),
   q("how", "HOW DID THEY GET IN?", ["THE OPEN WINDOW", "NEIL'S KEY", "THROUGH THE WALL", "THEY WERE ALREADY INSIDE"], [1, 0, 0, 0.25]),
   q("why", "WHY?", ["IT WANTED THE CAKE", "REVENGE ON THE BOY", "TO STEAL THE CASH BOX", "A PRANK"], [1, 0.25, 0, 0]),
  ],
  "reveal": "A fox came in through the open basement window, ate the cake, and left the candles in a neat pile. It has done this before.",
  "graham_reveal": "Poor cake.", "characters": ["Neil"], "content_tags": ["animals", "food", "fictional", "grossness_1"]},

 {"id": "bas.canteen_trifle", "title": "WHAT HAPPENED TO THE TRIFLE?", "location": "the staff kitchenette", "tone": "gross", "tier": 1,
  "setup": "The Christmas trifle in the staff kitchenette was found with a deep hand-sized hole in it, and the floor was wet. Three people had access.",
  "evidence": [
   ev("e1", "The hole in the trifle has finger marks. Five fingers. Small hands.", "key", ["who"]),
   ev("e2", "The wet patch on the floor runs from the fridge to the sink, not from the door.", "key", ["what"]),
   ev("e3", "The fridge has been leaking since Tuesday. A bucket under it is full.", "key", ["what"]),
   ev("e4", "Carol from make-up wears a large ring. There is no ring mark in the custard.", "support", ["who"]),
   ev("e5", "Somebody has washed one spoon and put it back, still wet.", "support", ["who"]),
   ev("e6", "The runner, Danny, was seen licking his fingers at 3pm. He says it was jam.", "key", ["who"], sensitive=True),
   ev("e7", "Neil is on a diet and has been 'very honest about it'.", "red_herring"),
   ev("e8", "There is custard on the handle of the tea urn.", "support", ["who"]),
   ev("e9", "The trifle was labelled 'DO NOT. CAROL.'", "support"),
   ev("e10", "Danny wears a size small glove. The hole is the size of a small hand.", "key", ["who"]),
  ],
  "investigations": [
   {"id": "i1", "label": "CHECK THE BIN", "text": "A jam doughnut wrapper. Unopened. So it wasn't jam."},
   {"id": "i2", "label": "LOOK UNDER THE FRIDGE", "text": "The leak is real, and it's a lot of water. The wet floor is the fridge's fault, not a culprit's."},
   {"id": "i3", "label": "CHECK THE URN", "text": "Custard fingerprints on the urn. Small ones. Someone made a cup of tea after."},
  ],
  "questions": [
   q("who", "WHO PUT THEIR HAND IN THE TRIFLE?", ["DANNY THE RUNNER", "CAROL", "NEIL", "NOBODY - IT COLLAPSED"], [1, 0, 0, 0]),
   q("what", "WHY IS THE FLOOR WET?", ["THE FRIDGE IS LEAKING", "THE CULPRIT SPILLED THE TEA", "SOMEBODY MOPPED UP EVIDENCE", "IT'S NOT WATER"], [1, 0.25, 0.25, 0]),
  ],
  "reveal": "Danny the runner put his whole hand in the trifle, washed one spoon in a panic and made himself a cup of tea. The wet floor was just the fridge.",
  "graham_reveal": "Danny's been let go. Not for this. For other reasons. But also for this.", "characters": ["Carol", "Neil", "Danny"], "content_tags": ["food", "fictional", "grossness_2"]},

 {"id": "bas.prop_store", "title": "WHO EMPTIED THE PROP STORE?", "location": "the prop store", "tone": "criminally weird", "tier": 1,
  "setup": "Overnight, every rubber chicken in the prop store disappeared. Forty-one of them. The alarm did not go off.",
  "evidence": [
   ev("e1", "The alarm log shows it was switched off at 01:12 with the correct code.", "key", ["how"]),
   ev("e2", "Only four people know the alarm code: Neil, Carol, Graham and the night guard.", "support", ["who"]),
   ev("e3", "The night guard's van was seen leaving at 01:30, riding very low.", "key", ["who"]),
   ev("e4", "A market stall in town is selling 'vintage TV chickens' this morning.", "key", ["why"]),
   ev("e5", "Graham says he was 'at home, asleep, alone, which is normal'.", "unreliable"),
   ev("e6", "There is a single rubber chicken on the floor of the loading area.", "support", ["how"]),
   ev("e7", "Neil once said the chickens were 'worth a fortune to the right people'.", "red_herring"),
   ev("e8", "The night guard asked last week what the chickens were insured for.", "key", ["who", "why"], sensitive=True),
   ev("e9", "The loading area door was propped open with a fire extinguisher.", "support", ["how"]),
  ],
  "investigations": [
   {"id": "i1", "label": "VISIT THE MARKET STALL", "text": "The stall holder says a man in a security jumper sold them the lot for forty quid."},
   {"id": "i2", "label": "CHECK THE CCTV", "text": "Camera 4 was facing the wall. It is always facing the wall."},
   {"id": "i3", "label": "COUNT THE CHICKENS", "text": "Forty-one missing, one dropped. Forty sold at the market. The numbers work."},
  ],
  "questions": [
   q("who", "WHO TOOK THEM?", ["THE NIGHT GUARD", "NEIL", "GRAHAM", "CAROL"], [1, 0, 0, 0]),
   q("how", "HOW DID THEY GET THEM OUT?", ["ALARM OFF, OUT THROUGH LOADING", "THROUGH THE ROOF", "ONE A DAY FOR WEEKS", "THEY NEVER LEFT THE BUILDING"], [1, 0, 0.25, 0]),
   q("why", "WHY?", ["TO SELL THEM", "A PRANK ON GRAHAM", "INSURANCE FRAUD", "HE LOVES CHICKENS"], [1, 0, 0.5, 0]),
  ],
  "reveal": "The night guard switched the alarm off, loaded forty-one rubber chickens into his van through the loading area and sold forty of them at the market for forty pounds.",
  "graham_reveal": "Forty pounds. For our chickens. Insulting.", "characters": ["Neil", "Carol", "Graham"], "content_tags": ["fictional", "studio_world", "grossness_0"]},

 {"id": "bas.footsteps", "title": "WHO WAS WALKING IN STUDIO C?", "location": "Studio C", "tone": "apparently supernatural", "tier": 2, "unresolved": True,
  "setup": "After the 1998 Christmas special, the cleaner heard footsteps crossing Studio C. The studio was locked and empty. The lights were off.",
  "evidence": [
   ev("e1", "The floor of Studio C was polished that evening. There are no footprints on it.", "key", ["who"]),
   ev("e2", "The heating pipes run under Studio C. They tick and knock as they cool.", "key", ["what"]),
   ev("e3", "The cleaner says the steps 'stopped at the podiums and stood there'.", "support"),
   ev("e4", "Pipes don't usually stop at podiums.", "support"),
   ev("e5", "The cleaner had worked a double shift and hadn't slept.", "key", ["what"]),
   ev("e6", "In the morning, podium 4's lamp was switched on.", "unreliable", ["who"]),
   ev("e7", "Podium 4's lamp switch is faulty. It sometimes turns itself on.", "support", ["what"]),
   ev("e8", "Nobody will say who stood at podium 4 in the Christmas special.", "support", sensitive=True),
   ev("e9", "The building is old and has 'a lot of noises', says Neil, without being asked.", "red_herring"),
  ],
  "investigations": [
   {"id": "i1", "label": "LISTEN TO THE PIPES", "text": "When the heating goes off, the pipes knock slowly, about one step a second."},
   {"id": "i2", "label": "CHECK THE RUNNING ORDER", "text": "The 1998 Christmas running order has a contestant 4. The name has been cut out of the page."},
   {"id": "i3", "label": "ASK THE CLEANER AGAIN", "text": "'It wasn't the pipes. I know the pipes.'"},
  ],
  "questions": [
   q("what", "WHAT MADE THE FOOTSTEPS?", ["THE HEATING PIPES COOLING", "A PERSON HIDING", "A TIRED CLEANER IMAGINING IT", "CONTESTANT 4"], [1, 0, 0.75, 0.5]),
   q("who", "WAS ANYBODY IN STUDIO C?", ["NO ONE", "THE CLEANER", "SOMEONE FROM THE SPECIAL", "WE CAN'T KNOW"], [0.75, 0, 0.25, 1]),
  ],
  "reveal": "The best-supported answer: the heating pipes cooling, heard by an exhausted cleaner. Nobody has explained podium 4's lamp, or the cut-out name.",
  "graham_reveal": "Pipes. It was the pipes. Next question.", "characters": ["Neil"], "content_tags": ["fictional", "studio_world", "unsettling_capable", "grossness_0"]},

 {"id": "bas.wig_urn", "title": "WHY DID THE TEA TASTE OF HAIR?", "location": "the staff kitchenette", "tone": "ridiculous", "tier": 1,
  "setup": "On Tuesday, every cup of tea from the staff urn tasted faintly of hair and hairspray. Production stopped for an hour.",
  "evidence": [
   ev("e1", "Graham arrived on Tuesday 'with a new, more natural look'.", "key", ["who"]),
   ev("e2", "The urn lid was found on the floor. Somebody had looked inside it.", "support"),
   ev("e3", "Make-up reports a hairpiece 'went missing from the dressing room for about an hour'.", "key", ["what"], sensitive=True),
   ev("e4", "The urn's water is a strange shiny brown with a film on top.", "key", ["what"]),
   ev("e5", "Graham's dressing room is next to the kitchenette. He 'never uses the kitchenette'.", "unreliable"),
   ev("e6", "There is a hairnet hanging on the urn tap.", "key", ["who", "what"]),
   ev("e7", "Neil says it was 'obviously the water supply'.", "red_herring"),
   ev("e8", "The hairspray smell is a brand called 'STUDIO HOLD 98'. Only make-up stocks it.", "support", ["what"]),
   ev("e9", "Graham insisted on making his own tea all day 'for reasons'.", "support", ["who"]),
  ],
  "investigations": [
   {"id": "i1", "label": "DRAIN THE URN", "text": "At the bottom: one small, sad, well-steamed hairpiece."},
   {"id": "i2", "label": "ASK MAKE-UP", "text": "'He came in looking for it in a panic. Then he came back with it wet and said nothing.'"},
   {"id": "i3", "label": "TEST THE WATER SUPPLY", "text": "Tap water elsewhere is fine."},
  ],
  "questions": [
   q("what", "WHAT WAS IN THE URN?", ["A HAIRPIECE", "A DEAD RAT", "OLD TEABAGS", "NOTHING - IT'S THE WATER"], [1, 0, 0, 0]),
   q("who", "WHOSE FAULT WAS IT?", ["GRAHAM", "MAKE-UP", "NEIL", "THE WATER BOARD"], [1, 0.25, 0, 0]),
  ],
  "reveal": "Graham dropped his new hairpiece into the urn while trying a 'natural look' between takes, fished it out, and said nothing.",
  "graham_reveal": "That's not what happened and I won't be answering questions.", "characters": ["Graham", "Neil"], "content_tags": ["fictional", "studio_world", "grossness_2"]},

 {"id": "bas.green_room_smell", "title": "WHAT IS THE SMELL IN THE GREEN ROOM?", "location": "the Green Room", "tone": "gross", "tier": 2,
  "setup": "For three days the Green Room has smelled 'like a warm bin full of fish'. Contestants have complained. Somebody was sick in a plant pot.",
  "evidence": [
   ev("e1", "The smell is worst near the sofa.", "key", ["where"]),
   ev("e2", "A prawn cocktail went missing from the hospitality tray on Friday.", "key", ["what"]),
   ev("e3", "The sofa cushions unzip. One zip has been opened and closed recently.", "key", ["where"]),
   ev("e4", "The radiator has been stuck on full since Friday.", "support", ["what"]),
   ev("e5", "A contestant on Friday 'didn't eat anything' but had sauce on their sleeve.", "support"),
   ev("e6", "The plant pot is a separate, unrelated incident. Allegedly.", "red_herring"),
   ev("e7", "There is a faint pink stain on the underside of the middle cushion.", "key", ["where", "what"]),
   ev("e8", "Carol has been spraying perfume 'at it' every morning.", "support"),
   ev("e9", "There is a mouse hole behind the sofa, and the mouse has not been seen since Friday.", "unreliable", ["what"]),
  ],
  "investigations": [
   {"id": "i1", "label": "UNZIP THE CUSHIONS", "text": "Inside the middle cushion: a prawn cocktail glass, on its side, very warm."},
   {"id": "i2", "label": "CHECK BEHIND THE SOFA", "text": "The mouse is fine. It's eating crisps. It looks well."},
   {"id": "i3", "label": "FEEL THE RADIATOR", "text": "Scalding. It's been slow-cooking the sofa for three days."},
  ],
  "questions": [
   q("what", "WHAT IS IT?", ["A HIDDEN PRAWN COCKTAIL", "A DEAD MOUSE", "THE DRAINS", "THE PLANT POT"], [1, 0.25, 0, 0]),
   q("where", "WHERE IS IT?", ["INSIDE A SOFA CUSHION", "BEHIND THE SOFA", "UNDER THE FLOOR", "IN THE RADIATOR"], [1, 0.5, 0, 0]),
  ],
  "reveal": "A nervous contestant hid an untouched prawn cocktail inside a sofa cushion on Friday. The radiator has been gently cooking it ever since.",
  "graham_reveal": "We've burned the sofa. We've kept the mouse.", "characters": ["Carol"], "content_tags": ["food", "fictional", "studio_world", "grossness_3"]},

 {"id": "bas.tape_room", "title": "WHO MOVED THE TAPES?", "location": "the archive/tape room", "tone": "disturbing", "tier": 3, "unresolved": True,
  "setup": "Every morning this week, the archive tapes have been found re-shelved in a different order. The tape room is locked at night. Only one key exists.",
  "evidence": [
   ev("e1", "The archivist keeps the only key on a string around her neck. She sleeps with it on.", "key", ["who"]),
   ev("e2", "The new order isn't random: the tapes are now sorted by contestant number.", "key", ["why"]),
   ev("e3", "Every tape featuring podium 4 has been moved to the top shelf.", "support", ["why"], sensitive=True),
   ev("e4", "There's dust on every shelf, but none on the tapes.", "support"),
   ev("e5", "The archivist sleepwalks. Her flatmate confirms it.", "key", ["who"]),
   ev("e6", "The archivist lives forty minutes away.", "key", ["who"]),
   ev("e7", "The tape room door has a gap underneath. You could slide something under it. Not a person.", "red_herring"),
   ev("e8", "The security guard 'never goes in there'. He says this three times.", "unreliable", ["who"]),
   ev("e9", "One tape has been left playing on the machine: 30 seconds of an empty Studio C.", "support"),
  ],
  "investigations": [
   {"id": "i1", "label": "CHECK THE SIGN-IN SHEET", "text": "Nobody has signed in after 7pm all week. The guard's handwriting is on every line."},
   {"id": "i2", "label": "WATCH THE PLAYING TAPE", "text": "Empty Studio C. At 0:28, the podium 4 lamp comes on."},
   {"id": "i3", "label": "ASK THE ARCHIVIST", "text": "'I don't sleepwalk forty minutes. I'd know.' She looks very tired."},
  ],
  "questions": [
   q("who", "WHO MOVED THEM?", ["THE SECURITY GUARD", "THE SLEEPWALKING ARCHIVIST", "NOBODY WE KNOW OF", "GRAHAM"], [0.75, 0.25, 1, 0]),
   q("why", "WHY THAT ORDER?", ["SOMEBODY IS LOOKING FOR CONTESTANT 4", "ALPHABETICAL MISTAKE", "TO HIDE A TAPE", "NO REASON"], [1, 0, 0.5, 0]),
  ],
  "reveal": "Best supported: someone with access is searching the archive for contestant 4. The guard is the only person who could get in. We don't know that it was him.",
  "graham_reveal": "Nobody needs those tapes. Nobody watches them. Let's move on.", "characters": ["Graham"], "content_tags": ["fictional", "studio_world", "unsettling_capable", "grossness_0"]},
]

items = []
for c in CASES:
    c.update({"enabled": True, "quality_status": "draft", "familiarity_tier": c.pop("tier"), "min_players": 2, "max_players": 8})
    c.setdefault("unresolved", False)
    items.append(c)
json.dump({"pack_id": "basement.core_cp7", "content_kind": "basement", "game_id": "basement",
           "_comment": "The Basement cases (CP7). Original fiction. evidence.kind: key (supports a question's best answer) | support | red_herring | unreliable (players are not told). 'sensitive' cards are flagged privately on the holder's phone. questions[].credit = partial credit per option. tone is hidden from players.",
           "items": items}, open("/home/claude/mildew/content/games/basement/core_cp7.json", "w"), indent=1)
print(len(items))
