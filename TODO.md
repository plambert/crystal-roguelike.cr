# To do

What has been asked for and where it stands. An item moves from Considered to Unplanned when it is
decided, from Unplanned to Planned when it is next up, and to Completed when it has shipped. Each
item says what a player would notice, not how it is built.

## Planned

### Stairs down land far from the arrival

The two staircases are drawn from any two different rooms, so they are often neighbours and a
floor is over in a few steps. Instead the down staircase is drawn from the rooms at least half the
floor's longest walking distance from the up staircase, measured by route rather than straight
line, falling back to the farthest room on a floor too small for that. The staircases draw from
their own stream, so an existing seed keeps its rooms, monsters and items and only the stairs
move, and only on floors that fail the rule today. The replay golden fixture is re-recorded if its
floor changes.

### One key wields and wears, and swaps armor by itself

`w` and `W` become one key that wields a weapon or wears armor by what the chosen item is. When
the item's slot is already full, the game takes the old piece off and then puts the new one on,
as two actions over the turns they take. A creature moving into view or damage taken interrupts
the swap after the first action, leaving the character with the old piece off and the new one
still in the pack. The message pane then ends the turn with a line such as "You are interrupted,
and have not put on the chain mail yet!", written last so it is the one the player reads.

### Explore does not stop for torches

A torch coming into sight stops an explore the way any new item does, and torches are common
enough that the walk stops for them again and again. Torches join gold in the list of items that
do not stop the walk.

### An options screen, and a pickup filter

Somewhere for preferences to live. One is what to pick up without being asked, as an ordered list
of rules such as "gold only", "never a cursed item", or "anything better than what I have".
Another is whether a bar's colour comes from the gradient or from fixed bands.

### An action menu on an inventory letter

Pressing an item's letter in the pack opens a fixed menu of what can be done with it, with entries
that do not apply dimmed rather than missing, so the same key is in the same place every time.
The inventory list itself gets a filter along its top, "all", "weapons", "armor", "potions",
"scrolls" and so on, which the left and right arrows move between, so a long pack can be read one
class at a time.

### A modern control configuration

A second control scheme, called modern, beside the classic one, chosen in the options. Movement is
on `wasd`, with `q` and `e` for north-west and north-east and `z` and `x` for south-west and
south-east. One action key, `r`, opens a menu of everything that can be done, such as wield, wear
and take off, read, drink and throw, each with its own memorable key. `f` guesses the action from
what is around: it opens or closes the door the character faces and lights or puts out the torch
beside them, and opens the action menu when more than one thing could be meant. In menus the
selection moves with `wasd` rather than by single-letter choices. It is a different way to drive
the same actions, and the help screen shows whichever scheme is in use.

### A what's new screen

The changes a player would notice since the version they last ran, reachable from the title screen
and printable with `--whats-new`. It draws on the changelog, so a release that adds a feature
tells the player about it without them reading the release page.

### A tutorial for new players

A guided first run that introduces moving, fighting, picking things up, the pack, doors, stairs
and saving, one at a time, with the game pausing to explain each when it first matters. It is
reachable from the title screen and never shown unasked after the first time.

### Spells

A mana pool that comes back over time, two starting spells to choose between at creation, and
spellbooks found on the floor that each teach one more. The first two spells are a lock that holds
a door shut for a while and a blinding that stops a creature seeing for a few turns.

### Sound and noise

Fighting, breaking, shouting and some spells make noise that wakes and draws creatures within a
range, and a quiet player goes unnoticed for longer. Creatures calling out to each other has an
effect only once this exists.

### Band communication and languages

Today every band shares what any member sees, at any range. Instead, only insects with a queen
share like that. Other creatures share with band members who speak a common language and are
within range or were seen recently, and call out to the rest. Languages are per creature, with
properties such as silent, sight-based or sound-based, and a clever goblin might speak Orc.

### Right-click and drag on the map to pan

Holding the right mouse button on the map and dragging moves the view with the pointer, so a player
can look at a part of the floor the character is not near without moving them. Letting go leaves
the view where it was dragged, and the next action, or the camera key, brings it back to the
character.

## Considered

### Sorting the pack

A key re-letters the pack in a chosen order, and the order is kept in the save so later pickups slot
in where they belong. Four orders. Alphabetically by name. By type, then alphabetically within the
type. By value, once items have values. By rarity, which for now is the highest enchantment first,
with a blessed item counting one higher and a cursed one lower; later it can be worked out at
compile time from the loot tables as the median floor an item first appears on, adjusted the same
way for enchantment and blessing. Readied items keep their slots, only their letters change, and the
message pane says the pack was sorted.

