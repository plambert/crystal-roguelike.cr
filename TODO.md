# To do

What has been asked for and where it stands. An item moves from Considered to Planned when it is
next up, to Unplanned when it is decided against, and to Completed when it has shipped. Each
item says what a player would notice, not how it is built.

## Planned

### Enchantments are learned over time, and only partly at first

An item's enchantment is hidden when it is picked up and comes out in steps as the character uses
it, the way blessings are learned by handling today. Each step says what is known so far. "You
realize that your dagger (z) is at least +1!" shows the item as "+1? dagger"; later "at least +2"
shows "+2? dagger"; and "You realize that your dagger is exactly +2." drops the mark. What is known
can also be relative, such as "You realize that your dagger (z) is better than your +1 dagger
(c)!", which lifts the lower bound. A scroll of identify learns it outright. How the steps are
timed, and what a negative enchantment reveals as, is to be settled when this is built.

### An options screen, and a pickup filter

Somewhere for preferences to live. One is what to pick up without being asked, as an ordered list
of rules such as "gold only", "never a cursed item", or "anything better than what I have".
Another is whether a bar's colour comes from the gradient or from fixed bands.

### A modern control configuration

A second control scheme, called modern, beside the classic one, chosen in the options. Movement is
on `wasd`, with `q` and `e` for north-west and north-east and `z` and `x` for south-west and
south-east. One action key, `r`, opens a menu of everything that can be done, such as wield, wear
and take off, read, drink and throw, each with its own memorable key. `f` guesses the action from
what is around: it opens or closes the door the character faces and lights or puts out the torch
beside them, and opens the action menu when more than one thing could be meant. In menus the
selection moves with `wasd` rather than by single-letter choices. It is a different way to drive
the same actions, and the help screen shows whichever scheme is in use.

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

The list is sorted by how far each creature is from the character.

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

### A safety map for fleeing creatures

A way for fleeing creatures to choose where to run, in case the escape-first rule needs tuning or
costs too much. Take the band's distance map from the character, negate it, scale it by about 1.2,
and relax it once so that no square is more than one above its best neighbor. A fleeing creature
then rolls downhill on that map. The relaxation carries the value of a long corridor back through
its door. A door nearer the character than a corner still pulls the creature toward it, because
what lies past the door is farther away than the corner. This takes two passes over the floor per
fleeing band per turn, with no second flood per creature, and the darkness and band tie-breakers
still settle equal squares. The cost is a tuning constant with no exact meaning, and decisions that
are harder to explain in a spec. Brogue's monster flight works this way.

### Mining

The character can dig through walls. Any weapon can do it, but badly, and a pickaxe does it far
better. Each kind of wall takes a different amount of damage to destroy, so soft rock gives way in a
few blows and the hardest stone takes a long time. Now and then a dig runs into a gold ore vein,
which is rare. A vein yields gold ore, an item of its own that is not gold and does not stack.

### Hunger, food and corpses

The character gets hungry as turns pass and must eat to avoid starving. Food is found on the floor
as rations and other things to eat. A creature the character kills leaves a corpse, and a corpse
can be eaten too. How fast hunger builds, what each food restores, how long a corpse lasts, and
whether some corpses are bad to eat are to be settled when this is built.

### Thirst, fountains and waterskins

The character gets thirsty as turns pass and must drink. Fountains on some floors give water to
drink on the spot. A waterskin holds water to carry away and drink later, and a fountain refills it.
How fast thirst builds, how much a waterskin holds, and whether fountain water is always safe are to
be settled when this is built.

### Where the game is drifting

Light, stealth, detection range and shutting doors move survival most, which pulls play toward
stealth. Whether that is wanted should be looked at again once creatures do more than walk at the
character and swing.

## Unplanned

Nothing is here yet. This section records items we decided not to follow up on, so the decision
is not made twice.

## Completed

### `replay dump`

`replay dump` writes the messages of a recorded run, one per line with the turn it came on.
Dumping one replay with two builds and comparing the files shows a change of wording that
`replay verify` cannot see. It stops with a report where the run differs from the recording.
`--output` names a file, and standard output is the default.

### A progress line for uploads

A replay upload shows a line on standard error for each file it sends, with the file's name, the
bytes sent of the total, and a bar. On a terminal the line redraws in place. When standard error is
a file or a pipe, each file gets one line.

### A what's new screen

The title screen has a "what's new" entry that shows the release notes for the versions newer than
the one last run, or the newest release when there is nothing newer. `--whats-new` prints the same
notes and stops. The game keeps the last version run in the state directory, and `--no-save` leaves
it alone.

