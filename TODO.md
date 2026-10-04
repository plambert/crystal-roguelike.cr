# To do

What has been asked for and where it stands. An item moves from Considered to Unplanned when it is
decided, from Unplanned to Planned when it is next up, and to Completed when it has shipped. Each
item says what a player would notice, not how it is built.

## Planned

### Windows support

The game builds and runs on Windows in a terminal that speaks the usual escape sequences. Work is
under way. Anything that runs an external command is compiled out on Windows until a Windows way
of doing it exists, so a Windows build has no process chain in `--dump-terminal-info` yet.

### `X` for explore

`X` walks the character toward the nearest square they have not seen, over ground they know, and
sweeps a room before leaving it. The lower-case `x` stays the examine key. It stops when a creature
comes into view, when the character is hurt, when they step on an item, or when nothing on the
floor is left to see, and says which. A travel command to a chosen square goes with it, so clicking
a square and typing a target reach the same place.

### Do not shoot missiles into walls

When a ranged or thrown weapon is readied, the target offered first is one the missile can reach.
A creature behind a wall, a door, or another creature is never auto-selected, because the shot
would hit what is in the way. The player can still pick such a target by hand and take the result.

### The targeting key aborts targeting

After `t` or `f` opens the target picker, pressing the same key again closes it without a shot,
the same as Escape. A player who reaches for the key out of habit is not left wondering how to back
out.

### Highlight the current turn's messages

Messages written this turn are drawn in a colour of their own, and messages from earlier turns in
the usual one. A player reading the log sees at a glance what just happened and what is history,
without counting lines or waiting for the pane to scroll.

## Unplanned

### A tutorial for new players

A guided first run that introduces moving, fighting, picking things up, the pack, doors, stairs
and saving, one at a time, with the game pausing to explain each when it first matters. It is
reachable from the title screen and never shown unasked after the first time.

### A what's new screen

The changes a player would notice since the version they last ran, reachable from the title screen
and printable with `--whats-new`. It draws on the changelog, so a release that adds a feature
tells the player about it without them reading the release page.

### Spells

A mana pool that comes back over time, two starting spells to choose between at creation, and
spellbooks found on the floor that each teach one more. The first two spells are a lock that holds
a door shut for a while and a blinding that stops a creature seeing for a few turns.

### Sound and noise

Fighting, breaking, shouting and some spells make noise that wakes and draws creatures within a
range, and a quiet player goes unnoticed for longer. Creatures calling out to each other has an
effect only once this exists.

### An action menu on an inventory letter

Pressing an item's letter in the pack opens a fixed menu of what can be done with it, with entries
that do not apply dimmed rather than missing, so the same key is in the same place every time.

### A modern control configuration

A second control scheme, called modern, beside the classic one, chosen in the options. Movement is
on `wasd`, with `q` and `e` for north-west and north-east and `z` and `x` for south-west and
south-east. One action key, `r`, opens a menu of everything that can be done, such as wield, wear
and take off, read, drink and throw, each with its own memorable key. `f` guesses the action from
what is around: it opens or closes the door the character faces and lights or puts out the torch
beside them, and opens the action menu when more than one thing could be meant. In menus the
selection moves with `wasd` rather than by single-letter choices. It is a different way to drive
the same actions, and the help screen shows whichever scheme is in use.

### Right-click and drag on the map to pan

Holding the right mouse button on the map and dragging moves the view with the pointer, so a player
can look at a part of the floor the character is not near without moving them. Letting go leaves
the view where it was dragged, and the next action, or the camera key, brings it back to the
character.

### Band communication and languages

Today every band shares what any member sees, at any range. Instead, only insects with a queen
share like that. Other creatures share with band members who speak a common language and are
within range or were seen recently, and call out to the rest. Languages are per creature, with
properties such as silent, sight-based or sound-based, and a clever goblin might speak Orc.

## Considered

### Balance of the first floor

Goblin scouts cause most early deaths. Their stones, their speed, how often they appear on floor
1, and the starting potion are the levers. A pass over them with the matchup table and the trial
bot would settle where the first floor should sit.

### The Seen list

Hovering a row with the mouse lights that creature's square on the map, and the list is sorted by
how far each creature is from the character.

### An options screen, and a pickup filter

Somewhere for preferences to live. One is what to pick up without being asked, as an ordered list
of rules such as "gold only", "never a cursed item", or "anything better than what I have".
Another is whether a bar's colour comes from the gradient or from fixed bands.

### The rest of the route on the map

A drawn route fades after a few seconds without movement or another click, rather than waiting for
a turn. Clicking a row of the Seen list draws a route to that creature.

### A minimap

A corner of the screen shows the whole floor at four by two squares per cell, or as an image where
the terminal draws them.

### Smoother bars

Where the terminal draws images, the health and other bars move by a pixel rather than a cell.

### A bot that plays well enough to trust

The trial bots shut doors and back away when hurt, but neither spikes a door or decides whether a
fight is worth having, so what the trials measure is still narrow.

### `replay dump`

A replay command that writes the messages of a run, so the messages of two builds over one run can
be set side by side.

### Where the game is drifting

Light, stealth, detection range and shutting doors move survival most, which pulls play toward
stealth. Whether that is wanted should be looked at again once creatures do more than walk at the
character and swing.

## Completed

### Five floors and the amulet

The dungeon has five floors with a sixth holding The Mighty Amulet of MacGuffin, deeper floors
spawn more and tougher creatures, and the staircases do not line up between floors.

### Floors of varied size and shape

A floor is anywhere from a quarter to four times the usual area, square or long, and is dug as a
tree of rooms, a looped grid, a cave, or a mix, sometimes mirrored. Wall-following fails on some
floors.

### Creature variety, factions and gear

Each species has variants that appear at different depths. Creatures belong to factions that fight
each other, shoot slings and bows, flee when hurt and regain health, open doors, and pick up and
wear gear better than their own. Ants swarm with flanking and jellies split.

### Doors and spikes

Doors can be shut and spiked, and a band treats a shut door as a wall until something opens it.

### Weapon speed

Actions cost different amounts of time by weapon and by creature, so a dagger strikes more often
than a great axe.

### Smarter pathing

Creatures route around each other and take detours rather than queueing in a corridor.

### A matchup table

`--matchup` prints how each kind of creature fares against a character of each of five kits.

### The minor healing potion

A potion of minor healing that the character starts with, common on the first floor and rare
after.

### Small fixes

The viewport follows a teleport and a floor change, a fight with several archers no longer
scrolls messages past without `--More--`, stacks recombine when an item becomes known, and a bare
`crystal-roguelike` starts a game.

### Test builds and releases

A test build records every run, is built statically for macOS and Linux beside each release and
nightly, and the release page carries the version's changelog entry.

### Replay submission

With agreement given once, each run's replay log and save are sent to the developer when the game
exits, and anything that could not be sent goes out next time. The replay commands read the
gzipped logs that arrive.

### The update check

The game says when a newer release is out and where to get it, asking GitHub at most once a day.

### The colour requirement and the terminal report

The game requires 256 colours and refuses to draw without them, saying what it found.
`--dump-terminal-info` prints one line of JSON about the terminal for a bug report.

### The seed on the help screen

`?` shows the run's seed and a diagram of the eight movement keys with arrows.
