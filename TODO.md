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

### A pickup filter

What to pick up without being asked becomes an ordered list of rules, such as "gold only", "never a
cursed item", or "anything better than what I have". The rules are set on the options screen. They
are part of the game state and are recorded in the replay.

### A tutorial for new players

A guided first run that introduces moving, fighting, picking things up, the pack, doors, stairs
and saving, one at a time, with the game pausing to explain each when it first matters. It is
reachable from the title screen and never shown unasked after the first time.

### Spells

A mana pool that comes back over time, two starting spells to choose between at creation, and
spellbooks found on the floor that each teach one more. The first two spells are a lock that holds
a door shut for a while and a blinding that stops a creature seeing for a few turns.

### Shouting and footsteps make noise

Creatures that shout and a character who walks make noise, as fighting does. A quiet player then
goes unnoticed for longer. Creatures calling out to each other, as in the band communication item
below, has an effect only once shouting makes noise.

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

### A minimap

A corner of the screen shows the whole floor at four by two squares per cell, or as an image where
the terminal draws them.

### Smoother bars

Where the terminal draws images, the health and other bars move by a pixel rather than a cell.

### A bot that plays well enough to trust

The trial bots shut doors and back away when hurt, but neither spikes a door or decides whether a
fight is worth having, so what the trials measure is still narrow.

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

### A floating pack window

The pack in the left sidebar becomes a toggle that opens a floating pack window. The window can be
dragged to the left or the right side of the map. A reveal toggle on it shrinks the window to a
very few lines, and toggles it back to full size. The sidebar then has room for other things.

### Light, darkness and burning squares

Each square holds a light timer and a dark timer. A permanent effect is a sentinel value that the
tick leaves alone. Both timers count down every turn. Light set alone shows light, dark set alone
shows darkness, and both set or neither set shows nothing. Light and darkness cancel each other
and do not stack. The square keeps no record of which came second. While both are present the
square is neutral, and when one expires the other shows for the turns it has left. A neutral
square behaves as an ordinary one, so a torch lights it and a creature in it is seen normally.
Magical darkness blocks light and line of sight like a wall.

A cast of the same kind raises that timer to the new value if the new value is larger. A permanent
cast over the opposite kind clears both timers, so permanent light destroys darkness and permanent
darkness destroys light. A temporary cast over the opposite kind writes its own timer, and that
suppresses the other kind until it runs out. The permanent glow that the floor keeps today becomes
the light kind with a permanent timer.

The wand of light is an aimed burst centered on a targeted square, with radius 6 as the glow has
now, and it makes passable squares permanently light. Any square may be targeted, not only a known
empty one. The bolt travels in a line from the character and bursts where it reaches the target or
hits a wall. A cursed wand makes temporary magical darkness over the same area for 100 turns, and
that darkness swallows natural light such as sconces and torches inside it.

Each square also holds a burning timer, and a permanent one uses the same sentinel. Permanent
burning is the reason it exists, since a floor with a lava channel across the whole map is a later
idea. Whether lava burns by itself or sets a timer is to be decided when lava arrives. A creature
that ends its turn on a burning square takes fire damage, whether it moved there or stayed. A cast
also deals damage at once to the creatures on the squares it sets alight. For now creatures treat
burning squares as walls when they plan a path, and later a desperate creature may choose to cross.
Each burning square is a light source of radius 3. Flammable items on a burning square are
destroyed. Burning stacks by addition, so a second zap adds its turns to the squares chosen both
times, and some squares burn longer. The display uses the existing flicker clock as another flame,
with a red underline and overline where the terminal supports them and a changed background color
where it does not.

The wand of fire sets half of the squares within radius 6 of the character alight at random, for 3
turns, and never the square under the character. A blessed wand chooses every square that holds a
creature in range first and then fills the rest at random up to half. It does double damage and
destroys no items. A cursed wand burns for 5 turns, its draw can include the character's square,
and it never chooses a square that holds an enemy.

The wand of lightning strikes along a straight line up to 24 squares long in the aimed direction.
The line and one square on each side of it are lit for one turn. The first creature struck takes
high damage, and each creature after it along the line takes less. A blessed wand does damage to
every creature in the lit area, not only on the center line. A cursed wand centers the line on the
character at the same angle, and the character takes the damage too.

### The potion of fire breathing and the scroll of darkness

The potion of fire breathing breathes a cone 45 degrees wide and 12 squares long, aimed at any
square within 12 of the character. Each creature in the cone takes 1d4 fire damage. When the
potion is blessed, creatures in the cone are also set aflame, and each takes 1 damage a turn for 4
turns after the breath. A few of these potions soften a group without breaking the game.

The scroll of darkness makes a burst of permanent magical darkness centered on the character, with
radius 3. It follows the light and darkness rules above. It destroys permanent light under it,
suppresses temporary light, and blocks light and sight like a wall.

### Pets

The character can have a pet, a creature that follows the character from floor to floor and fights
on the character's side. How a player gets one, what kinds there are, how a pet is told what to do,
and what happens when it dies are to be settled when this is built.

### Where the game is drifting

Light, stealth, detection range and shutting doors move survival most, which pulls play toward
stealth. Whether that is wanted should be looked at again once creatures do more than walk at the
character and swing.

## Unplanned

Nothing is here yet. This section records items we decided not to follow up on, so the decision
is not made twice.

## Completed

### Sound and noise

Fighting, missiles, wand bolts, doors struck and broken, and shattering make noise. Noise goes
around walls and is muffled by shut doors. A sleeping creature that hears it stirs, stands still
for a turn, and then searches toward the sound. An awake creature heads for the sound. A thrown
rock draws creatures to where it lands. The character hears noise from out of sight, with its
direction, once every ten turns for each kind of sound, and a blinking note on the map points
toward it. A noise bar in the character pane shows how far the character's recent noise carried and
falls as turns pass. For one turn after the character makes noise, the map tints the squares it
reached, brightest at the source.

