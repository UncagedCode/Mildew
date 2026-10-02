# 12 — Decision Ledger / Reconciliation Record

Purpose: preserve the user's decisions from the design conversation so future implementation sessions do not accidentally flatten them into generic summaries.

This ledger is grouped by topic rather than relying on the overlapping question numbers used during brainstorming.

## Platform and multiplayer

- One Android TV runs the main broadcast.
- Everyone joins via phone on local Wi‑Fi.
- Everything required for normal multiplayer works locally/offline.
- Target 2–8 players.
- Several games are explicitly designed to work from 2+; low-player support must be real adaptation.
- Android TV is primary. Xbox Series X Developer Mode is available as fallback/secondary host if Android TV is too constrained.
- Engine choice: Godot.
- Target mid-range Android TV hardware.
- Design at 1080p, scale to 720p/4K.
- Normal UI/broadcast target ~60 FPS; occasional heavy effects may be ~30 FPS.
- Phone controllers portrait-first.
- Current Android Chrome first; Samsung Internet and iPhone Safari where practical.
- Browser controllers require no install/PWA.

## Session format

- Standard session about 45 minutes.
- Mildew chooses the running order.
- Players generally do not know the next game.
- Sometimes Mildew lets players vote, and Graham may occasionally ignore the vote.
- Around five games in a standard broadcast, depending on runtime.
- Midpoint commercial break acts as bathroom/snack break; manual pause also exists.
- Broadcast can sometimes run 2–5 minutes over.
- Final game roughly 1.5× scoring.
- Finale may sometimes be selected partly from standings.
- Graham may very rarely choose a finale that disadvantages someone he dislikes based on history, while preserving legitimate rules.

## Launch 6+2 roster

Core:

1. Guess the Genitals
2. Hole
3. Mildew Survey
4. Real or Mildew?
5. Police Sketch
6. Do Not Press That

Additional ambitious:

7. The Basement
8. Mouthfeel

All games available from the start. Events/variants may progressively become eligible.

## Guess the Genitals

- Animal genitals only, not human.
- Clinical/factual presentation.
- Real photography preferred where suitable/licensed; illustrations allowed where needed.
- Real biological facts are important.
- Graham may sometimes ask how someone recognised something so quickly.
- Themed rounds are desirable.
- Accuracy dominates scoring; speed only small bonus.
- Optional advanced confidence/wager variant.
- Large long-term library target.

## Hole

- Early-lock risk/reward is required.
- Once locked, cannot change.
- Progressive score decreases with more reveals.
- Misleading scale is desirable.
- Partial category credit sometimes.
- Rare advanced no-multiple-choice version.
- Rare studio-world holes/images can appear.

## Mildew Survey

- Players do not normally vote for themselves.
- Archived responses are central, especially for two players.
- Archived answers may use recurring fictional contestants.
- Old local player answers may later appear as archive responses.
- Simple semantic normalization only initially; no cloud AI dependency.
- `None of these` can exist in selected rounds.
- Graham may rarely discard or alter an answer for a joke/punishment.

## Real or Mildew?

- Fake facts use same factual tone as real facts.
- Images/objects may also be used, not just text.
- Rare `none are real` / `all are real` twists.
- Confidence mechanic supported.
- Short factual explanation on reveal; sources in Viewer Information Service.

## Police Sketch

- Default 4+ format uses drawing/description chains.
- 2-player adaptation swaps roles across prompts.
- Drawing deliberately crude/simple.
- Graham commentary is sparse and can shit-talk the drawings/players.
- Multiple vote categories.
- Original artist can score when chain reconstructs prompt.
- Old drawings may very rarely reappear as evidence/props.

## Do Not Press That

- Must be a real communication/coordination game, not trivia in disguise.
- Team + individual small bonus scoring.
- Mistakes usually cause puzzle consequences, not raw team score subtraction.
- Graham identifies who caused mistakes; rarely may blame wrong player.
- Irrelevant controls allowed.
- Rare timer irregularity allowed.
- Success tiers required.
- Explicit 2-player layouts required.

## The Basement

- Reusable authored scenario system.
- Tone ranges from mundane to disturbing.
- Usually definitive answer, but a minority may remain partially unresolved.
- Players submit final theories individually, not unanimous group submission.
- Partial credit allowed.
- Evidence selection has small efficiency scoring.
- Players can withhold clues socially; game does not force sharing.
- Some uniquely sensitive clues go to one player.
- Recurring locations/characters are desirable.
- No liar role every time.

## Mouthfeel

- Primarily text-driven, with imagery as support where useful.
- Multiple voting criteria, not only funniest.
- Make It Worse collaborative chains required.
- Horrible-choice bonus rounds allowed.
- Graham can anonymously submit and genuinely win.
- Archived old player answers may appear.

## Scoring

