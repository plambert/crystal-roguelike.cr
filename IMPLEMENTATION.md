# Implementation plan

A phased build of a terminal roguelike on [termbuf](https://github.com/plambert/termbuf.cr),
[termbuf-input](https://github.com/plambert/termbuf-input.cr) and
[termbuf-widgets](https://github.com/plambert/termbuf-widgets.cr).

Each phase adds one or a very few features, and each ends at a point where the game runs and the
new thing can be seen working. No phase starts until the one before it is verified.

The target at the end of Phase 25 is a small, complete, winnable game. It is deliberately much
smaller than what this is meant to become — see [Long-term direction](#long-term-direction) for
where it is going, and [Architecture](#architecture) for the handful of early decisions that
exist so the road there stays open.

## How a phase is done

Every phase carries the same two lines:

* **Build** — what the phase adds.
* **Verify** — what proves it works, in the terminal and in `crystal spec`.

A phase is finished when `crystal tool format`, `ameba`, and `crystal spec` are all clean, the
binary builds, the model still round-trips through serialization, and the **Verify** line has
actually been run rather than reasoned about.

## Settled decisions

| Decision | Answer |
|---|---|
| Module namespace | `Roguelike`, not `Crystal::Roguelike` |
| Diagonals | NetHack `y u b n` |
| Run | A `G` prefix; `Shift` is reserved for other commands |
| Inventory | `i` |
| Pick up | `,` |
| Command line | `Shell::AutoComplete`, not `OptionParser` |
| Terminals supported | ghostty (primary), kitty, iTerm2. Terminal.app is not supported |
| Colour floor | 256 colours required; 24-bit used wherever it helps |
| Numpad decoding | Deferred until there is a keypad to test it on |
| Git transport | ssh for GitHub, via a global `url.insteadOf` rewrite |
| Level and floor | A `Floor` is one map. A `Player#level` is how far the character has advanced |
| Armour class | Higher is better. It is what is worn plus the dexterity modifier, floored at zero |
| Readying a weapon | `w` picks the slot from the item, so one key fills melee, ranged and quiver |
| Field of view | Symmetric shadowcasting on exact fractions. If A sees B then B sees A |
| Seen | A square is seen when it is in the field of view and lit. A dungeon floor starts dark |
| Light in the model | `LightKind`, never a colour. `Ui::Palette` holds the colours |
| Sconces | A `Fixture` on the open square beside the wall, not a terrain. The wall keeps its rock |
| A mounted flame | Throws the whole radius over the half turned away from its wall |
| A standing flame | Throws every way, one step less far, because the flame is at ankle height |
| Shading | Five steps through `Widgets::Ramp`. The remembered step sits well below the four lit ones |
| Palette brightness | A wall is drawn brighter than the floor beside it, and an item brighter than both |
| Belief | `Knowledge` per believer per floor. `Game#look` is the one way anything gets in |
| Flicker | Drawn, never played. It shifts a shade and decides nothing, so a seed still reproduces a run |
| One flame | Every square one flame lights takes its shift. Overlapping pools add. `--no-flicker` stops it |
| A creature in the dark | Seen by the light on it, or as a shape against light behind it |
| Monsters on a floor | Keyed by square, so one square holds one creature and the lookup is free |
| What a creature knows | Its own `Knowledge` and its band's, never the same one. `Band#sharing` says how the second reaches the first |
| Floor file layers | One character per square. A mark that is not terrain takes its ground from the squares beside it |
| A swing | `d20` plus the attacker's bonus against the defender's armour class. Twenty always lands, one never does |
| Combat rolls | Their own stream per swing, named by how many the run has rolled, so a save file holds a count |
| Noticing | A band notices, not a monster. Reach is the species' own, less stealth, plus the light on the character, a square per point |
| Seeing in the dark | An orc's reach ignores light. A goblin or a slime notices nothing unlit, however close it stands |
| Pursuit | One `Descent` per band per turn, flooded over the band's own `Knowledge`. Its members step downhill |
| A creature's decision | `Pursuit.decide` reads a snapshot holding no floor and no player, and answers an `Action` |
| Seeing across a square | A creature that can see somebody writes down that the ground between can be crossed, and no more |
| Touch | A creature knows the terrain of the eight squares round it and what is fixed to them. Items only where it stands |
| Hands on | A door opened or shut and a sconce lit or put out are remembered as they were left, light or no light |
| Monster loot | Independent draws per species, each with its own chance and table, on a stream named by where the creature stands |
| A carried light | Rolled alight. A monster holding one lights itself, and it goes on burning where the monster fell |
| Swinging back | A creature swings at a sighting no more than a turn old, so one stabbed in the dark hits back |
| Aiming | `f` and `t` put the Phase 4 examine cursor on the map. `Tab` walks the monsters in sight, nearest first |
| A missile's line | Bresenham, the line sight and light already use. It stops at the first creature, the first wall, or its reach |
| Where it lands | On the square it stopped on, hit or miss. A fired arrow is on the floor to be picked up again |
| How far it goes | A bow, a sling, a dart and a rock say. Anything else goes ten squares less one per twenty of weight |
| Sidebar | Three sections: "Here" is the square underfoot, "Seen" is what is in sight now, "Look" is the square pointed at |
| Here and Seen | What is there now, never `Knowledge`. The map draws what was last seen. These two say what is seen |
| Naming the ground | "Here" always names the terrain underfoot. Nobody reads it standing still. Everybody notices it change |
| An item's effect | An `Effect` member. `Game#work` is the whole registry. Nothing in the model holds a block |
| Finding out by use | Using an item names its kind, and every item of that kind with it. Each effect here is one a watcher would understand |
| A use rolls on its own stream | `#draught` is `#exchange` without the fight, so a potion drunk mid-fight does not shift the swings after it |
| An empty wand | Costs the turn and says nothing happened. A person cannot know a wand is spent until they try it |
| Shutting a door | A doorway with a creature or a pile in it stays open. The door swings through that square |
| Who says why | `Game` writes the refusal. `Play` never writes over it with a guess about what went wrong |
| A scattered launcher | Lands with ammunition it fires within three squares, most of the time. A bow nobody can shoot is scenery |
| The supply's stream | Named by the launcher's square, never the litter's own, so adding the rule moved nothing else on the floor |
| Reading in the dark | Refused. A scroll is words on paper. The scroll is not spent and no turn is taken finding that out |
| A shape against light | Drawn by `Species::Size`, in one colour for every species. A letter names a species and a shape names none |
| Shooting at a shape | Allowed. `Tab` walks it and a bolt, an arrow or a rock flies at it. Seeing something move is enough to aim |
| Glyphs for a shape | `∙`, `▪` and `◼`. No letters, and none East Asian Ambiguous: a two-cell glyph would tear the map's grid |
| A shape wavers | With the flame lighting the square behind it, not with its own square. Its own square has no light on it |
| How far it wavers | One step up from the dimmest lit step, and never below it. A shape drawn dimmer than that reads as a memory |

## Ground rules

These hold from Phase 0 and are not revisited.

* **One seed, many streams.** A run has one seed and `--seed N` reproduces it exactly, which is
  what makes every later phase testable. It does not have one sequence: `Rng#derive(domain, id)`
  picks an independent PCG32 stream from a stable hash of the name, so what a floor, a loot
  table or a monster band draws does not depend on what anything else drew first. One shared
  stream would make a run deterministic without making it stable — adding a roll anywhere shifts
  every roll after it — and it cannot work at all once planning is parallel, because the
  interleaving between threads is not the same twice. Nothing calls the global `Random`, and a
  derived generator belongs to one fiber.
* **A domain name is part of the seed contract.** Renaming one changes every seed that reaches
  it. The pinned derivation specs are there so that is a decision rather than an accident.
* **The game is headless-testable.** `TermBuf::Widgets::App` takes a `TermBuf::Drawing` and an
  event channel rather than a `Terminal`, so specs drive the whole UI over a bare
  `TermBuf::Buffer` and assert on `Buffer#to_text`. Every phase that draws something gets a
  snapshot spec this way. Nothing needs a tty to test. `Session` owns the terminal, the frame
  loop and the mouse, and `Ui::Play` owns everything shown and everything the keys do, so a spec
  presses keys at the thing that runs rather than at a copy of its wiring.
* **The model knows nothing about the screen.** Floor, player, monsters and items have no
  reference to `TermBuf`. Widgets read the model and draw it. A spec runs a hundred turns with no
  widget tree at all.
* **Turns, not frames.** The loop is `App#wait`, which blocks on the event channel. Nothing
  redraws on a clock. Animation and regeneration are driven by `App#after` timers that arrive on
  the same channel, in order with the keystrokes.
* **Build for 24-bit colour and check the fallback.** Styles carry true colour; termbuf reduces
  at encode time. Each phase that adds colour is also run once under
  `TERMBUF_CAPS=none,+color256` to confirm it is still readable.
* **Level means one thing and floor means another.** The word means two things in a roguelike.
  A `Floor` is one map of the world, and `Player#floor` names which one the character is on. A
  `Player#level` is how far the character has advanced. The types, the fields and the prose all
  follow that split, so neither reading has to be guessed.
* **`shard.yml` names dependencies as `github:`.** Transport is ssh, set once and globally with
  `git config --global url."git@github.com:".insteadOf "https://github.com/"`, which covers
  transitive dependencies as well. Naming a git URL in `shard.yml` does not, and collides with
  the `github:` a dependency's own `shard.yml` uses for the same shard.

## Architecture

Four decisions that cost almost nothing now and are expensive to retrofit. Each exists because of
something in [Long-term direction](#long-term-direction).

### Floors persist, so the model serializes from the start

Floors are not thrown away when they are left, and eventually they live in a save file. So the
world is a `World` holding `Floor`s by id, and every type in the model round-trips through
serialization from Phase 3 onward, with a spec that says so.

The constraint that follows, and the one that bites if it is found late: **nothing in the model
holds a `Proc` or a closure**. Behaviour is named — an enum, a symbol, a registry key — and
looked up. A monster's attack pattern, an item's effect and a trap's trigger are all identifiers,
not blocks.

Save and load themselves are future work. Serializability is not.

### Belief is modelled apart from truth

What is on a floor and what somebody thinks is on a floor are two different things, and the
second one is where the interesting behaviour lives. So there is a `Knowledge` type from the
first moment anything needs to remember a floor: terrain seen, where things were when last seen,
where somebody was last known to be, and how stale each of those is.

The player's remembered map in Phase 14 is the same type a monster band uses in Phase 19. Writing
it once, for the player, and reusing it is the whole point of putting it this early.

### One owner for game state, and AI that proposes rather than mutates

The model is owned by one fiber. Nothing else writes to it. An AI decides what a monster does by
reading a snapshot and answering an `Action`; the owner applies it. Through Phase 25 this is all
one fiber and one thread, and none of it is parallel.

It is written that way regardless, because moving planning into a
`Fiber::ExecutionContext::Parallel` later is then a scheduling change rather than a rewrite. The
rule to keep: **an AI function takes a snapshot and returns an action, and touches nothing.**

### Monsters belong to bands, and bands have factions

A `Monster` carries a `band` and the band carries a `faction`, from Phase 16, even though nothing
reads either until much later. A band is the unit that shares knowledge, and a faction is the
unit that decides who fights whom. Adding the fields to a serialized type later means migrating
save files; adding them now costs two lines.

### A creature knows two things: what it saw and what it was told

Every creature has a `Knowledge` of its own, and so does its band. The two are never the same
object, so that one creature walking into a room can be told apart from the band having been told
about it. `Band#sharing` decides how the second reaches the first:

| `Sharing` | What it is |
|---|---|
| `Inherited` | The band's knowledge seeds a new member's own, and the two go their own ways. A tribe whose members have all walked these corridors before and who each saw something different yesterday. Most bands. |
| `Hive` | One mind in several bodies. What one member sees, the band and every other member know in the same turn. A hive, and some slimes. |
| `Called` | Each member keeps its own and passes it to whichever members are near enough to be told. A pack that calls out. |

`Knowledge#sightings` is where each creature was last seen, by who, with the turn. A monster goes
to where it saw the character rather than to where the character is, which is the difference
between a creature that hunts and one that cheats. `Knowledge#copy` is what `Inherited` hands a
new member.

The fields are in place from Phase 16. Nothing reads them until Phase 19.

## Keybindings

Settled in Phase 5 and extended as each phase adds a verb. All of it goes through `Keymap`, so
none of it is fixed and a preset can rebind the lot.

| Key | Does |
|---|---|
| `h` `j` `k` `l` | Move west, south, north, east |
| `y` `u` `b` `n` | Move northwest, northeast, southwest, southeast |
| `G` + direction | Run that way until something is worth stopping for |
| `.` | Wait one turn |
| `<` `>` | Up stairs, down stairs |
| `,` | Pick up what is here |
| `d` | Drop something |
| `i` | Inventory |
| `w` `W` `T` | Wield a weapon, wear armour, take a weapon or armour off |
| `q` `r` `z` | Quaff a potion, read a scroll, zap a wand |
| `f` `t` | Fire the ranged weapon, throw something |
| `a` | Apply. Light or put out a torch, a candle, or a wall sconce |
| `o` `c` | Open, close |
| `x` | Examine. Put a cursor on the map and move it with the movement keys |
| `Escape` | Take back whatever is waiting for a key |
| `M` | Turn mouse reporting on and off |
| `Ctrl+E` | Grant experience. A debug key, removed when there is something to kill |
| `?` or `F1` | Help, from `Router#active_bindings` |
| `Q` | Quit, behind a `[yn]` prompt |

`Shift` plus a letter is deliberately unbound and kept for later commands.

## Shard extraction

Five pieces are general-purpose rather than roguelike-specific. They are built here first, in
`src/roguelike/termbuf_ext/`, with their own specs and no dependency on game types, and moved to
`termbuf-widgets.cr` once their shape has settled. Each keeps a `# Extraction candidate:` comment
naming what still has to be decided before it moves.

| Piece | Built in | What it is |
|---|---|---|
| `Cells(T)` and `CellGrid(T)` | Phase 2 | A 2D addressable grid widget with a camera |
| `Prompt` | Phase 6 | `[yn]` answered by one keystroke, in a modal overlay |
| `Pager` | Phase 7 | `--More--` held at a page boundary |
| `Menu` | Phase 10 | A list addressed by letter rather than filtered |
| `Ramp` | Phase 14 | A style per step between one style and a colour, from given fractions |

Numpad decoding — the `SS3` keypad keys and a `DECKPAM` `Tty::Mode` for `termbuf-input.cr` — is
deferred until there is a keypad to test it on and it is known which of the three supported
terminals honour the mode.

## Part 1: The harness

Nothing here is a game. It is the ground everything else is built on, and it is the part that
makes the rest cheap to verify.

### Phase 0 — Skeleton, CLI, seeded RNG

* **Build** — Rename the module to `Roguelike`. `Shell::AutoComplete` for the command line:
  `--version`, `--seed N`, `--threads N` as a placeholder, and `--shell-completion` for free.
  A `Roguelike::Rng` over `Random::PCG32`, carrying its seed and its stream, with
  `#derive(domain, id)` for the independent stream a subsystem draws from. The spec helper that
  builds an `App` over a `TermBuf::Buffer` with an `IO::Memory`-backed event channel.
* **Verify** — `shards build` produces a binary. `--version` reports what is in `shard.yml`.
  `--help` and `--shell-completion bash` both produce sensible output. Two runs with the same
  `--seed` draw the same sequence from the RNG; two different seeds do not. A derived generator
  draws the same sequence however much its parent or its siblings have been drawn from, and the
  streams it derives are pinned so a change to the hash fails a spec. The spec helper builds an
  empty app and `Buffer#to_text` comes back blank.

### Phase 1 — Four regions on the screen

* **Build** — `Terminal.open`, a `Widgets::App`, and a root laid out as a row — a map pane that
  grows beside a fixed sidebar of about twenty-four columns — above a one-row status bar and a
  message log of four rows. Placeholder text in each. The sidebar is where Phase 4 puts the
  examine readout and later the character summary. `Q` quits. `HelpOverlay.install`. A minimum
  size: under it the game will not start, and a window shrunk under it during a run shows a
  notice asking for a larger one in place of the whole layout.
* **Verify** — Run it in ghostty. The four regions are there and in proportion; resizing reflows
  them and narrowing past the sidebar's width drops the sidebar rather than overflowing;
  shrinking past the minimum shows the notice and growing again brings the game back; starting
  in a window under the minimum says so and exits without taking the terminal over; `Q` gives
  the terminal back; `?` shows the help overlay. A snapshot spec renders the layout at 80x24, at
  200x50, with no sidebar and with the notice, and compares `Buffer#to_text` against fixtures.

### Phase 2 — `Cells(T)` and `CellGrid(T)`

The one piece of shard-shaped work that has to come before anything can be drawn.

* **Build** — `Cells(T)`, a source answering `#size` and `#cell(x, y)`, modelled on the existing
  `Rows(T)`. `CellGrid(T) < Widget`, including `Scrolls`: an `#on_draw(view, x, y, cell)`
  callback per visible cell, `#center_on(x, y)`, `#reveal(x, y, margin)` for a dead-zone camera,
  `#cell_at(view_x, view_y)` for turning a mouse report back into grid coordinates, and camera
  clamping at the edges.
* **Verify** — Specs on the viewport arithmetic: a grid smaller than the pane is not scrolled; a
  grid larger than it clamps at both edges; `center_on` at a corner clamps rather than showing
  blank; `cell_at` round-trips against `center_on` for a hundred random points; `reveal` with a
  margin moves only when the point is inside the margin. Visually: a 200x200 checkerboard scrolls
  under the arrow keys inside a 40x15 pane and a `Scrollbar` attached to it tracks.

## Part 2: A world to walk in

### Phase 3 — Terrain and a hand-built floor

* **Build** — A `Terrain` enum: `Granite`, `Sandstone`, `Shale` (three rock walls, identical in
  behaviour for now, distinct in colour), `StoneFloor`, `DirtFloor`, `ClosedDoor`, `OpenDoor`,
  `StairsUp`, `StairsDown`. Each carries the character a floor file writes it as, a label, a
  description, whether it blocks movement and whether it blocks sight — but not a glyph or a
  style, which are the screen's and live in `Ui::Palette`, per the rule that the model knows
  nothing about the screen. A `World` holding `Floor`s by id; a `Floor` holding a grid of `Tile`,
  loaded from a plain-text map file under `data/floors/` so the fixture is readable and diffable
  and read into the binary at build time so the game runs from anywhere. The floor drawn through
  `CellGrid`, by way of a `Ui::LevelCells` adapter that keeps `Floor` free of the widget layer.
  Serialization for everything so far, with the terrain stored as the same text a floor file
  holds.
* **Verify** — The test floor loads and renders, walls in three colours, doors and stairs
  visible. A spec loads the fixture and snapshots the rendered pane. A spec asserts every glyph
  in the file maps to a terrain and that an unknown glyph raises rather than silently becoming
  floor. A spec round-trips the `World` through serialization and gets an identical one back.

### Phase 4 — Mouse hover and the examine pane

* **Build** — `terminal.enable TermBuf::Tty::MOUSE_SGR_ANY`, so motion with no button held is
  reported. Hovering a map cell puts what is there into the sidebar — the terrain's name and
  description, and, once Phase 10 exists, everything lying on that square. It is a permanent
  readout, not a tooltip: it holds the last thing hovered rather than blanking on the way past.
  `x` does the same thing from the keyboard with a cursor moved by the movement keys, and `M`
  turns mouse reporting off and on, since a terminal reporting the mouse no longer lets the
  person select text with it. While the pointer is over the map the terminal's own cursor sits
  on the square under it and the pointer becomes a crosshair through `OSC 22`; the cursor is
  hidden again and the pointer asked back to `text` when it leaves, when the mouse is turned
  off, and when the run ends. There is no reset to ask for: kitty takes an empty `OSC 22`
  payload as one and ghostty parses the payload as a shape name and ignores what it does not
  know, so only a named shape works, and `default`, `text` and `pointer` are the three every
  terminal with `OSC 22` supports. The pointer cannot be hidden either — every shape is a CSS
  cursor name and none of them means "no pointer", and auto-hiding is a setting in each terminal
  rather than something an application can ask for.
* **Verify** — Hover across a room; the sidebar tracks the terrain under the pointer. Hover over
  the edge of the pane and nothing is reported. Hover a wide glyph and the lead cell is named,
  not half of one. A spec feeds synthetic `Events::Mouse` at known coordinates and asserts the
  sidebar contents; a second spec does the same through `x` and the movement keys.

### Phase 5 — The player moves

* **Build** — A `Player` with a position. The eight movement bindings. Walls and closed doors
  block. The camera follows with a dead zone via `CellGrid#reveal`. A turn counter that advances
  on a move and not on a blocked one.
* **Verify** — Walk around the test floor in all eight directions. Walking into a wall does not
  move and does not burn a turn. The camera holds still until the player nears an edge, then
  follows. A spec feeds a scripted key sequence into the app and asserts the final position and
  turn count.

### Phase 6 — Doors, stairs, and winning

* **Build** — Walking into a closed door opens it and costs the turn. `o` and `c` do it
  deliberately, asking for a direction only when more than one door is adjacent. `>` on the down
  stairs ends the game as a win. `<` on the up stairs leaves. A one-line `[yn]` prompt, the
  first extraction candidate, behind `Q` and behind `<`. The prompt is an `Overlay`: a small box
  in the middle of the screen, with everything behind it dimmed and still readable. It is modal,
  so a key nothing in it claims stops there, and a click behind it reaches nothing.
* **Verify** — A scripted sequence opens a door, crosses the floor, descends, and the win screen
  appears. `Q` prompts, `n` returns to the game, `y` exits. A spec asserts that `>` anywhere but
  on the stairs says so and does not win.

### Phase 7 — The message log

* **Build** — A `MessageLog` holding a queue of messages, wrapped to the pane width with
  `Layout::TextMeasure.wrap` and shown through a `VirtualList` over `Rows(String)`. The
  `--More--` pager — the second extraction candidate — holding at a page boundary until a key is
  pressed, so a burst of messages in one turn is all read. Messages for everything so far:
  bumping a wall, opening a door, arriving at the stairs.
* **Verify** — Messages appear oldest-first and the pane scrolls. A message longer than the pane
  wraps rather than being cut. A turn producing six messages in a four-row pane holds at
  `--More--` and continues on a key. A spec drives twenty messages through a three-row log and
  asserts the sequence of pages.

## Part 3: The character

### Phase 8 — Attributes, hit points, level, experience

* **Build** — `Attributes`: strength, dexterity, constitution, intelligence, stealth. Hit points
  and maximum hit points, derived from constitution and level. Character level, experience
  points, and the threshold for the next level. The status bar showing all of it. A debug binding
  that grants experience, so levelling can be watched before combat exists.
* **Verify** — The status bar reads correctly and reflows when the window narrows. A spec over
  the levelling table: experience at each threshold raises the level exactly once, maximum hit
  points rise, current hit points rise by the same amount.

### Phase 9 — Items and variants

The model only. Nothing is on the floor yet and nothing can be carried.

* **Build** — An `ItemKind` catalogue: healing potion; arrows, stones, rocks, darts; short sword,
  long sword, rapier, dagger, mace, spear; sling, bow; leather armour, chain mail, shield, cap,
  boots, gloves; scrolls; wands. An `Item` carrying a kind plus its variants: an appearance
  (colour or material, assigned per seed, so "a swirly potion" means the same thing all game and
  a different thing next game), an enchantment `+N` or `-N` for weapons, armour and ammunition,
  a condition of damaged, plain, or masterwork, and a blessing of blessed, uncursed or cursed.
  The blessing is hidden per item rather than per kind, because two identical swords may be
  blessed and cursed, and a cursed item leans toward a penalty. Naming that composes all of it:
  "a damaged short sword", "a blessed masterwork +1 chain mail", "a swirly potion" before it is
  identified and "a potion of healing" after.
* **Verify** — Specs on naming across the combinations, including the article. Specs that the
  appearance mapping is stable within a seed and differs between seeds. A spec that generating
  ten thousand items under a seed produces the same multiset every time.

### Phase 10 — Floor items, pick up, drop, gold

* **Build** — Items lying on the floor, drawn on the map under the player, and named in the
  examine pane from Phase 4. `,` to pick up, `d` to drop. An inventory with letter slots. The
  inventory screen, addressed by letter — the third extraction candidate, an accelerator list
  rather than a filtered one. Gold as the simplest floor item, counted rather than carried, shown
  in the status bar.
* **Verify** — Walk onto an item, pick it up, see it in the inventory under a letter, drop it,
  see it on the floor again. Two items in one square offer a choice, and the examine pane lists
  both. Gold adds to the total and leaves no inventory slot. A spec asserts letters are assigned
  stably — dropping `b` and picking up something else does not renumber `c`.

### Phase 11 — Equipment slots and derived stats

* **Build** — Slots: melee weapon, ranged weapon, and quiver; shield, body, feet, hands, head.
  `w` to wield, `W` to wear, `T` to take off. Derived stats: armour class from what is worn plus
  dexterity, damage from the wielded weapon plus strength, each adjusted by enchantment and
  condition. The status bar showing armour class and the wielded weapon.
* **Verify** — Wield and wear across every slot; armour class and damage change as expected.
  Wearing a second body armour is refused with a message. Specs over the derived-stat table for a
  matrix of equipment, enchantment and condition.
* **Done.** `Slot` names all eight. `Equipment` holds an inventory letter per slot rather than an
  item, so a readied sword is still listed in the inventory and a save file holds one copy of it.
  `w` picks the slot from the item, which fills melee, ranged and quiver from one key, so the
  quiver needs no key of its own before Phase 21. Armour class is higher-is-better. Dropping a
  readied item is refused until it comes off, and a cursed one announces itself as it goes on.
  The inventory list marks each readied item the way NetHack does.

## Part 4: Sight and light

The largest part, split so that each step is visible on its own.

### Phase 12 — Field of view

* **Build** — Symmetric shadowcasting from the player over the terrain's sight-blocking flag.
  Everything within the field of view is drawn; everything outside it is blank. No light yet —
  the whole floor is treated as lit.
* **Verify** — Standing in a room, the room is visible and the corridor behind the door is not.
  Standing in a corridor, sight runs its length and stops at the corner. Specs against fixture
  maps with the expected visible set written out as a second text file, so a change to the
  algorithm shows as a diff of two maps.
* **Done.** `FieldOfView` is Albert Ford's symmetric shadowcasting over four quadrants. Every
  comparison is on whole numbers: a slope is a `Fraction` of two integers, so a square on the
  edge of a wedge falls the same side of it every time. A spec asserts the symmetry itself over
  every pair of open squares on a map with walls in it. Four fixtures under `spec/fixtures/sight/`
  hold the visible set as a map. A field of view is derived rather than stored, and `Game#sight`
  works it out again each time it is asked, because it depends on where the character stands and
  on which doors are open. The examine pane says "out of sight" for a square the character cannot
  see, so the whole map cannot be read with the pointer.

### Phase 13 — Light sources

* **Build** — A `LightSource` with a position, a radius and a colour. Static sources: a wall
  sconce that is unlit until `a` lights it, and a room flagged as magically lit. Carried sources:
  a torch or a candle the player holds, and one set down on the floor. A lighting pass that
  accumulates light per tile, and a visibility rule combining it with the field of view — a tile
  is seen when it is in the field of view and lit, so a distant lit room is visible across a dark
  one and an unlit corridor is not.
* **Verify** — With no light, nothing but the player's own square is visible. Lighting a sconce
  reveals the room. Dropping a lit torch and walking away leaves the pool of light behind and
  visible. Standing in a dark corridor looking into a lit room shows the room and the doorway.
  Specs on the accumulation against fixture maps.
* **Done.** `Lighting` accumulates a level per square; `Vision` is the field of view cut down to
  what is lit, and every pane takes one of those instead of a bare `FieldOfView`. A source lights
  what it can see, so light does not go round a corner. Light comes from three places: a lit
  `Fixture` on the floor, an `Item` that `#burns?` and is lit, carried or lying down, and the
  floor's own `#glow` and `#ambient`. A glowing square spills onto every neighbour, walls and
  doors included, so a lit room has an edge to it and a door in a wall can be found. `a` lights or
  puts out whichever of those is to hand. The proving ground is dark, with four sconces in the
  first room, two in the second, and a magically lit room around the down staircase; the character
  starts holding a lit torch.

A sconce began as two `Terrain` members replacing a wall square. That made a sconce on granite and
a sconce on sandstone the same terrain, and the rock a wall is cut from has to keep mattering:
digging, sound and floor generation all read it. It also made the light shape an accident of
casting from inside a wall rather than a rule.

`Fixture` replaced it. A fixture stands on the open square beside the wall it is bolted to, which
is where the flame is, so the wall keeps its rock and the cast is an ordinary one. `#attached`
names the wall, and a fixture with none stands on its own foot. A floor file writes `|` and `!` on
the open square; `Floor.parse` infers the attachment from the one wall touching it, and takes the
terrain under it from the squares beside it, so a sconce in a dirt room stands on dirt.

### Phase 14 — Knowledge and remembered terrain

The phase that introduces the type monster bands will use in Phase 19.

* **Build** — `Knowledge`: what somebody believes about a floor — which tiles they have seen and
  what was on them, where things were when last seen, where each creature was last seen, and how
  many turns ago each of those was.
  The player gets one. Terrain once seen is remembered and drawn dim; items and monsters are
  remembered as they were, and are not updated while out of sight. The quantized style ramp — the
  fourth extraction candidate — giving a fixed number of steps between lit, dim and unseen, so
  the style table stays bounded no matter how many frames run.
* **Verify** — Walk through a room and out; its shape stays on the map, dimmed, and the item that
  was in it is still drawn where it was even after it is moved. A spec asserts the style table
  stops growing after the first few frames of a long walk. A spec round-trips `Knowledge` through
  serialization.
* **Done.** `Knowledge` holds a `Memory` per square: the terrain, the fixture and the top item as
  they were, and the turn it was seen on. Each is a copy, so a torch that burns down or a door
  that shuts after the character looks away does not change what they remember. `Player#memory`
  keeps one per floor, because floors persist. `Game#look` is the one way anything gets in, and
  whatever is about to draw the floor calls it, so what is remembered and what is drawn are never
  out of step. `Game#sight` answers the same thing without recording it, for a spec reading the
  field of view. The map pane draws three states: what is there now, shaded by light; what was
  there when last seen, at the bottom of the ramp; and a blank for a square nobody has seen. The
  examine pane says what a remembered square held and marks it `remembered`.

### Phase 15 — Silhouettes and flicker

* **Build** — A monster standing in an unlit tile is drawn when the player has a line to it and
  there is light behind it, so movement between the player and a distant source is seen. Flicker:
  torch and candle sources vary their radius and colour by a small amount on a timer through
  `App#after`, in 24-bit colour, which is the one thing in the game driven by a clock rather than
  a turn.
* **Verify** — A goblin crossing a lit doorway is visible from a dark corridor; the same goblin in
  a dark corner with nothing behind it is not. The flicker is visible in ghostty, readable under
  `TERMBUF_CAPS=none,+color256`, and does not make the game redraw when nothing else changed. A
  spec asserts the silhouette rule on a fixture and that flicker is deterministic under a seed.
* **Done.** `Line` walks a straight line, and `Line.beyond` carries on past a square, which is
  what looks for light behind a creature. `Vision#backlit?` is the rule and `#shows?` is the two
  rules together; `Game#can_see_creature?` is what Phase 16 will ask. There is nothing to draw
  yet, because there are no monsters.
  `Ui::Flicker` shifts which step of the ramp a flame-lit square draws at, and nothing else. A
  square comes into sight or goes out of it by the turn, never by the clock, so a run started from
  a seed plays out the same whatever the clock did while it was running. One shift is worked out
  per flame per tick, from the seed, the tick and where the flame stands, and every square that
  flame lights takes it, so a pool wavers as one flame rather than as a field of squares deciding
  for themselves. Two flames are not one flame and do not move together; where their pools overlap
  the squares they share take both shifts, so two guttering at once drop that ground twice as far
  and one guttering against the other flaring leaves it where it was. A lit square never falls to
  the shade a remembered one draws at, however many flames gutter at once. `Lighting`
  records which sort of light is on each square, which is what says whether a square wavers and
  what it is tinted with: firelight warm, a magically lit room cold. `Session` advances the tick
  through `App#after`, and `--no-flicker` holds the flames still. Two seconds idle sends five or
  six frames of about ninety cells each with a torch lit, and nothing at all with it out.

## Part 5: Things that fight back

### Phase 16 — Monsters on the map

* **Build** — A `Monster` with a species, hit points, attributes, a position, a `band` and a
  `faction`. Three species: slime, goblin, orc, each with a glyph, colour and base statistics.
  Placed on the floor from the map file, each in a band of one. They block movement and are
  drawn, and the examine pane names them. No behaviour at all.
* **Verify** — All three appear, in the right colours, and hovering one describes it. Walking into
  one is refused with a message. A spec snapshots a floor with one of each and round-trips it
  through serialization.
* **Done.** `Species` is the table, `Ui::Palette` holds the glyph and colour, and a floor file
  writes `j`, `g` and `o`. `Floor#monsters` is keyed by square, so finding what stands on one
  costs nothing and a square holds one creature; a monster carries its own position as well and
  `Floor#walk` is the one thing that keeps the two in step. Each is in a `Band` of one, and the
  band carries the `Faction`, because adding either to a serialized type later means migrating
  save files. A creature on a lit square draws in its own colour; one on an unlit square with
  light behind it draws as a shape at the dimmest lit step, which is Phase 15's rule finally
  having something to answer about. Nothing is remembered: a monster is drawn where it is or not
  at all, until Phase 19 gives `Memory` a creature.

### Phase 17 — Melee combat, death, experience

* **Build** — Walking into a monster attacks it. To-hit from dexterity, weapon and enchantment
  against armour class; damage from the weapon, strength, enchantment and condition. Hit points
  fall, messages say what happened, a monster at zero dies and is removed. The player at zero
  dies and the game ends. Experience awarded per species, driving the levelling from Phase 8.
* **Verify** — Kill a slime with a short sword; the messages read correctly, experience is
  awarded, the level rises at the threshold. Die to an orc and get the death screen. Specs run a
  fixed seed through a hundred exchanges and assert the exact sequence, so a change to the combat
  maths shows as a diff.
* **Done.** `Combat.swing` is the whole of the maths: one twenty sided die plus what the attacker
  adds, against `Combat::TARGET` plus the defender's armour class, with twenty always landing and
  one never landing so that neither side is ever unhittable or unmissable. It answers a `Blow`,
  which records the face, the bonus, what it was against and the damage, and changes nobody.
  `Game` reads one and takes the hit points off. Every swing draws from its own stream, named by
  `Game#blows`, so a miss and a hit rolling a different count of values shifts nothing after them
  and a save file holds a count rather than a generator's position. `Species` gained an `armour`
  field, so a goblin is harder to hit than a slime. A creature standing beside the character
  swings back on every turn the character takes, which is the whole of monster behaviour until
  Phase 18 decides whether one has noticed. `Ctrl+E` is gone: there is something to kill now.

### Phase 18 — Detection, stealth and darkvision

* **Build** — Each species has a base detection radius. It is reduced by the player's stealth and
  raised by how brightly the player's own square is lit. Orcs see in the dark, so their radius
  ignores light; goblins and slimes do not, and cannot notice an unlit player beyond their own
  light. A monster is asleep, alert, or hunting, and says so when it notices. Detection state
  lives on the band rather than the monster, so that waking one wakes the band later without a
  change of shape.
* **Verify** — Sneak past a goblin in a dark corridor with a high stealth and no torch; carry a
  lit torch past the same goblin and it wakes. The orc wakes either way. Specs over the detection
  function across the matrix of stealth, light and species.
* **Done.** `Notice` is the whole rule and holds no state: a reach of the species' own `notice`
  less the stealth modifier plus the light on the character's own square, and a straight line
  comparison against it. Two species traits decide how the last two are read. `Species#darkvision?`
  makes an orc's reach ignore light in both directions, so it reads the same in a lit room and a
  dark corridor. Without it a creature sees by the light on what it looks at, so a character
  standing on an unlit square is not noticed at all, however close — which is what a doused torch
  buys, and it is what makes the awake check in `Game#creatures_act` do real work rather than
  never fire. Being hit wakes a band whatever the light, which is `Game#wake` rather than a rule
  in `Notice`.

  Line of sight costs nothing extra. The field of view is symmetric, so the cast the character
  already makes each turn answers which creatures have a line back, and one cast serves the whole
  floor. `Awareness` lives on the `Band`, not the monster: `Asleep` takes no turn at all, `Hunting`
  can see the character, and `Alert` has lost them and knows where they were. A band that notices
  writes a `Sighting` into its own `Knowledge`, which is the phase 16 field finally having a
  writer. Nothing reads it until Phase 19. The examine pane says which of the three a creature is
  in.

### Phase 19 — Pathfinding and pursuit

* **Build** — A band's `Knowledge` of the floor, seeded with the tiles its monsters have seen. A
  Dijkstra map computed over what the band knows rather than over the truth, which every hunting
  monster descends. Attack when adjacent. Lose the player after a number of turns without seeing
  them and go to the last known square. Slimes do not path — they step toward the player and stop
  at walls. Every AI decision is a function from a snapshot to an `Action`, per the architecture
  rule.
* **Verify** — A goblin on the far side of a wall walks around it rather than into it. Breaking
  line of sight and moving makes it go to where the player was, then give up. A goblin that has
  never seen a shortcut does not use it. Specs on the Dijkstra map over fixture floors, and a
  spec that a hundred turns of pursuit terminates and costs no more than a bounded amount of
  work.
* **Done.** `Descent` is a Dijkstra map: the goal holds zero, every square beside it one, and a
  creature walks a shortest path by stepping to whichever neighbour holds a smaller number. The
  search runs once for a band rather than once for each of its members, and it floods over the
  band's `Knowledge` rather than over the `Floor`, so a shortcut nobody has looked down is not in
  it. `Knowledge#walkable?` is the whole of that: a square never seen answers false. The flood
  stops at `Descent::LIMIT`, which is what bounds the work however much floor a band has walked.

  `Pursuit.decide` is the AI and it keeps the architecture rule exactly: it reads a
  `Pursuit::Snapshot` holding no `Floor` and no `Player` — the band's belief, where the band last
  saw the character, whether it can see them now, the descent, and which neighbouring squares are
  taken — and answers an `Action`, which `Game#perform` applies and checks against what is
  actually there. A creature that decides to walk into a wall walks nowhere.

  Every awake creature looks about each turn and writes what it saw into its band's `Knowledge`,
  which is what fills the descent in. A species with darkvision learns the shape of everything it
  has a line to; one without it learns only what is lit. An asleep band looks at nothing, so a
  floor of sleeping monsters costs one cast, the character's own. `Species#paths?` is false for a
  slime, which walks straight at the character and stops against whatever is in the way.

  `Awareness::Alert` now means something: a band walks to the square it last saw the character on
  and gives up `Game::PATIENCE` turns after the sighting, forgetting where they were but keeping
  what it learned of the floor. Being hit writes a sighting as well as waking a band, because a
  band woken with nowhere to go would give up the turn after.

  A creature that can see the character writes down the ground between them. A line of sight that
  reached them ran through every square on the way, so it knows that ground well enough to walk
  it, and it goes on knowing it after the light has gone. That is what lets a goblin in a dark
  corridor walk at somebody standing in a pool of light: it never sees the squares between, but
  it can see across them.

  `Knowledge` holds that apart from what has been seen. `#opening` records that a square can be
  crossed and nothing else — no `Memory`, so `#seen?` still answers false and `#walkable?`
  answers true. Writing a memory there would claim the square is a stone floor, or an open door,
  or a staircase, none of which the creature has looked at. What is remembered wins over what was
  inferred, so a square later seen to be a wall is a wall.

  A creature also knows the ground it could reach out and touch, seen or not, so it can take the
  first step out of a dark square. `#touch` records the shape of that square and what is fixed to
  it, and nothing lying on it. What a creature stands on it knows whole, items and all; what is
  beside it it knows the shape of and no more. Reaching out in the dark says there is a wall
  there, and a bracket bolted to it, not that there is a sword on the floor.

  `#touch` is what a door opened or shut by hand records too, and a sconce lit or put out.
  Somebody who has just shut a door knows it is shut whether or not they can see it.

  One gap, left for later: a creature cannot open a door. A shut door is impassable in a band's
  knowledge, so pursuit stops at one.

### Phase 20 — Monster inventory and drops

* **Build** — Loot tables per species, drawn from the seeded RNG. A slime carries coins and the
  occasional simple treasure. A goblin or an orc usually carries a damaged weapon, sometimes a
  plain one and rarely a good one, sometimes damaged armour and rarely good armour, and sometimes
  a lit torch or candle — which is where Phase 13's carried light sources come from. Everything
  carried drops where the monster died.
* **Verify** — Kill a goblin, pick up what it dropped; kill a goblin carrying a torch and the
  torch is on the floor, still lit. Specs that ten thousand seeded rolls of each table produce
  the stated distribution within tolerance, and that a table never produces an item the species
  should not have.
* **Done.** A species makes several independent draws rather than one. `Loot::Draw` is a table of
  kinds by weight, a chance out of a hundred, and a count; a goblin draws for a weapon, for
  armour, for a light and for coins, and each rolls whether or not the others did. One table of
  everything a goblin might have would make those exclusive, and a goblin with a sword and no
  boots is the ordinary case. A slime has no weapon draw at all rather than one it almost never
  makes.

  Each creature rolls on a stream named by where it stands, which is its stable identity on a
  floor written by hand. Adding an entry to a table shifts what that one creature carries and
  nothing else, and the order the creatures are walked in says nothing.

  `Loot::CONDITIONS` leans toward damaged where `Items::CONDITIONS` leans toward plain, so what is
  taken off a body is more battered than what is lying about the floor. Anything that burns comes
  out alight: a monster carrying a torch is carrying it for the light, `Game#lights` reads it, and
  Phase 13's carried source finally has a carrier. Killing the monster leaves it burning where the
  monster fell.

  Verifying this turned up a hole worth naming. A creature stabbed in the dark stood there and
  took it, because it only swung at a character it could see and it could see nothing. A creature
  now swings at a sighting no more than `Pursuit::FRESH` turns old, and being hit writes one, so
  it fights back at the square the blow came from.

## Part 6: A whole game

### Phase 21 — Ranged and thrown attacks

* **Build** — `f` fires the wielded ranged weapon using ammunition from the quiver — arrows for a
  bow, stones for a sling. `t` throws what is chosen — a rock, a dart, anything. A targeting
  cursor sharing the Phase 4 examine cursor, cycling through visible monsters with `Tab`, drawing
  the Bresenham line to the target and showing whether it is clear. Ammunition that misses lands
  on the floor.
* **Verify** — Shoot a goblin across a lit room; the line draws, the ammunition depletes, the
  arrow that misses is on the floor and can be picked up. Firing a bow with no arrows says so and
  costs no turn. Specs on the line and on what a wall does to it.
* **Done.** `Flight` is the geometry, and it holds nothing else: given a floor, two squares and a
  reach, it answers which squares a missile crosses, where it stops and why. `Landing` names the
  four reasons — it arrived, it met a creature, it met something solid, it ran out of reach. The
  line is `Line.walk`, which is the line sight runs along and the line light comes from, so a shot
  at something visible runs the squares the sight of it ran.

  `Game#fire` and `Game#throw` both end in one private method. It builds the flight, swings at
  whatever is standing where the missile stopped, and drops the missile on that square. A hit and
  a miss leave it in the same place, because an arrow that goes home still ends up on the floor.
  One of a stack goes: a person carrying twenty darts throws one dart, and the last arrow empties
  the quiver slot as well as the letter.

  How far a thing goes is a fact of its kind. A bow, a sling, a dart and a rock each say. Anything
  else goes as far as its weight allows, ten squares less one for every twenty of weight, so a
  dagger crosses a room and a suit of chain mail lands on the thrower's boots. A held weapon can
  be thrown without putting it down first; worn armour has to come off.

  The targeting cursor is the Phase 4 examine cursor. Nothing new draws it, nothing new moves it,
  and the readout it writes is the one that was already there with one row added. `f` and `t` put
  it on the nearest monster in sight, `Tab` walks the rest nearest first, and the movement keys
  walk the squares. `MapPane` colours the line one shade and the square the shot stops on another,
  so a shot that will not reach shows the gap rather than having to be described.

  `Tab` already meant "the next widget" in every application `Widgets` builds. The binding takes
  the key only while something is being aimed and hands it back to the focus stack otherwise.

  `Game#cannot_fire` answers the complaint rather than the shot, so `Play` asks it before the
  cursor goes up. A person with an empty quiver is told at once and spends no turn finding out.

### Phase 22 — Consumables

* **Build** — `q` quaffs — a healing potion restores hit points and identifies itself by use. `r`
  reads — a couple of scroll effects, say identify and magic mapping. `z` zaps — a wand of light,
  which places a permanent light source, and one offensive wand. Charges on wands, and a wand at
  zero charges that says so. Every effect is named by an identifier rather than held as a block,
  per the architecture rule.
* **Verify** — Drink a healing potion at low hit points and watch them rise; the potion is
  identified afterwards and every other potion of that appearance is too. Zap a wand of light in
  a dark room and the room stays lit. Specs on charges, on identification propagating, and on
  each effect.
* **Done.** `Effect` is an enum of six members and `Game#work` is the whole registry. An item
  names its effect and nothing holds a block, which is the rule a save file needs. `ItemFacts`
  gained `effect` and `power`, so what a potion heals for and what a wand hits for are table
  entries beside the weight and the label.

  Using an item names its kind, and `Lore` is per kind, so one swirly potion names every swirly
  potion. That holds for all five effects in this phase because each is one somebody watching
  would understand. `Game#found_out` is where the exception goes when there is an effect nobody
  could see.

  A use rolls on its own stream. `#draught` is `#exchange` without the fight: a potion drunk
  between two swings leaves those swings rolling the numbers they would have rolled. A spec
  fights the same goblin in two games, one of which drank first, and compares the messages.

  `Game#effect_of` answers what an item would do before the turn is spent, which is what lets
  `Play` ask the second question first. A scroll of identify asks which carried item it names,
  and leaves itself out of that list: spending it to name itself teaches nobody anything. A wand
  of striking puts Phase 21's targeting cursor up rather than a second menu, and `Aiming::Zap`
  joins `Fire` and `Throw` on the same three keys.

  A wand of light writes the floor's own `glow` rather than placing anything. That is what the
  proving ground's magically lit room already is, so a zapped room and a built one are the same
  thing and the light survives a save file. Only the passable squares are set. A glowing square
  spills onto every neighbour, so the walls light the way they do round any lit room, and setting
  the glow on them as well would light what is behind them.

  Magic mapping writes `Knowledge#touch` over every square: the terrain and what is fixed to it,
  and not what is lying on the floor. A map shows a person the walls.

### Phase 23 — Running

* **Build** — `G` plus a direction moves repeatedly until something is worth stopping for: a
  monster comes into view, an item or a door or stairs is reached, a corridor branches, hit
  points change, or a message is printed. Each step is a full turn, so monsters act.
* **Verify** — Run down a corridor and stop at the junction. Run into a room and stop at the
  doorway. Run with a goblin in a side passage and stop when it appears. A spec asserts the stop
  condition for each case on a fixture floor.

### Phase 24 — Floor generation

Everything before this runs on hand-built floors, which is what makes them testable. The
generator comes last because by now it is clear what it has to place.

* **Build** — Rooms and corridors from the seeded RNG. Doors where a corridor meets a room. Up
  and down stairs in different rooms. Rock type varying by region. Items, gold, monsters, bands
  and light sources placed to a density that scales with nothing yet, since there is one floor.
* **Verify** — `--seed N` twice gives the identical floor. A spec generates a thousand seeded
  floors and asserts for each: every floor tile is reachable from the up stairs, both staircases
  exist and are not in the same room, no door is isolated, and no monster or item is inside rock.

### Phase 25 — Start, death, victory

* **Build** — A title screen naming the seed. A death screen with what killed the player, the
  turn count, the level reached and the gold. A victory screen for reaching the down stairs. A
  final inventory listing on both. Restart without leaving the process.
* **Verify** — Play a full game start to finish, twice, on the same seed and on a different one.
  Win once and die once. A spec drives a scripted game to a win and to a death and snapshots both
  screens.

## Feature checklist

Everything asked for in the basic game, against the phase that delivers it.

| Feature | Phase |
|---|---|
| Hit points | 8 |
| Attributes: strength, dexterity, constitution, intelligence, stealth | 8 |
| Character level and experience points | 8, 17 |
| Weapon slots: melee and ranged | 11 |
| Armour slots: shield, body, feet, hands, head | 11 |
| Terrain: three rock walls, stone floor, dirt floor, doors, stairs | 3 |
| Stairs as the exit that wins the game | 6 |
| Items: potions, ammunition, thrown weapons, melee, launchers, armour, scrolls, wands | 9 |
| Item variants: appearance, `+N`, damaged and masterwork, blessed and cursed | 9 |
| Enemy types: slime, goblin, orc | 16 |
| Enemy pathfinding and attack | 17, 19 |
| Detection range against stealth and light | 18 |
| Orc darkvision, goblin without | 18 |
| Enemy inventory and drops | 20 |
| Light sources: sconce, magical room, wand, dropped torch, carried torch | 13, 22 |
| Flicker | 15 |
| Line of sight and lit areas seen at a distance | 12, 13 |
| Movement seen against a light source | 15 |
| Movement: `hjkl`, `yubn`, and running | 5, 23 |
| Pick up and drop | 10 |
| Wield and wear weapons, armour, wands, ammunition | 11 |
| Gold | 10 |
| Mouse hover naming terrain and items | 4, 10 |

## Long-term direction

Not scope, and not a plan. This is what the basic game is a foundation for, written down so the
early decisions in [Architecture](#architecture) have a reason attached to them.

### A world that stays put

* Floors persist in the save file rather than being regenerated. Leaving and returning finds
  what was left.
* Enemies respawn, and a floor is not truly safe until whatever is producing them is found and
  dealt with — hidden spawners, nests, unsealed passages.
* Shortcuts matter, because the alternative is walking the same floors repeatedly. Portals are
  placed by the player, where and when they choose, rather than arriving as a teleport spell.
* The best treasure is not portable: ore seams and resource points that have to be found, cleared
  a path to, and then worked by NPCs recruited in town and escorted back.
* Enemies travel between floors, set up new bases, and lay traps in the direction they expect the
  player to return from.

### Enemies that are actually intelligent

The centre of the project, and the reason for the snapshot-and-action rule and for `Knowledge`.

* A band — clan, tribe, den, pack — shares a mental map of the floor it lives on, and it knows
  that floor better than the player does. Fleeing into unfamiliar ground is a real risk.
* Pack tactics: wolves that flank, cut off a retreat, and do not all close at once.
* Summoners that watch what the player can do and summon against it.
* Kobolds that set traps in advance, and on learning the player has entered the floor, run to
  prepared stations and wait for a trap to fire before engaging.
* Scouts at the edge of a complex that run to raise the alarm rather than fight, and alarm traps
  set to do the same.
* Stealthy trackers that follow at the edge of vision, avoid combat entirely, record what the
  player is capable of, and report it to a leader who plans around it.
* Leaders whose death changes the band's behaviour to something markedly less coordinated.
* Factions, so a goblin can be kited into a room of slimes and shut in, or two monsters shut in
  together.

### Senses told apart

Detection is one reach today. The light on the character raises it, which is what makes standing
in the middle of a lit room or crossing a passage with a torch dangerous. Splitting it is a
change to perception and a change to behaviour together.

* Sight and hearing as separate senses, each with its own reach and its own rules. Light belongs
  to the first and says nothing about the second.
* A light noticed as a thing in its own right rather than only as what makes a creature visible.
  A torch coming up a corridor is a fact about the corridor before it is a fact about whoever is
  carrying it.
* Noticing a light is then a behaviour a species has or does not. A slime round the corner does
  not care that a torch is approaching. A goblin or an orc reads it as somebody arriving and acts
  on that before anything is in sight.
* What such a creature does with it: wait at the mouth of the corridor, move to somewhere it can
  strike from, or fall back and tell the rest of the band.

### Ways of seeing without light

`Species#darkvision?` is one flag on a monster today, and the character has nothing at all. Three
senses replace it, each with its own reach, each carried by the character as well as by a
monster. A creature may have any combination of them and a reach of its own for each.

* **Darkvision.** Every square within reach is treated as dimly lit, which is what the flag
  already does for an orc. Everything a lit square shows is shown: terrain, creatures and items
  alike. The reach is short, and past it the dark is the dark.
* **Low light vision.** Terrain within reach is sensed in the dark, and nothing else. Walls,
  doors, chasms and staircases come through; creatures and items do not. A person with this
  walks a corridor in the dark without a light and without knowing what is standing in it. This
  is close to what `Knowledge#touch` already records, so the shape it writes is settled.
* **Blindsense.** Creatures within reach are sensed in the dark, and nothing else. No terrain,
  no items. The reach is typically much longer than the other two, which makes it the sense that
  answers "something is coming" rather than "here is the room".

Each is a separate reach rather than a rank, because a creature with blindsense and no
darkvision is a different thing to play against than one with both. Drawing has to tell them
apart as well: a creature known only by blindsense is a shape with no name and no detail, the
way a backlit silhouette is drawn now, and terrain known only by low light vision draws the way
remembered terrain draws rather than the way lit terrain does.

### The machinery that needs

* Planning in a `Fiber::ExecutionContext::Parallel`, off the fiber that owns the model and off
  the one that draws, sized by `--threads`.
* Plans that span several turns, each carrying the preconditions it depends on, validated by the
  owner each turn and cancelled when a dependency no longer holds.
* A monster with no plan ready takes a cheap default action rather than stalling the turn, so a
  fleeing player never waits on a planner.

### A place to come back to

* A town floor whose shops and residents are attracted by what the player does and what they are
  worth.
* A house to build out: storage, decorations.
* Reputation, managed partly through travelling bards.
* Pets.

### Depth and systems

* Many floors, with themes driving terrain, inhabitants and loot together.
* Item and character interactions in the spirit of Wazhack.
* Weapon skills, damage types, resistances, status effects.
* Spells beyond wands; cursed and blessed items; enchanting.
* Traps and searching; locked doors; digging, which is where the three rock types stop being only
  a colour.
* Hunger, regeneration, encumbrance.
* Water, lava, and terrain that costs more than one turn to cross.

## Near-term follow-ups

Small things deliberately left out of the basic game, to be picked up once it exists.

* Save and load. The model already serializes; this is the file format, the slot, and the rule
  that a save is removed on load.
* Numpad decoding, once there is a keypad to test it on.
* A full-screen map view for a floor larger than the pane.
* A message history screen.
* Mouse support for targeting and for the inventory, which `CellGrid#cell_at` already allows.
* Glyph and colour themes. `Palette::GROUND` is the first colour one would want to change.
* A flicker that sleeps. The tick runs whether or not anything is burning. It sends no bytes with
  every flame out, but it still lays out and draws the tree seven times a second.
* A status bar that does not need 136 columns. It carries the hit points, armour class, weapon,
  level, experience, gold, turn, five attributes, position and mouse state on one row, and a
  wielded weapon's name pushes the last pairs off a narrower window. The five attributes belong
  in the sidebar, which has room for them and is nearly empty.
* A `--replay` mode that re-runs a recorded key sequence against a seed, which would make every
  bug report reproducible.
* Move each of the five general-purpose pieces to `termbuf-widgets.cr` once settled, with the
  specs written here.
