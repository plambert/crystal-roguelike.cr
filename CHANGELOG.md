# Changelog

All notable changes to this project are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The version is written in `shard.yml`,
and a tag of the form `vX.Y.Z` builds and publishes a release.

## [Unreleased]

### Added

* Giant ants (`a`, orange) hunt in bands of three to five from floor 2. They are fast, bite
  weakly and have few hit points. An ant beside the character walks round to stand across from a
  nestmate, so a band ends up on every side.
* Violet jellies (`J`, lavender) appear alone from floor 3. A jelly that has noticed the character
  and is above half its hit points splits into a second jelly beside it every 40 turns, up to six
  jellies on a floor.
* Flanking. An attacker with another attacker across the target from it, diagonals included, adds
  2 to hit. It works the same whoever the target is. The character is told "You are flanked!" the
  first time it happens in a run, and a flanking blow reads "The giant ant bites you from behind".
* `--matchup` prints who beats whom and stops. Each kind of creature fights a character of each of
  five kits, one per depth, in an empty room. The tables give the win rate, the mean turns to a
  decision and the mean hit points the character lost. `--matchup-fights N` sets the fights in a
  cell, 2000 by default, and `--seed` names the stream they roll on. A kind added to the game gets
  a row without any other change.
* `R` rests turn after turn until the character is healed. It stops when their hit points are
  full, when a creature comes into sight, when they lose hit points, when a line is written to the
  message log, and on any key. It refuses to start when the character is already at full health or
  when a creature is in sight. A creature the character cannot see does not stop it until that
  creature does something they notice. Each turn of rest is a turn of the run, so everything else
  on the floor acts between one and the next.
* A turn spent standing still and a hit point regenerated are each reported as an event. Neither
  writes a line to the message log.
* A melee attack is a verb of its own. It names the square the blow is aimed at rather than a
  direction. A replay log records a step into a creature the character can see as a `melee` line
  rather than a `move` line, and a step into a creature they cannot see stays a `move` line.
  `Game#legal` offers one attack for each creature in sight within the weapon's reach, and leaves
  out the step into that creature. The keys are the same. A movement key into a creature still
  swings at it.
* `--replay-log PATH` writes every run the process plays to a file, as JSON Lines. The file holds
  the seed, the versions it was recorded under, one line per action, the fingerprint of the run
  every so many turns, and how the run ended. Each line is flushed as it is written, so a run that
  ends in a crash leaves a file that reads. `%s` in `PATH` is the character's name as a slug, `%d`
  is a number that rises until the name is free, and `%02d` pads it. A `PATH` that names a
  directory takes `<started_at>_<seed>_<player>.jsonl` inside it.
* `--replay-every N` sets how many turns there are between two fingerprints in a replay log. The
  default is 25.
* `crystal-roguelike replay view FILE` plays a recorded run back in the game's own interface.
  Space plays it and stops it, `l` and the right arrow perform one action, `h` and the left arrow
  take one action back, `g` goes to a turn, and `Q` leaves. `1` to `5` set the speed, from two
  seconds between actions to no pause at all, and `+` and `-` step the same ladder. `x` reads a
  square while the run stands still. A banner under the map holds the turn, the action number,
  whether the run is playing and the speed. Nothing is recorded and nothing is saved. A file whose
  fingerprints disagree with this build still plays, and the first disagreement is written to the
  message log.
* `crystal-roguelike replay export FILE...` writes out what a recorded run saw and what it did,
  as JSON Lines. One line per action holds the turn, the observation, the actions that were legal
  and the action that was taken. It is for learning a policy from runs somebody else played. The
  fingerprints are checked as the run is played again, so a file that no longer plays out the way
  it was recorded stops the export rather than producing pairs from a run nobody played.
  `--no-legal` leaves the legal actions out. `--output` names a file, and a name ending `.gz` is
  compressed, which is about forty times smaller.
* `crystal-roguelike replay upgrade SOURCE TARGET` writes a recorded run out again under this
  build's fingerprints. It is for a file this build refuses, which is one recorded before the
  message log came out of the fingerprint. The actions, the seed, the character, and the times the
  run started and ended all carry over, and the checkpoints stay on the turns they were on. The new
  file records what this build does with those actions, so what the build that recorded it did is
  no longer there to compare against. A file already at the target name stops the command.