- Broadly consistent score scale.
- Exact points matter, but relative position/behaviour matters more than esports balance.
- Usually resolve ties with ridiculous sudden death.
- Graham can very rarely socially ignore/prefer a tied player, while official record can preserve tie.
- Speed bonus capped/small.
- Small streak bonuses.
- Wrong streaks feed Graham/punishment logic.
- Wrong answers normally 0, not negative.
- Rot separate from score.
- Correct/fast disgusting knowledge can increase Rot.
- Rot cannot decrease during a session.
- Lifetime Rot persists.
- Scoreboards mainly between rounds.
- Graham can delay scoreboard.
- Rare scoreboard anomalies allowed.
- End awards are personalised.
- Graham Favourite/Least Favourite not guaranteed.
- Some old titles can briefly appear on return.

## Graham

- Human-looking late-40s/mid-50s British presenter.
- Slightly heightened but believable.
- One iconic outfit.
- Can look more tired/stressed under Pressure, not supernatural.
- Professionally treats gross content as normal.
- Rarely acknowledges weirdness.
- Sometimes weird events anger him.
- Can have favourites.
- Can dislike players.
- Can hold grudges.
- Can sometimes resent dominant winners.
- Can sometimes protect last-place player.
- Can defend someone from audience.
- Can humiliate players theatrically.
- Can target one player with special/punishment questions.
- Punishment sometimes secretly rewards.
- Can punish everyone because of one player.
- Can rarely eject someone from one short segment and give them challenge to return.
- Can disagree with official scoring.
- Rarely can lie about or alter a submitted answer for punishment/humiliation.
- Can put words in a player's mouth.
- Can remember selected grudges across nights.
- Can misunderstand a player and create a recurring false label; rarely persist it.
- Can be visibly angry/rattled; visible emotional state is required.

## Announcer

- Separate formal, calm continuity voice.
- Can progressively become more aware.
- Can disagree with Graham.
- Graham may suppress them.
- May rarely communicate privately to phones.
- Not guaranteed truthful/good.
- Unknown sources can impersonate Announcer.

## Sinister core philosophy

- Subtle sinisterness is a core design philosophy.
- Players should occasionally feel wrong for participating.
- Wrong-camera rooms, random screams, `shut up`, crew arguments and strange phone messages are important.
- The show moves on quickly rather than explaining.
- Full/default interference is the intended experience.
- Full interference must still be sparse/unpredictable.
- Some sessions may have almost nothing major happen.
- Disturbing scenes always remain within the broadcast visual language.
- Do not catalogue hidden incidents.
- Rare incidents should create real-world folklore between players.
- No named monster/entity conclusion.

## Private phone interference

- Messages like `WHY ARE YOU WATCHING THIS?`, `YOU NEED TO HELP ME`, etc. may appear and vanish fast.
- Player may wonder if they hallucinated it.
- Usually only one player sees a given message.
- Sometimes two see same message.
- Sometimes different players receive contradictory fragments.
- Some messages are fake production notes.
- Some are lies.
- Some can mention another player.
- Some predict future content; predictions can be false.
- No in-game message history.
- Screenshots work.
- Phone call-like vibration allowed inside controller session.
- No fake actual system call UI.
- Microphone only with explicit transparent request for a game/feature; no secret listening.
- Rare cross-player distributed incidents are allowed.
- TV may later show something only one player understands from a private message.

## Incident tiers / world

- Minor and major incidents required.
- Five-tier model accepted: production mess, odd, unsettling, major, legendary.
- Tier 4 requires conditions, not pure RNG.
- Small subset can be installation-specific.
- Installation seed hidden.
- Reinstall/reset creates new seed unless restored.
- Recurring rooms exist and change over time.
- Room changes can reverse.
- Recurring production staff can be named/referred to.
- Actual screams are rare.
- `scream + shut up` extremely rare.
- Rare Graham stare/noninteractive beat allowed.
- Interruption Games that “do not exist” are desirable; most do not become permanently selectable.

## Director

- Tracks mood/tone categories.
- Has safeguard against too much horror.
- Has safeguard against too much uninterrupted normal comedy.
- Graham emotional state is separate and visible.
- Graham state can influence game choice, but Director may deliberately do opposite.
- Player behavioural/TV-personality tags are desirable.
- Unfair social labels are desirable.
- Games have separation and opener/middle/finale tags.
- Director may violate pacing deliberately for punishment.
- Every game should have multiple round formats.
- Punishment cooldowns required.
- Humiliation usually spread around, with occasional strong rivalry.
- Familiarity household/category + per-player callback split accepted.
- Gross categories should rotate normally, except deliberate punishment.

## Profiles and memory