### An action menu on an inventory letter

Pressing an item's letter in the inventory lists what can be done with it: wield or wear, take off,
drink, read, zap, apply, throw and drop. The list is always in that order with the same keys as on
the map, and entries that do not apply are dimmed. Clicking an item in the sidebar's pack opens the
same list. The inventory shows one class of item at a time, such as weapons, armor, potions or
scrolls, and the left and right arrows move between classes. The first class shows everything, and
each item keeps its letter.

### Routes fade, and the Seen list points and walks

A route drawn by clicking the map or the Seen list fades after four seconds with no move and no
other click, and a second click on the same square within that time still walks it. Pointing at a
creature or an item in the Seen list lights its square on the map, blinking about twice a second,
or steady with `--no-flicker`. Clicking a row draws the way to it, and a second click walks it.

### Explore clears the small side first

`X` looks into a dead end or a small pocket beside it before it walks on into open ground, so the
pocket is not left to walk back to at the end of the floor. A pocket counts as small when
everything around it has been seen. `X` also no longer stops in a doorway or the neck of a cave
while the room beside it still has ground left to see.

### Explore commits to a passage once it enters one

Once `X` steps into a corridor, it follows that corridor to its end before it goes back for another
exit. It no longer opens a door, looks into the corridor, and turns around.

### One key wields and wears, and swaps armor by itself

`w` wields a weapon or wears armor, by what is chosen, and `W` does the same and is no longer on the
help screen. When the slot is already full, the old piece comes off first and the new one goes on
after it, each over the turns it takes. A creature coming into view or a blow landing between the
two stops the swap, leaving the old piece off and the new one in the pack, and the last line says
so, as in "You are interrupted, and have not put on the chain mail yet!". A cursed piece that will
not come off stops the swap before it starts, and no turn passes.

### Arrows and darts wear out

Each arrow or dart that lands has a 1 in 10 chance to become damaged, and a damaged one has a 1 in
20 chance to break. Damaged ammunition is named as damaged, hits a little less hard, and does not
stack with sound ammunition. Masterwork ammunition has half the chance of damage or breaking, and
blessed ammunition half again. Stones and rocks never wear out, and arrows that creatures shoot
wear out the same way. A damaged arrow of the quiver's own kind is still picked up on the way and
goes under its own letter. Other items cannot be damaged yet, since nothing in the game does it.

### Right-click and drag pans the map

Holding the right mouse button on the map and dragging moves the view, so the player can look at
another part of the floor without moving. The view stays where it was left until the next turn or
`Escape` brings it back to the character. A right click no longer draws a route.

### Explore ignores items seen from far away

`X`, `_` and `v` no longer stop for an item seen from too far off to read. The walk goes on, and
it stops when the character comes within eight squares and can make out what the item is. Once
nothing is left to see on a floor, `X` walks toward such an item and stops when it can read it.

### Blessed and cursed are underlined in the message pane

The words "blessed" and "cursed" in the message pane are underlined, white for blessed and red for
cursed. A terminal that cannot color an underline draws a plain one. "Uncursed" is not marked.

### The quiver refills itself from the pack

When the last of the quiver's ammunition is fired or thrown, the best stack of the same kind in
the pack goes into the quiver, and the message pane says so. It ranks by the known enchantment,
then a known blessing, then the larger stack. Ammunition known to be cursed is never chosen. With
nothing of that kind in the pack, the quiver stays empty and remembers what it held.

### A key to walk to what explore just saw

`v` walks to the items `X` last stopped for, nearest first, and the next `v` walks to the next
one. It never walks to a creature, and it says "There is nothing more to walk to." when the list is
used up. An item that comes into sight on the way joins the list, and running in a direction
clears it. The list is kept in the save.

### Explore does not stop for torches

`X` and `_` no longer stop when a torch comes into sight, and they leave torches out of the items
they name when they stop for something else.

### Explore collects the quiver's ammunition

`X` walks to arrows or stones that match what is in the quiver, or what an empty quiver
remembers, the way it walks to gold. Known piles come before unseen squares, nearest first, and
the pickup on arrival goes into the quiver without stopping the walk. Other ammunition is left
where it lies, and `_` does not turn aside for any of it.

### Stairs down land far from the arrival

The down staircase is placed in a room at least half the floor's longest walk from the up
staircase, so a floor is no longer over in a few steps. A floor too small for that uses the
farthest room. An existing seed keeps its layout and its up staircase, but creatures, sconces and
loot may sit on different squares where the down staircase moved.

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