* `crystal-roguelike replay verify FILE...` plays the runs in those files again and compares them
  against what was recorded. It names the turns a difference is between, and exits 1 when any file
  differs. It refuses a file recorded by a build whose draw sequences have since moved, and
  `--force` checks it anyway.
* An arrow, a thrown item and a bolt from a wand are drawn crossing the squares between. A missile
  moves three times as fast as the character walks.
* A hit point bar in the sidebar for the creature the character last traded blows with. It is red
  at full strength and shades to yellow as the creature falls, the other way round from the
  character's own bar. It names the creature by its species when the character can see it, and by
  the size of the shape when the creature is only an outline. A swing, a shot and a blow taken all
  raise it, whether they land or miss. It goes when the creature dies and after eight turns with no
  blow either way.
* Pointing at a row of the `Here` or `Seen` sections writes out what is on it. A creature gives its
  name, a sentence about it, its hit points and what it is doing; an item gives its whole name and
  what it does; a fixture and the terrain each give a sentence.
* A creature the character makes out only as a shape against light behind it reads as its size in
  its tooltip, as it already does in the `Seen` list and the `Look` readout. The tooltip says
  nothing about its species, its hit points or what it is doing.
* Clicking a square highlights the route to it. Clicking it again walks the route, one step at a
  time. The route crosses doorways and junctions without stopping, and stops for anything the
  character has not seen.
* `>` and `<` pressed away from a staircase highlight the remembered staircase and the route to it,
  and scroll the map to it. Neither costs a turn. The highlight clears when the `--More--` prompt
  is dismissed.
* The character regenerates hit points. Regeneration stops for ten turns after taking damage. The
  interval per point then comes from constitution: eight turns at 18, twenty at 10, thirty-two at
  3.
* Potion of haste. It speeds the drinker up for a while. Blessed it lasts
  twice as long, cursed half.
* Scroll of slow monster. Uncursed, it slows the targeted creature. Blessed, it slows every
  creature in sight. Cursed, it slows the reader.
* Scroll of haste monster. Uncursed, it hastes the targeted creature. Blessed, it hastes the
  reader. Cursed, it hastes every creature in sight.
* Scroll of repair. It mends one damaged carried item. Blessed, it mends everything carried, worn
  and lying underfoot. Cursed, it damages one item that was undamaged.
* Scroll of treasure detection, scroll of item detection, scroll of darkness, scroll of blindness
  and scroll of minor teleport.
* Blindness, for the character and for a creature. A blind character sees only their own square.
* `Ctrl+P` opens a scrollable pager over every message of the run. Arrows, `jk`, the page keys,
  space, `Home`, `End` and the wheel scroll it.
* The mouse wheel scrolls the message pane back over earlier lines.
* Ammunition matching the readied quiver is picked up on the step onto its square, with no turn of
  its own.
* Gold is picked up on the step onto its square, with no turn of its own.
* The title screen lists saved characters. Picking one resumes that run.
* Playing again after a run ends offers the name of the character that just finished.
* Clicking a menu row picks it, the same as typing the row's letter.
* The name prompt suggests a randomly generated name.
* Installation instructions in the README: the Homebrew tap, a release binary, or building from
  source.
* A `nightly` release, rebuilt from the head of the default branch on each night that anything was
  committed. It holds the same three platform tarballs as a tagged release, under names that do not
  change, so a download link goes on working. The release notes give the commit it was built from
  and the commits since the last nightly.
* The dungeon is five floors deep. The down staircase on each floor leads to the up staircase of
  the floor below, which is dug the first time the character reaches it. The up staircase leads
  back to the floor above, as it was left. Creatures stay on their own floor. A save file holds
  every floor visited.
* A small chamber under floor 5 holds an ancient amulet. Picking it up wins the run.
* The sidebar shows the depth beside the character's level, and the rule under the map names the
  floor.
* `--trial` reports the deepest floor each run reached, how many runs reached each floor, and how
  many runs did not die on floor 1. Its bot walks to a down staircase it remembers.