- Names entered by players but must be speakable.
- Graham should speak names.
- Use pronunciation validation.
- Returning local profiles.
- Exact duplicate profile names not allowed without disambiguation.
- If new player chooses inactive existing profile name, Graham may ask other players `Is this actually Stacy?`.
- Do not automatically identify by name.
- Players may choose New Contestant/reset identity.
- Remember names, selected statistics, selected jokes, prizes, Familiarity and rare event state.
- Not everything persists.
- Selective progressive event/minigame variants.
- Games themselves all unlocked at start.

## Visual identity

- Main fictional broadcast authentic 4:3.
- Graham realistic/believable, not cartoon.
- Cheap regional 1998 studio.
- Palette: mildew green, nicotine beige, burgundy/purple, teal, cheap gold/chrome, loud gradients.
- Multiple cameras and live switch grammar required.
- Camera switching can be slightly imperfect.
- 8–10 recurring backstage locations in final vision.
- Their geography internally mapped.
- Recurring staff appearances consistent.
- Audience rarely visible clearly.
- Audience size can rarely be inconsistent.
- Opening titles are aggressive 1998 CGI/chrome/lens flare/game-show music.
- Opening mostly fixed with rare variants.
- Every game has short title sting.
- VHS/analogue effects present but restrained enough to keep readability.
- Different footage/tapes can have different degradation.
- Fake adverts have many visual genres/styles.
- Recurring brands have identities/jingles.
- Graham occasionally appears in adverts.

## Audio

- Hybrid Graham voice architecture accepted.
- No voice actor is available; use synthetic/pre-rendered common lines plus offline dynamic speech, replaceable later.
- Announcer distinct calm formal voice.
- Layered audience reaction library required.
- Backstage audio should be spatial where feasible.
- Every game gets its own cheap late-90s musical identity.
- Deliberate silence is important.

## Content/legal metadata

- Factual source metadata required.
- Player does not need citations mid-round.
- In-universe Fact Archive/Viewer Information Service shows sources later.
- Creepy incidents never appear in archive.
- Real factual imagery requires source/licence/attribution/approval.
- Use placeholders until licensed content approved.
- Quality states and enable/disable required.
- Content validators required.
- Dev content browser required.

## Lobby / UX

- Boot like a TV programme, not a generic menu.
- `SALLOW ENTERTAINMENT PRESENTS` / ident / `MILDEW` direction accepted.
- Main options like Begin Transmission / Viewer Information / Broadcast Settings.
- Graham appears while waiting for contestants.
- Join QR + local URL + room code fallback.
- QR does not require code re-entry.
- Phone begins as `MILDEW HOME RESPONSE UNIT — IDENTIFY YOURSELF`.
- Minimum two players.
- Late join between games.
- Up to 30-second reconnect wait; resume early on reconnect.
- Graham comments on people who do not return.
- If all quit/disconnect, Graham visibly annoyed and broadcast ends.
- TV remote provides pause/settings/end, but normal gameplay uses phones.
- Crash recovery can offer `RESUME INTERRUPTED TRANSMISSION`.
- Main controllers portrait.
- Old-broadcast appearance simulated at modern readable quality.
- Hybrid Graham presentation.
- Programme schedule can appear and be wrong.
- Commercial break approximately midpoint.
- Graham can rarely be seen leaving desk/set.

## Development/build

- First real milestone is Android TV + LAN phones.
- Checkpoint 1 already styled like Mildew as closely as practical.
- Graham and minimal Director exist from checkpoint 1.
- CP2 Hole.
- CP3 Real or Mildew + Guess the Genitals.
- CP4 Survey + Mouthfeel.
- CP5 Police Sketch.
- CP6 Do Not Press That.
- CP7 Basement.
- Full Interference Director introduced in stages.
- Every checkpoint ends in installable APK where build environment allows.
- Detailed progress tracking inside repo.
- Claude must bring material change suggestions to user before altering locked design.
- Machine-readable design constants accepted.
- Content by game/system directories.
- Factual and fictional content separated.
- Quality states: placeholder/draft/reviewed/approved.
- Validators required.
- Content Browser required.
- Live Director debug overlay required.
- Detailed Director decision logs in dev.
- Release logs lightweight technical only.
- Save schema versioned/migratable.
- Reset Mildew + separate player/broadcast reset options.
- Content expansion initially via APK updates, not live service.
- Fake bot personalities required.
- Automated pacing/player-count/reconnect validation required.
- Proof of concept should be as close to final experience as practical.
- Vertical-slice polish preferred over broad ugly completion.
- AI-generated provisional art acceptable, tracked as replaceable.
- Graham PoC requires multiple emotional/behavioural states.
- Real camera cuts required early.
- PoC advert/room/content targets in acceptance criteria.
- Familiarity included in PoC.
- A couple of persistent chains included in PoC.
- Tier 4 mostly after PoC; one developer-testable chain proves machinery.
- 1–2 Interruption Games should exist in PoC.