### The Seen list

Hovering a row with the mouse lights that creature's square on the map, and the list is sorted by
how far each creature is from the character.

### The rest of the route on the map

A drawn route fades after a few seconds without movement or another click, rather than waiting for
a turn. Clicking a row of the Seen list draws a route to that creature.

### `replay dump`

A replay command that writes the messages of a run, so the messages of two builds over one run can
be set side by side.

### A minimap

A corner of the screen shows the whole floor at four by two squares per cell, or as an image where
the terminal draws them.

### Smoother bars

Where the terminal draws images, the health and other bars move by a pixel rather than a cell.

### A bot that plays well enough to trust

The trial bots shut doors and back away when hurt, but neither spikes a door or decides whether a
fight is worth having, so what the trials measure is still narrow.

### Armor weight slows the character

Heavier armor makes movement slower, and the heaviest armor slows attacks as well. A shield slows
attacks somewhat too. The gain in armor class then costs something a player can feel, and leather
armor is a choice rather than a stop on the way to chain mail.

### A progress bar for uploads

A game that submits its replay sends it at exit, after the terminal is handed back, and says
nothing while the upload runs. A bar on the console would show how much of each piece has gone, so
a slow connection reads as progress rather than a hang.

### Where the game is drifting

Light, stealth, detection range and shutting doors move survival most, which pulls play toward
stealth. Whether that is wanted should be looked at again once creatures do more than walk at the
character and swing.

## Completed

### Explore walks to gold it sees

`X` walks to gold the character can see or remembers before the next unseen square, nearest pile
first, picks it up and carries on in the same walk. Gold found gone on arrival is forgotten, gold
out of reach is passed over, and `_` does not turn aside for gold.

### The quiver remembers its ammunition

Firing or throwing the last arrow or stone leaves the quiver remembering what it held, and the
memory is kept in the save. Walking over matching ammunition, or picking it up with `,`, puts it
back in the quiver. The equipment panel shows the empty quiver dimmed as "no stones", and keeps the
row when a short screen hides the empty slots. Wielding another kind or taking the quiver off with
`T` forgets it.

### Windows support

The game builds and runs on Windows, in WezTerm and Windows Terminal, and every release carries a
Windows zip. Saves and state live where Windows keeps them, and the specs run on Windows in CI.
Anything that runs an external command is compiled out on Windows, so a Windows build has no
process chain in `--dump-terminal-info`.

### Explore picks up gold and stops for new items only

`X` and `_` pick up gold they walk over and walk over other items without stopping. They stop when
an item the character has not seen before comes into sight, and say what it is, such as "A pink
potion and a long sword come into sight". Items already seen, on the floor or in the pack, are
ignored, so a floor already walked explores in one go.

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

### Do not shoot missiles into walls

Aiming a shot or a throw offers only monsters the missile can reach, and `Tab` skips the rest. The
cursor stays on the character with a note when nothing can be reached, and can still be moved onto
a covered monster by hand.

### Paths look natural

A route to a square in view runs along the straight line to it, and a route around something bends
once and runs straight after. Routes are the same length as before and no rule changed.

### Highlight the current turn's messages

Messages from the current round are drawn bright, and earlier ones in the usual colour, so what just
happened stands apart from history.

### The targeting key aborts targeting

A second `f` or `t` while the target picker is up closes it with no shot and no turn, the same as
Escape.

### `X` for explore

`X` walks toward the nearest unseen square and sweeps a room before leaving it, stopping and saying
why when a creature appears, the character is hurt, they step onto something, or nothing is left to
see. `_` picks a square to travel to. Both are recorded as actions, and knowledge is cut into
chambers.

### Balance of the first floor

Goblin scouts are one creature in seven on the first floor instead of one in three, and carry
1d4+1 stones. Over 200 bot runs deaths fell from 43% to 24% and leaving floor 1 alive rose from
64% to 83%. Deeper floors are unchanged.

### The seed on the help screen

`?` shows the run's seed and a diagram of the eight movement keys with arrows.

### Missiles fly before they land

A shot, a thrown item, a bolt from a wand and a creature's arrow or stone are seen crossing the
floor before the hit, the damage and the message appear. The map, the bars and the log show the
result once the missile has landed, and the death screen waits for it. A creature's shot was not
drawn before.