* Each species comes in kinds. Slimes are white, blue, red and green. A blue slime has more hit
  points and chills what it touches. A red slime scalds for more damage, and a green slime eats at
  its target for the most. Goblins are scouts, warriors and shamans. A scout is quick, carries a
  dagger, has poor armor and always appears alone. A shaman fights weakly and heals a hurt goblin
  beside it for 1d4 once every few turns. Orcs are orcs and orc archers. An archer has no bow yet.
* Every kind of a species shares its letter and has a colour of its own. The examine pane, the
  sidebar and the message log name the kind.
* Each kind has the depths it appears at. Red slimes and goblin warriors appear from floor 2, green
  slimes, goblin shamans and orcs from floor 3, and orc archers from floor 4. The weaker kinds
  thin out deeper down: goblin scouts stop after floor 2, white slimes after floor 3, and blue
  slimes and goblin warriors after floor 4.
* `a` drives an iron spike into a shut door beside the character. The spike holds the door shut
  against anything on the far side. Opening the door from the spiked side pulls the spike out and
  puts it back in the pack. A spiked door draws as `ǂ`, and the examine pane calls it a spiked
  door.
* `--trial-doors` plays `--trial` with a bot that shuts each door behind it. It combines with
  `--trial-cautious`.

### Changed

* A blow costs what the weapon says rather than one turn. A dagger takes 75 energy, a short sword
  100, a rapier 115, a long sword 120, and a mace or a spear 125. Bare hands take 80. A shot costs
  what the launcher says, 120 for a bow and 100 for a sling, and a throw costs what the thrown item
  says. A hit and a miss cost the same. An orc's swing takes 120 and a goblin's and a slime's take
  100. A recorded run that fought with a dagger, a long sword, a bow or an orc no longer verifies.
* An item's description gives its speed as a word and a number, such as `swing quick (75)` for a
  dagger and `swing slow (120)` for a long sword.
* `--trial` prints what the starting weapon hits for in a blow and in every hundred energy.
* A creature whose way to the character is taken by another creature steps to a square the same
  distance off rather than waiting, so members of a group come at the character from several sides
  instead of queuing behind each other. One that has waited on another for two turns in a row
  treats that creature's square as solid for the next twenty turns and walks round it by another
  route when there is one.
* Floor 1 holds white and blue slimes and goblin scouts only. Orcs appear from floor 3 and grow
  commoner from floor 4, where orc archers join them. Deeper floors hold more creatures.
* Better kinds wait for deeper floors, on the ground and in a monster's hands. A long sword, a
  rapier, a spear, a shield, a wand, a potion of haste and a scroll of blessing appear from the
  second floor down. Chain mail, a wand of striking and a scroll of haste monster appear from the
  third. Nothing on floors 1 and 2 is better than +1, and nothing on floors 3 and 4 is better than
  +2.
* A save written before there were several floors loads as floor 1 of its run.
* The character starts with a potion of healing, and knows what it is.
* `replay export` writes format 2. Each observation carries the depth of the floor the character
  is on, and leaves it out on a floor outside the dungeon's numbering. An observation without it
  reads back with no depth.
* Climbing up from floor 2 or deeper asks nothing. Climbing up from floor 1 still asks before the
  character leaves the dungeon.
* A creature placed on a generated floor rolls its hit points from its kind's hit dice. It
  used to start with a fixed number.
* The creatures in one room belong to one band and are one species. Waking one wakes the others.
* A goblin warrior always carries a short sword and a goblin scout a dagger. A kind's chance of
  carrying a lit torch or candle is its own.
* An orc is drawn in a brighter red, so it stands out further from the ground.
* A save written before kinds existed loads each creature as its species' original kind.
* Goblins and orcs of every kind open shut doors. Walking into one opens it and takes the
  creature's turn, and it steps through on the next. A band of them paths through doors it
  remembers as shut. Slimes do not open doors. A creature that finds a door spiked against it
  stops trying that door. The character is told when they see a door opened.
* A fingerprint is worked out about a third faster. `replay verify` on a five thousand action run
  takes 9.8 seconds where it took 11.5. The value is the same one, so a run recorded by an earlier
  build of this format still verifies.
