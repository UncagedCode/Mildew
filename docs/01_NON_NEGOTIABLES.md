# 01 — Non-Negotiable Design Rules

These are locked decisions. Do not reinterpret them for convenience.

## Product / platform

1. Primary host is **Android TV** running a Godot application.
2. 2–8 players join from ordinary phone browsers over the same local Wi‑Fi.
3. Core multiplayer works without internet.
4. Xbox Series X Developer Mode is a future/fallback host option; architecture must stay portable.
5. Phone controllers are portrait-first.
6. Main TV output is 16:9, but the fictional programme is normally presented as authentic 4:3 late-1990s television.
7. Mid-range Android TV hardware is the performance target.
8. Normal presentation aims for 60 FPS; occasional heavier effects may run at 30 FPS if required.
9. Readability, input responsiveness and reliable reconnects outrank decorative effects.

## Creative identity

10. Mildew is a **comedy/adult party game first**, not a horror game.
11. The intended tone is gross, inappropriate, absurd, funny, occasionally disturbing and subtly sinister.
12. Players should sometimes feel wrong for continuing to participate.
13. The programme never explicitly explains that it is haunted/supernatural.
14. The true cause of irregularities remains intentionally unresolved.
15. No canonical named monster/demon/entity reveal by default.
16. Sinister incidents are implication, not lore dumps.
17. The programme moves on immediately after disturbing moments.
18. The show never transforms visually into a conventional dark/red horror aesthetic.
19. Even disturbing scenes look like footage being broadcast through the same old TV production.
20. Authentic bad-television incompetence and genuinely disturbing anomalies must coexist.
21. Not every glitch is sinister; some are simply cheap television.
22. Not every suspicious message is truthful.
23. Full/default interference means maximum *eligible repertoire*, not constant frequency.
24. Some sessions may remain unusually clean.
25. Do not catalogue creepy events or give completion percentages for them.

## Graham

26. Graham is a recognisably human presenter, not a monster.
27. Default state is professional, cheerful and matter-of-fact.
28. He can have favourites, dislikes, grudges, targets and pet projects.
29. He can humiliate contestants in theatrical in-game ways.
30. He can occasionally punish one player or everyone because of one player.
31. He may rarely alter/misrepresent an answer for humiliation/punishment.
32. He may rarely eject someone from one short segment, not from the actual session.
33. He may sometimes disagree with official scoring without changing it.
34. He can be visibly annoyed or angry, but this is rare enough to matter.
35. He may occasionally remember selected grudges/jokes across sessions.
36. He can defend a player from the audience or show sympathy; he is not uniformly malicious.
37. Humiliation must derive from in-game behaviour, not real protected/personal characteristics.
38. He may call out AFK behaviour, repeated mistakes, fast gross knowledge, recurring answer categories and avatars.

## Announcer / production

39. A separate Announcer exists.
40. The Announcer begins as a calm formal continuity voice.
41. Announcer awareness/conflict can progress slowly across sessions.
42. Graham may suppress or contradict the Announcer.
43. The Announcer is not confirmed as trustworthy.
44. Unknown messages may impersonate any apparent source.
45. A small recurring cast of production staff may be named/glimpsed but not formally introduced.
46. Recurring backstage rooms exist and can change state across sessions.
47. Their geography is internally consistent.

## Private interference

48. Private phone messages normally disappear and have no in-game history/log.
49. Screenshots work normally.
50. Messages may lie.
51. Messages may contradict each other.
52. Different players may receive different fragments of one rare incident.
53. Phone vibration may be used, including call-like patterns inside the controller experience.
54. Never impersonate the actual system call screen, emergency alert or OS notification UI.
55. Do not require unrestricted microphone access.
56. Microphone access may only be requested transparently for a specific game/explicit fictional feature requiring it.
57. The game may act as if it knows something it does not actually know; do not secretly gather private data to achieve the effect.

## Games / content

58. Launch roster is the fixed 6+2 list in the game spec.
59. Every launch game supports two players through a designed adaptation where necessary.
60. All core games are available from the start.
61. Events/variants/rare interruption material may progressively become eligible.
62. Guess the Genitals uses **animal** genitalia, not human sexual content.
63. Its presentation is clinical/factual rather than pornographic.
64. Real gross facts should genuinely teach something.
65. Huge expandable content libraries are a requirement.
66. Content and incidents are data-driven.
67. Factual claims require source metadata before approval.
68. Real factual imagery requires source/licence/attribution/approval metadata.
69. Do not scrape and silently ship unlicensed factual imagery.
70. Familiarity tiers gradually enable more obscure/inappropriate content.
71. Ordinary repetition is avoided, except when repetition itself is the intended joke/incident.

## Session / scoring

72. Standard broadcast is about 45 minutes.
73. Mildew chooses the normal programme order.
74. Players generally do not know what comes next.
75. Midpoint commercial break doubles as a natural bathroom/snack break.
76. Manual pause remains available.
77. Finale is roughly 1.5× normal scoring, not so large that earlier play is irrelevant.
78. Speed is a small bonus; accuracy matters more.
79. Wrong answers normally score zero rather than subtracting points.
80. Rot is separate from points.
81. Rot can rise for correct/fast disgusting knowledge.
82. Rot does not decrease during a session.
83. Lifetime Rot may persist.
84. Scores are mainly shown between rounds rather than permanently.
85. Personal end awards are important.
86. Graham's Favourite/Least Favourite are not guaranteed every session.
87. Fake prizes end the show; selected prizes may be referenced later.

## Networking / usability

88. Real networking failures must be represented honestly and reliably.
89. Do not use fake disconnects in a way that obscures actual connection state.
90. Disconnecting active player pauses for up to 30 seconds; reconnecting resumes early.
91. Preserve session/input state where practical on reconnect.
92. If enough players remain, the show continues after a player fails to return.
93. If everyone leaves and fails to return, Graham is visibly annoyed and ends transmission.
94. Late join is allowed between games.
95. Normal gameplay should not require holding the Android TV remote.
96. Pause/settings/end transmission must always remain accessible.
97. Broadcast glitches must not make active questions/timers/safety UI unreadable.
98. The server/Director is authoritative; phones never award themselves points.

## Development process

99. Checkpoint 1 is a real Android TV + LAN-phone playable slice, not a desktop mock-up.
100. Mildew styling and Graham/Director exist from the first checkpoint.
101. Every major checkpoint ends with a playable installable APK when the build environment permits it.
102. Maintain detailed progress/status/test documentation inside the repo.
103. Do not silently change locked design decisions.
104. Bring material design-change suggestions to the user before implementing the changed behaviour.
105. Use debug fake players and accelerated full-broadcast simulation.
106. Automated tests must cover 2-player, 8-player, reconnects, content validation and deadlock prevention.
107. Prefer polished vertical slices over racing ahead with ugly generic placeholders.
108. Temporary assets should already resemble the intended Mildew art direction where practical.