### Armor weight slows the character

Body armor has a weight class that sets how fast the character walks and attacks. With nothing on,
the character walks a tenth quicker than a turn a step. Leather armor walks at a normal pace, and
chain mail a little slower. Chain mail adds a tenth of a turn to each melee blow. A shield adds a
tenth to each blow and does not slow walking. Creatures in armor follow the same rule. A padded
jacket is a light armor that protects less than leather and is easier to move in. The Scores
section shows the walking pace and the melee damage per turn. A weapon's description gives the
damage per turn in the character's armor, and an armor's description says how much it slows
walking and attacks.

### Settings for explore

An "Explore" row on the options screen opens the settings for `X`. They set how far a small pocket
may be and still come first, how large a pocket may be, and whether `X` walks to gold, to what
automatic pickup takes, and to items too far off to read. They also say whether `X` finishes a room
or a corridor before it leaves. Each thing that stops a walk can be turned off. Two stops can be
turned on, a creature attacking the character and finding the stairs down. During play the settings
belong to the character and are kept in the save and the replay. From the title screen they set
what a new character starts with. `--explore` sets them for one run, and a bot can change them at
any point with the `configure` action, which takes no turn. The defaults are the explore that
existed before.

### Events for every change to a character stat

The game emits a `stat_changed` event each time one of the character's stats changes. It names the
stat, the old and new values, and the cause. It covers hit points, maximum hit points, experience,
level, the attributes, gold, armor class, to-hit, melee and ranged damage dice, ranged to-hit and
speed, which it calls `pace`. Bots read the events in the stream, and the events file holds them.

### Temporary effects show their time remaining

A haste, a slow or a blindness on the character gets its own bar in the character pane, below the
experience bar. The bar shows the effect's name and the turns it has left, empties as the effect
wears off, and goes away when it ends. The three bar colors are in the theme editor.

### Ten floors, new creatures and Ulgroth

The dungeon is ten floors deep, and the amulet chamber lies under floor 10. Below floor 5 the
slimes, goblins, ants and shallow beasts give out one by one. Floors below floor 5 are drawn
larger, rooms hold more creatures, and gold piles are larger. Items on floors 8 to 10 can be up to
+4. Experience levels past 9 need half again as much as the level before, so the character keeps
gaining levels on the deeper floors.

Thirteen new creatures arrive in four new factions. Beasts are rats, wolves, boars, snakes, bears
and werewolves, and they fight every other band, other beasts included. Undead are skeletons and
zombies, and they fight every band that is not undead. Imps are fast, hard to hit and run when
hurt. Gelatinous cubes are slow and tough. Stone and iron golems guard the lower floors and fight
only the character. Ulgroth, the orc warlord, guards the amulet with two orcs and an orc archer.
The chamber is a landing behind a shut door and a long pillared hall, and his band hears the
character on the stairs and comes to the door.

### A modern control configuration

A second control scheme, called modern, sits beside the classic one. The first interactive launch
offers the choice, and the options screen switches schemes while the game runs. Movement is on
`WASD`, with `Q`, `E`, `Z` and `X` for the diagonals, and the shifted letters walk in that
direction. `r` opens the full catalog of actions. `f` opens the actions available right now, and a
second `f` confirms a target. `g` picks up, `.` waits, `Ctrl+X` explores, and `<` and `>` use the
stairs or route to them. Menus and forms move their selection with the movement keys. `F2` opens
the catalog in either scheme. The help screen shows the scheme in use.

### A color theme

The game reads its colors from `theme.json` in its state directory when that file exists, one
color per line written as `#rrggbb`. A color the file leaves out keeps the game's own. "Color theme"
on the options screen lists every color the game draws, grouped as Map, Creatures, Light, Items,
Text, Panels and Bars. `Enter` on a color opens a picker, and the screen behind changes as the
choice moves, with a preview of map glyphs, an item line and a message at the top. `r` puts one
color back, and "Reset every color" puts them all back after asking. Each change is saved. On a
terminal without 24 bit color the picker offers the 256 colors it can draw.

### An options screen

Preferences live in `options.json` in the state directory, read at start. They are motion, flicker,
mouse reporting, the update check, sending runs, and the bar color, which is `gradient` or `bands`.
`--motion`, `--flicker`, `--update-check` and `--autosubmit` override the file for one run and leave
it unchanged. `o` on the title screen and `O` during play open the options screen, which also holds
the tester name. A change is kept as soon as it is made and takes no turn. Motion, flicker, bar
color and the mouse change while the screen is open, and the update check and sending runs take
effect at the next start. A setting that a flag overrode for this run says so, and changing it on
the screen keeps the player's choice.

### Learning a kind says so

When the character finds out what a potion, scroll or wand is, the message pane says so, as in
"You learn that a scroll THARR is a scroll of identify." The line comes after what the item did,
and it replaces the old "It was ..." line. A blessed scroll of identify gives one line for each
new kind, in letter order.

### `F` fires at the nearest enemy

`F` fires the readied ranged weapon at the nearest monster in sight, with no aiming step. It gives
the same refusals as `f` for no ranged weapon, an empty quiver or the wrong ammunition. With no
monster in sight it says "There is nothing to fire at.", and with monsters in sight but none in a
clear line it says "There is no clear shot." Neither spends a turn.
It works in both control schemes.

### The Seen list is sorted by distance

The Seen list shows the nearest creature or item first. Two that are equally far apart are ordered
by row and then by column, so the list reads the same way every turn.

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