* The game works a field of view out once per turn rather than about twice, and holds the answer
  while nothing it reads has moved. Playing a recorded run back, checking one and driving the game
  from a bot are each about twice as fast. What the game does is unchanged, and a recorded run
  verifies to the same fingerprints.
* The fingerprint of a run leaves the message log out. A save still holds the log, and a person who
  comes back to a run reads their last lines. `replay verify` no longer reports a difference for a
  line the game wrote outside an action, such as the one `G` writes when it asks which way to run.
  A replay log is now format 2. `replay verify` refuses a format 1 file and says that its
  fingerprints cover the message log, which this build leaves out. `--force` does not check one
  anyway, because every checkpoint in it differs.
* A rest runs several turns between one repaint and the next. The first turns are drawn one at a
  time, the middle of a rest goes by in batches, and the batches shrink again as the hit points
  fill up. A rest of 220 turns took 5.1 seconds and now takes 1.5. A key still stops the rest, and
  it is read between one batch and the next.
* Every British spelling is now the American spelling. The item is "leather armor". A save file
  written by an earlier build no longer loads, because a save holds the old field names and the
  old enum names.
* In a list of items the blessing is a mark beside the key instead of a word in the name. The marks
  are `✦` blessed, `✘` cursed, `✓` uncursed, and nothing while the blessing is not worked out. The
  slot an item is readied in is a mark against the right edge: `⚔` in the hand, `➶` the ranged
  weapon, `➷` the quiver, `⛊` worn. `⁕` marks a light source that is burning. The count or the
  article are in their own field. The names line up. The tooltip on a row gives each mark and the
  word for it. Its first line names the item without the blessing word.
* The highlighted row of a menu has `⟪` at its near edge and `⟫` at its far edge. The highlight
  covers the name. It no longer covers the key and the mark beside it. The same two marks are used
  on the row of the `Here` or `Seen` list under the pointer.
* A scroll nobody has read is "a scroll YLOH" rather than "a scroll labeled YLOH".
* The character starts knowing their own kit is uncursed. The short sword, the leather armor, the
  torch and the spikes are uncursed from the first turn. None of them waits on a handling roll.
* No message is written when an item is discovered to be uncursed. Only a blessing or a curse is
  written to the log. The pack still moves the item to a letter of its own, which shows it has been
  worked out.
* A name too long for the `Here` or `Seen` column is cut at the edge and marked with an ellipsis,
  the same as every other row of the sidebar.
* Time runs on ticks. Every actor gains energy each tick and every action
  costs energy, so an actor can be faster or slower than another.
* The speeds of creatures relative to the character are 80% for the slime, 95% for the orc, and
  100% for the goblin.
* Putting a suit of body armor on, or taking it off, takes three turns.
  Every other action takes one.
* A scroll of magic mapping reveals walls only. Room and corridor floors stay unknown until the
  character walks them.
* A blessed weapon adds 1 to hit. Damage is unchanged.
* Messages agree in number: "3 iron spikes are not cursed", "1 iron spike is cursed".
* Linux release binaries are stripped, which takes about a megabyte off each.
* The build records the commit it was built from. `script/build-id` answers it while the compiler
  runs, and a build with no repository to ask records `unknown` rather than failing.
* A run no longer stops for an item that was already drawn on the character's map. It still stops
  for one that was not.
* `G` and a walked route are drawn one step at a time, at about the rate of a held movement key,
  rather than all at once. Any key stops a walk in progress and does nothing else.
* An item lying more than eight squares off is named by its kind in the `Look` readout and the
  `Seen` list: "a spear" rather than "a cursed -2 spear", "a scroll" rather than "a scroll YLOH",
  "a potion" rather than "a swirly potion". Walking within eight squares of it names it in
  full from then on.

### Fixed

* `replay upgrade` keeps the checkpoint spacing a file was recorded with when an action of several
  turns ran past a checkpoint. It took the shorter gap after that checkpoint as the spacing.
* A build of the game as another shard's dependency records the game's own commit, which
  `lib/.shards.info` names. It recorded the other shard's commit.
* A replay file recorded on a seed above `Int64::MAX` reads. `Rng` rolls a `UInt64`, so about half
  of all runs are on one. `crystal-roguelike replay verify`, `replay view` and `replay upgrade`
  each reported `line 1 is not JSON` for such a file and would not open it.
