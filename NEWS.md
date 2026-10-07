# News

What changed in each release, for the people playing it. The full record, including build and
packaging changes, is in [CHANGELOG.md](CHANGELOG.md).

## [0.4.0] - 2026-10-07

Exploring gathers gold and ammunition on the way and stops only for things you have not seen, and
the down staircase is a long walk from the up staircase.

### New

* `v` walks you to the items exploring last stopped for, the nearest first.
* An empty quiver remembers what it held, so walking over your spent arrows or stones refills it.

### Changed

* Exploring picks up gold and quiver ammunition without stopping, and stops only for new items.
* The down staircase sits far from the up staircase, so a floor is no longer over in a few steps.
* You see every arrow, stone and bolt cross the floor, yours and the monsters', before the hit.

### Fixed

* A flood of messages holds at More until you have read them all, and the log keeps far more.

## [0.3.0] - 2026-10-05

The game runs on Windows, in WezTerm and Windows Terminal.

* Take the `windows-x86_64` zip from the release page. There is one for the regular build and one
  for the test build.

## [0.2.5] - 2026-10-05

The sidebar shows the whole turn count and fits a short terminal, and the help screen scrolls.

* The turn count in the sidebar is never cut short, and the gold is labeled.
* The help screen scrolls on the arrow keys, the page keys, Home, End and Space.
* On a short terminal the equipment and the pack scroll under the mouse wheel instead of vanishing.
* Clicking Pack on a short terminal opens the pack. Before, it turned the arrow and showed nothing.

## [0.2.4] - 2026-10-04

Replay uploads and the update check work on a Mac without Homebrew, `X` explores, `_` travels,
and the first floor is kinder.

### New

* `X` explores. You walk toward the nearest square you have not seen, opening doors on the way.
* Exploring stops when a creature appears, you are hurt or you step onto something, and says why.
* `_` puts a cursor on the map. Enter walks you there, and the way is lit as the cursor moves.
* A second click on a square walks you there too, and the walk says why it stopped.

### Fixed

* Sending replay logs and checking for a newer release work on a Mac without Homebrew.

### Changed

* Goblin scouts are rarer on the first floor and carry fewer stones for their slings.

## [0.2.3] - 2026-10-04

The game needs 256 colors, aiming offers only clear shots, routes walk straighter, and this
turn's messages stand out.

### New

* The help screen shows the run's seed and draws the eight movement keys around your character.
* This turn's messages are bright yellow in the message pane. Earlier turns stay the plain color.

### Changed

* The game needs a 256-color terminal. It says what it found when it refuses to start.
* Aiming offers only monsters your shot can reach. Tab skips one behind a wall or another creature.
* A walked route goes straight when it can and bends once at an obstacle instead of zigzagging.
* Pressing `f` or `t` a second time while aiming cancels the shot, the same as Escape.

## [0.2.2] - 2026-10-03

The game tells you when a newer release is out, and a test build can send its replay logs to the
developer.

* Before and after a run, the game says when a newer release is out and where to get it.
* `--no-update-check` keeps the game from asking GitHub about releases.
* `--autosubmit` sends each run's replay log to the developer when the game exits. A test build
  has it on.
* The first run with it on shows what would be sent and asks yes or no before sending anything.
* `--no-autosubmit` turns it off for a run.

## [0.2.1] - 2026-10-02

Starting the game with no arguments works again.

* `crystal-roguelike` with no arguments starts a game. 0.2.0 printed the help and stopped.

## [0.2.0] - 2026-10-02

The dungeon is five floors deep, floors vary in size and shape, and the monsters have kinds,
factions and tactics.

* Five floors, with an amulet under the fifth. Picking it up wins the run.
* Floors vary in size and layout: trees of rooms, grids full of loops, and natural caves.
* Each species comes in kinds, giant ants and violet jellies join deeper down, and factions fight.
* Monsters shoot, flee when hurt, open doors, flank you, and pick up better weapons and armor.
* Time runs on ticks, so a dagger swings faster than a long sword and slimes are slower than you.
* `R` rests until you are healed, and there are new potions and scrolls, from haste to teleport.
