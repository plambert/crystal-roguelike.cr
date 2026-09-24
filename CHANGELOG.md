# Changelog

All notable changes to this project are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The version is written in `shard.yml`,
and a tag of the form `vX.Y.Z` builds and publishes a release.

## [Unreleased]

### Added

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

### Changed

* In a list of items the blessing is a mark beside the key instead of a word in the name. The marks
  are `✦` blessed, `✘` cursed, `✓` uncursed, and nothing while the blessing is not worked out. The
  slot an item is readied in is a mark against the right edge: `⚔` in the hand, `➶` the ranged
  weapon, `➷` the quiver, `⛊` worn. `⁕` marks a light source that is burning. The count or the
  article are in their own field. The names line up. The tooltip on a row gives each mark and the
  word for it. Its first line names the item without the blessing word.
* The highlighted row of a menu has `⟪` at its near edge and `⟫` at its far edge. The highlight
  covers the name. It no longer covers the key and the mark beside it. The same two marks are used
  on the row of the `Here` or `Seen` list under the pointer.
* A scroll nobody has read is "a scroll YLOH" rather than "a scroll labelled YLOH".
* The character starts knowing their own kit is uncursed. The short sword, the leather armour, the
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
* Putting a suit of body armour on, or taking it off, takes three turns.
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

* Carrying a saved character on no longer pages through their whole message history before showing
  where they are. The log comes back whole and counts as read.
* Healing a character who is above their maximum hit points no longer reduces them to their
  maximum.
* The oval a scroll of item detection reaches was twice the stated size. The span is the width of
  the oval, not its radius.

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
* **Items.** Twenty-five kinds: weapons, ranged weapons and ammunition, thrown weapons, armour,
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
  targeting cursor. One twenty sided die against ten plus armour class.
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