* Carrying a saved character on no longer pages through their whole message history before showing
  where they are. The log comes back whole and counts as read.
* Healing a character who is above their maximum hit points no longer reduces them to their
  maximum.
* The oval a scroll of item detection reaches was twice the stated size. The span is the width of
  the oval, not its radius.
* A walk no longer stops on an item the character saw earlier in the same walk. It stops on an item
  they have not seen.
* A walk stopped on the first of two identical items and not on the second. It now stops on both.
* A walk in a run of more than two hundred messages stopped on every item it crossed, including
  items the character had already walked over. It stops only on an item they have not seen.
* A route now crosses a door the character remembers, open or shut. A walk along a route opens a
  shut door and carries on, spending a turn on it. A square behind a door the character remembers
  as shut can be picked with the mouse, and so can the door itself. A walk in one direction still
  stops in front of a shut door, and a band of monsters still treats one as a wall.

## [0.1.0] - 2026-09-19

First release. A seeded roguelike played in the terminal, built over 26 phases recorded in
`IMPLEMENTATION.md`.

### Added

* **The floor.** Rooms, corridors, doors and staircases, either generated by binary space partition
  or read from a hand-built map file. Every open square is reachable from the up staircase.
* **Movement.** `hjkl` and `yubn`, `G` to run until something stops the run, `.` to wait, `o` and
  `c` for doors, `<` and `>` for staircases.
* **Sight and light.** Symmetric shadowcasting for the field of view. Torches, candles, wall
  sconces, magically lit rooms and a floor-wide ambient level. A square is seen when it is in the
  field of view and lit. Remembered terrain is drawn dimmer than lit terrain, and a creature on an
  unlit square with light behind it is drawn as a silhouette. Flames flicker, and `--no-flicker`
  disables the animation.
* **Items.** Twenty-five kinds: weapons, ranged weapons and ammunition, thrown weapons, armor,
  potions, scrolls, wands, light sources, iron spikes and gold. Each carries an enchantment, a
  condition and a blessing. Potions, scrolls and wands are disguised until found out. Items are
  carried under a letter, dropped, picked up and scattered on the floor.
* **Blessings and curses.** Hidden per item. Carrying an item long enough reveals its blessed or
  cursed status. A scroll of identify names one kind, a scroll of blessing and a scroll of remove
  curse mark what they find. A cursed item cannot be removed from its slot, and zapping a cursed
  wand welds it into a free hand slot and returns whatever was readied there to the pack.
* **Equipment.** Eight slots: melee, ranged, quiver, head, body, hands, feet and shield. `w`, `W`
  and `T` ready, wear and remove.
* **Combat.** Melee by walking into a creature, ranged with `f`, thrown with `t`, aimed with a
  targeting cursor. One twenty sided die against ten plus armor class.
* **The character.** Five attributes, hit points, experience and levels.
* **Monsters.** Slimes, goblins and orcs, each with their own notice range, stealth, darkvision,
  persistence and clumsiness. They belong to bands, hold their own belief about the floor, path
  toward where they last saw the character, and give up after long enough.
* **Consumables.** `q` drinks, `r` reads, `z` zaps. A potion of healing, scrolls of identify and
  magic mapping, and wands of light and striking.
* **Saved characters.** One JSON file each under the state directory. A finished run moves to the
  deaths or wins directory and frees its name.
* **The screen.** A map pane, a sidebar holding the character block, what is nearby and what is
  under the pointer, and a message log that pauses at each page with `--More--`. Tooltips on the
  sidebar and on menu rows. Mouse hover and a keyboard examine cursor, with `M` to turn mouse
  reporting off.
* **Start, death and victory screens**, each naming the seed.
* **Tooling.** `--seed` reproduces a run, `--trial N` plays N games with a bot for tuning,
  `--debug-console` opens a console for commands that change the running game, and a tag builds
  binaries for linux-x86_64, linux-aarch64 and macos-aarch64.

[Unreleased]: https://github.com/plambert/crystal-roguelike.cr/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/plambert/crystal-roguelike.cr/releases/tag/v0.1.0
