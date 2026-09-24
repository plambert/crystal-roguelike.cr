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
| Pursuit | One `Descent` per band per turn, flooded over the band's own `Knowledge`. Its members step to a neighbour nearer the goal |
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
| A scattered ranged weapon | Lands with ammunition it fires within three squares, most of the time |
| The supply's stream | Named by the weapon's square, never the litter's own, so adding the rule moved nothing else on the floor |
| Reading in the dark | Refused. A scroll is words on paper. The scroll is not spent and no turn is taken finding that out |
| A shape against light | Drawn by `Species::Size`, in one colour for every species. A letter names a species and a shape names none |
| Shooting at a shape | Allowed. `Tab` walks it and a bolt, an arrow or a rock flies at it. Seeing something move is enough to aim |
| Glyphs for a shape | `∙`, `▪` and `◼`. No letters, and none East Asian Ambiguous: a two-cell glyph would tear the map's grid |
| A shape wavers | With the flame lighting the square behind it, not with its own square. Its own square has no light on it |
| How far it wavers | One step up from the dimmest lit step, and never below it. A shape drawn dimmer than that reads as a memory |
| Readying an item | The message follows the slot. A sword is held, a helmet is worn, and arrows go in the quiver |
| Running | `Game#run` takes whole turns, so creatures act between steps. It never swings and never opens a door |
| Digging a floor | Binary space partition. Joining the two halves of every cut is what leaves every square reachable |
| A generated door | Where a corridor crosses the ring one square outside a room, and only with a wall on each side of it |
| Where a run starts | The room with the up staircase holds no creature |
| What stops a run | The run ending, a wound, a creature coming into sight, a message, a door underfoot, or a junction |
| What counts as a corridor | Two cardinal ways off a square, facing each other. A room corner has two at right angles |
| Naming a bow's slot | "Ranged weapon", never "launcher". `ItemClass::RangedWeapon` and `Player#ranged_weapon` say the same |

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

The constraint that follows, and an expensive one to discover late: **nothing in the model holds
a `Proc` or a closure**. Behaviour is named — an enum, a symbol, a registry key — and
looked up. A monster's attack pattern, an item's effect and a trap's trigger are all identifiers,
not blocks.

Save and load themselves are future work. Serializability is not.

### Belief is modelled apart from truth

What is on a floor and what somebody thinks is on a floor are two different things, and what a
creature does follows from the second. So there is a `Knowledge` type from the first moment
anything needs to remember a floor: terrain seen, where things were when last seen,
where somebody was last known to be, and how stale each of those is.

The player's remembered map in Phase 14 is the same type a monster band uses in Phase 19. It is
written once, for the player, and reused.

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
| `Inherited` | The band's knowledge seeds a new member's own, and the two go their own ways after that. Most bands. |
| `Hive` | What one member sees, the band and every other member know in the same turn. |
| `Called` | Each member keeps its own and passes it to whichever members are near enough to be told. |

`Knowledge#sightings` is where each creature was last seen, by who, with the turn. A monster goes
to where it saw the character rather than to where the character is. `Knowledge#copy` is what
`Inherited` hands a new member.

The fields are in place from Phase 16. Nothing reads them until Phase 19.

## Keybindings

Settled in Phase 5 and extended as each phase adds a verb. All of it goes through `Keymap`, so
none of it is fixed and a preset can rebind the lot.

| Key | Does |
|---|---|
| `h` `j` `k` `l` | Move west, south, north, east |
| `y` `u` `b` `n` | Move northwest, northeast, southwest, southeast |
| `G` + direction | Run that way until something stops the run |
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

Six pieces are general-purpose rather than roguelike-specific. They are built here first, in
`src/roguelike/termbuf_ext/`, with their own specs and no dependency on game types, and moved to
`termbuf-widgets.cr` once their shape has settled. Each keeps a `# Extraction candidate:` comment
naming what still has to be decided before it moves.

| Piece | Built in | What it is |
|---|---|---|
| `Cells(T)` and `CellGrid(T)` | Phase 2 | A 2D addressable grid widget with a camera |
| `Prompt` | Phase 6 | `[yn]` answered by one keystroke, in a modal overlay |
| `Entry` | Saves | A question with one line typed into it, in a modal overlay |
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

  What it holds is written again on every refresh, through `Examiner#restate`. It used to be
  written only when the pointer or the cursor landed on a square, so everything on that square
  could change without the readout hearing: a creature killed, an item picked up, a door opened.
  The pointer is over a cell of the screen rather than over a square of the floor, so a refresh
  also points it at whatever the camera has slid under the pointer since. The keyboard cursor is
  exempt from that second part: it is held to a square, and `Examiner#move` brings that square into
  view rather than letting the camera carry it off.

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
  block. The camera follows with a dead zone via `CellGrid#reveal`, sized in "Where the camera lets
  the character get to" below. A turn counter that advances on a move and not on a blocked one.
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
  costs nothing and a square holds one creature; a monster carries its own position as well, and
  `Floor#walk` is the only method that moves a monster, so it writes both. Each is in a `Band` of
  one, and the band carries the `Faction`, because adding either to a serialized type later means
  migrating save files. A creature on a lit square draws in its own colour; one on an unlit square
  with light behind it draws as a shape at the dimmest lit step, which is Phase 15's silhouette
  rule applied to the first creatures there are. Nothing is remembered: a monster is drawn where
  it is or not at all, until Phase 19 gives `Memory` a creature.

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
  standing on an unlit square is not noticed at all, however close. Putting a torch out is then
  worth doing, and the awake check in `Game#creatures_act` has cases where it fires. Being hit
  wakes a band whatever the light, which is `Game#wake` rather than a rule in `Notice`.

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
  and it writes the Phase 4 readout with one row added. `f` and `t` put
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
  proving ground's magically lit room already is, so a zapped room is stored the way a built one
  is and the light survives a save file. Only the passable squares are set. A glowing square
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
* **Done.** `Game#run` walks one direction a step at a time and answers a `Running`: how far it
  went and a `Halt` saying what stopped it. Every step is a whole turn, so the creatures on the
  floor act between one step and the next and a run is as dangerous as walking the same squares
  one key at a time. A run makes no decisions: it stops in front of a creature and in front of a
  shut door rather than swinging or opening, and a run that takes no step at all writes the same
  refusal one press of the movement key would have written.

  The eight `Halt` members are the stop conditions, and `Game#stopped_by` asks about them in the
  order a person would name them: the run ended, the character was hurt, a creature came into
  sight, something was written to the log, the character stepped onto a door, the square has more
  ways off it than the corridor behind it. A creature usually writes the message that would have
  stopped the run on the same step, so the creature is asked about first.

  `Game#corridor?` is the branch rule: a square is a length of corridor when two of its four
  cardinal neighbours can be walked onto and the two face each other. The corner of a room has
  two neighbours as well, at right angles, and counting that would stop a run along a room wall
  on its first step. Diagonals are not counted, because two squares touching at a corner are not
  a way between rooms and counting them would read every bend in a corridor as a junction.

  `G` waits for a direction and the next movement key runs. Nothing is lit up while it waits:
  `o` and `c` light the doors they would act on, and every direction is an answer to `G`. The
  whole run happens inside the one key press and the screen is drawn once at the end, because
  `Ui::Play` holds no terminal and cannot send a frame partway through a handler.
  `spec/fixtures/running/ground.txt` holds where a run stops from every square of a small floor
  in each of the four directions, so a change to any of the rules shows as a diff of two maps.

  `.` is the other half of that. `Game#wait` spends one turn and moves nobody, so everything else
  on the floor acts and the character does not. A person waits to let something come to them
  rather than walking into it. A run that is over takes no turn: nothing acts after the character
  has died. A command already waiting for a direction takes the key back instead, the way a
  movement key does.

### Phase 24 — Floor generation

Everything before this runs on hand-built floors, so every spec can name the squares it asserts
on. The generator comes last because by now it is clear what it has to place.

* **Build** — Rooms and corridors from the seeded RNG. Doors where a corridor meets a room. Up
  and down stairs in different rooms. Rock type varying by region. Items, gold, monsters, bands
  and light sources placed to a density that scales with nothing yet, since there is one floor.
* **Verify** — `--seed N` twice gives the identical floor. A spec generates a thousand seeded
  floors and asserts for each: every floor tile is reachable from the up stairs, both staircases
  exist and are not in the same room, no door is isolated, and no monster or item is inside rock.
* **Done.** `Generator` cuts a floor by binary space partition. The whole floor starts as one
  rectangle of solid rock, each rectangle is cut in two until it is no larger than `ROOMY`, a room
  is carved in each of the smallest rectangles, and the two halves of every cut are joined by a
  corridor of two straight lengths meeting at a right angle. Joining at every cut is what makes
  every square reachable from every other: the rooms form a tree, and a tree has a path between
  any two of its leaves. No repair pass walks the floor looking for what was left stranded.

  Cutting to a rectangle size rather than to a fixed depth is what lets the floor grow without the
  rooms growing with it. A floor twice as wide holds twice as many rooms of the same size.

  A room keeps a square of rock between itself and the edge of its rectangle, so two rooms never
  touch. Each rectangle takes its own rock, so what a wall is made of changes from one part of
  the floor to another. A door goes where a corridor crosses the ring of squares one outside a
  room, and only where that square has exactly two ways off it facing each other: a door needs a
  wall on each side to hang from. A square inside another room, and one with a door already
  beside it, take no door.

  The room with the up staircase gets no creature. A character who arrives standing next to a
  goblin has been given no turn to decide anything.

  Every roll is on a stream named after the rectangle or the room it is about, never on one
  shared stream walked in order. Adding a roll in one place moves nothing elsewhere: a second
  sconce in one room shifts that room's lights and leaves every other room where it was.

  `Game.dug` plays a floor the generator cut and `Game.start` plays the floor that ships, which
  is what every spec about a named square still reads. `--no-generate` plays the shipped floor.

  A floor is 216 by 84 squares. A dug one holds about 175 rooms of about 35 squares each, 7000
  squares of open ground, 108 creatures, 264 doors, 161 sconces and 200 things to pick up. The
  window shows about a fortieth of it at once.

  `Game::LITTER` is a rate rather than a count: items per hundred squares of open floor. So how
  far a person walks between two things they can pick up does not change with the size of the
  floor. Creatures are already per room and scale the same way.

  A run asked for the field of view twice a step, and on a floor this size that was most of what a
  step cost. `Game#run` works it out once and passes it to `Game#monsters_in_sight`.

### Phase 25 — Start, death, victory

* **Build** — A title screen naming the seed. A death screen with what killed the player, the
  turn count, the level reached and the gold. A victory screen for reaching the down stairs. A
  final inventory listing on both. Restart without leaving the process.
* **Verify** — Play a full game start to finish, twice, on the same seed and on a different one.
  Win once and die once. A spec drives a scripted game to a win and to a death and snapshots both
  screens.
* **Done.** `Ui::Placard` is a box of lines answered by one keystroke. `Widgets::Prompt` asks a
  question on one row, and both of the screens this phase adds are several rows of text with the
  same one-keystroke answer under them. `Ui::Placards` holds the wording of both, so there is one
  place to read what a person is told at the start and at the end of a run.

  The title screen names the seed. `p` plays and `q` quits, and `Enter` plays. It goes up after the
  first layout, over the map, so a person who has just started a run sees the floor they are about
  to walk behind it.

  One screen ends a run, whichever way it ended, and the heading is what tells the three apart: You
  win, You died, You left the dungeon. Under it go what ended the run, the turn, the level and the
  experience, the gold, what the character was carrying, and the seed. `Game#killer` is new and
  holds the label of what killed the character, so the screen says "Killed by an orc" rather than
  "You die". The label is kept rather than the creature, which is still standing on the floor.

  The pack is listed through `Lore#revealed`, a copy of the run's lore that knows every kind. A
  person who died holding a potion they never drank is told it was a potion of healing. The run is
  over and there is nothing left for them to find out.

  `y` on that screen starts another run and `n` quits, with `n` on `Enter`: a person pressing
  `Enter` to get a screen out of the way is not asking to start a whole new run. `Session.open`
  takes the seed rather than a generator and builds a fresh `Session` for each run, so another run
  costs a new `Game`, a new `Ui::Play` and a new `Widgets::App` over the terminal that is already
  open. A seed named on the command line is replayed every round and a run started without one
  gets a fresh seed each round, so `--seed N` goes on reproducing N. The line printed after the
  terminal is handed back names the last run's seed, which is the one to pass to `--seed` to play
  it again.

  `spec/fixtures/screens/` holds the title screen, the death screen and the victory screen drawn
  out, so a change to any of the wording shows as a diff of three screens.

## Development tools

Not phases. These are for working on the game rather than for playing it, and they are built when
they are needed rather than in the sequence above.

### The debug console

`--debug-console` builds a box that opens on `` ` `` and runs typed commands against the game that
is running. Without the flag nothing is built: there is no box in the widget tree and the key is
not bound, so a normal run cannot reach any of it.

The flag itself is hidden. It is in neither `--help` nor the shell completions, because whoever
plays the game has no use for it. `hidden: true` takes it out of the help; the completion
candidates are generated from the same declarations and do not read that yet, so `Cli` filters its
own spellings out afterwards.

The box opens with `version X build Y` on its first line. `Y` is the short commit the binary was
built from, with a `+` after it when a tracked file differed from that commit. `script/build-id`
answers it and `src/crystal-roguelike.cr` runs that while the compiler expands its macros, beside
the `shards version` call that fills `VERSION`. A build from a release tarball has no repository to
ask and gets `unknown`. Untracked files are not counted: nothing untracked reaches the binary
unless a tracked file was edited to require it, and counting them would mark every working tree
that has a stray note in it. The compiler caches macro expansion, so a rebuild that changes no
source carries the stamp the last full build wrote.

The reason for it is the cost of finding the thing to test. Firing a bow needs a bow and arrows to
turn up on the floor, and a seed that drops them there drops something else after the next change
to the generator. `spawn bow` and `spawn 20 +1 arrow` take two lines instead of twenty minutes of
walking.

The commands are `help`, `heal`, `hurt`, `spawn`, `identify`, `remove-curse`, `kill`, `inspect`,
`goto`, `reveal` and `light`. `help` lists them with what each one takes.

Two rules hold for all of them.

* A command takes no turn. Nothing else on the floor acts, so setting a test up does not change
  what is being tested.
* A command rolls nothing. No command touches an `Rng`, so `--seed N` plays out the same way
  whether or not the box was opened. `spawn` therefore takes the enchantment, the condition and
  the blessing from what was typed rather than from `Items.make`, which rolls: `spawn bow` makes a
  plain uncursed `+0` bow every time.

`Debug::Console` holds the commands and everything they do, and owns no widget and no terminal, so
a spec runs a command against a `Game` without drawing anything. `Ui::ConsolePane` is the box: it
takes what was typed, hands it over, and puts what came back on the screen. `Debug.item` turns
words into an item, and matches a kind by its own label, by its member name, or by the starts of
the words of its label, so `mwk sh sword` and `pot heal` each name one thing. Words that could
name more than one thing make nothing and say what they could have meant.

### The trial harness

`--trial N` plays N games with a bot and prints how they went. No terminal is opened and nothing
is drawn. `--trial-turns` caps one run and `--seed` names the first seed, so two builds are
compared over the same dungeons.

It is an instrument for tuning rather than a way to play. `Trial::Bot` plays badly and plays the
same way every time: it takes the staircase down when it is standing on one, drinks when badly
hurt, swings at whatever is next to it, picks up what is underfoot and holds the heaviest hitting
weapon it is carrying, and otherwise steps to a neighbour it has not stood on. It never retreats,
never shuts a door behind it, never shoots and never puts its torch out, which are the four things
that keep a person alive. So the numbers are the pessimistic end of what the game is.

The size of a number here means little on its own. The difference between two sets of runs is what
to read, and the seeds have to be the same in both.

## Balance

What the numbers are set to, and what was measured to set them. A change here is made against
`--trial` over the same seeds, before and after, and both readings go in this section.

### The level one curve

A character starts at level one with twelve hit points, a short sword and leather armour, all
readied, plus a lit torch. Turns to kill against turns to die, at average attributes:

| | slime | goblin | orc |
|---|---|---|---|
| level 1 | 3.1 / 16.0 wins well | 5.7 / 6.9 wins narrowly | 11.4 / 5.9 loses |
| level 3 | 3.1 / 26.7 wins well | 5.7 / 11.4 wins well | 11.4 / 9.9 loses |

That shape is deliberate. A slime is safe, a goblin is a fight worth picking, and an orc is
something to walk away from until a better weapon turns up. A long sword at level three beats an
orc narrowly, so the answer to an orc is what is lying on the floor rather than another level.

It did not start there. At eight hit points with bare hands, a level one character needed 13.3
turns to kill a goblin and died in 3.8, and lost to all three species with the best common weapon.
Goblins are 45 out of 100 of what is on a floor, so every fight was a loss and there was no way to
reach level two. The bot reached level two in 1% of two hundred runs.

Two hundred runs of at most 1500 turns from seed 5000, before and after:

| | eight hit points, bare hands | twelve, short sword and leather |
|---|---|---|
| died | 87% | 79% |
| turns until death, median | 67 | 96 |
| squares from the start, median | 13 | 17 |
| level reached, best | 2 | 3 |
| gold, mean | 11.5 | 18.3 |
| killed by | goblin 114, orc 33, slime 27 | goblin 104, orc 47, slime 8 |

Slime deaths fell from 27 to 8, which is the change asked for. Orc deaths rose from 33 to 47
because the bot now lives long enough to meet one. The death rate is still high because the bot
never retreats; see the note on what `Trial::Bot` does not do.

### How often a floor curses what it hands out

Two tables decide this. `Items::BLESSINGS` says how often a curse lands at all, and
`Items::ENCHANTMENTS` says how often an item nobody has touched carries a minus. A cursed item
rolls its plus on `Items::CURSED_ENCHANTMENTS` instead, which is where most of the minuses come
from.

Both were halved. `Blessing::Cursed` went from 10 to 5 against the other two, and the `-1` entry in
`ENCHANTMENTS` went from 6 to 3. Five hundred thousand rolls of `Items.random`, before and after:

| | before | after |
|---|---|---|
| items carrying a curse | 10.0 out of 100 | 5.0 out of 100 |
| enchantable items carrying a minus | 11.8 out of 100 | 6.1 out of 100 |

Two hundred runs of at most 1500 turns from seed 5000 read the same either way, which is what was
expected. The bot dies to the first goblin it cannot beat, and that fight is decided by what it
started with rather than by what it found.

| | before | after |
|---|---|---|
| died | 77% | 77% |
| turns until death, median | 96 | 97 |
| squares from the start, median | 18 | 18 |
| gold, mean | 19.9 | 21.1 |
| killed by | goblin 103, orc 47, slime 5 | goblin 94, orc 53, slime 7 |

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
| Items: potions, ammunition, thrown weapons, melee, ranged weapons, armour, scrolls, wands | 9 |
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
  A creature would notice a torch coming up a corridor without yet knowing who carries it.
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
  the drawing fiber, sized by `--threads`.
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

* Numpad decoding, once there is a keypad to test it on.
* A full-screen map view for a floor larger than the pane.
* A message history screen.
* Mouse support for targeting and for the inventory, which `CellGrid#cell_at` already allows.
* Glyph and colour themes. `Palette::GROUND` is the first colour one would want to change.
* A flicker that sleeps. The tick runs whether or not anything is burning. It sends no bytes with
  every flame out, but it still lays out and draws the tree seven times a second.
* A `--replay` mode that re-runs a recorded key sequence against a seed, which would make every
  bug report reproducible.
* Move each of the five general-purpose pieces to `termbuf-widgets.cr` once settled, with the
  specs written here.

## The sidebar

Everything a person reads every turn is in one column on the right. There was a status row along
the foot of the screen; it needed 150 columns to show every pair and cut the last of them on
anything narrower. The map has that row back.

`Ui::CharacterPane` stacks the level, the bars, the numbers that are not on a bar, the five scores,
what is readied and what is in the pack. `Ui::NearbyPane` and `Ui::ExaminePane` sit under it, so
the block that is read every turn is the one that never moves.

`Ui::Meter` is one bar with the count inside it rather than beside it, which is one row instead of
two. The fill runs from green through to red as it empties, mixed between the five levels in
`Palette::HEALTH` rather than stepping at each one. Magic runs the same levels but ends at light
orange: running out of magic is not the same as running out of blood, and the red is worth keeping
for the one bar that means the run is about to end. The experience bar is one colour however full
it is, because a bar that changes colour says something is wrong and nothing is wrong with being
early in a level. Whether a bar shades or steps should be a person's own choice, and the levels are
written down either way.

`Ui::Naming.short` writes an item for a column: no article, the count in front, the noun singular,
and every word shortened rather than left out, so `bls mwk +1 chain` is still four separate facts.
A name too long for the column is cut and marked. The whole name belongs in a tooltip.

`Ui::Line` is one row written at columns the caller picks, which is what keeps the numbers under
each other. It is a fixed row rather than a `Widgets::Label` because the layout squeezes a label to
nothing before it squeezes a row of fixed height, and a heading that vanishes under pressure leaves
a rule over a list of nothing in particular.

An empty equipment slot is drawn dimmed rather than left out, so a person learns which row the
weapon is on instead of reading the labels. The pack is shut to begin with, because it is ten rows
and the readouts under it want them.

`CharacterPane#fit` decides what to show in the rows it is given, in the order a person would give
things up: an open pack shuts, then the empty slots go, then the scores, then the pack heading,
then the equipment. The level and the bars never go. At the shortest terminal the game runs in, the
three readouts still keep a heading, a rule and one row each.

### Pointing at the sidebar

`Ui::Line` takes the pointer. A row says what it is about when the pointer crosses it, and
`Ui::Play#pointed` decides what to do with that once the event has been through the whole tree. A
press is claimed so that a click on the sidebar is not also a click on the map; the pointer moving
is not claimed, because whatever tracks where the pointer is has to hear about every report.

`Ui::Tooltip` hangs to the left of the row, over the map, so a person reading it can still see the
row they are pointing at. It takes neither the keyboard nor the pointer: a pointer that crossed it
could never reach the row under it, and the two would take turns. `Ui::Detail` writes what goes in
it — the slot written out, the whole name, and what the character knows about the item. An
unidentified potion is named by its colour and nothing is said about what drinking it would do.

The triangle on the pack heading opens and shuts the pack when it is pressed.

### Pointing at a menu

Every menu that lists carried items hangs the same box off the row the highlight is on: `i`, `d`,
`w`, `W`, `T`, `q`, `r`, `z`, `a`, `,` and the second question a scroll of identify asks. The box
is up the moment the menu is, because the highlight is always on a row. The arrows move it and so
does the pointer crossing a row, so a person reading the list with either one reads the same thing.

`Widgets::Menu::Content` works out which row the pointer is on from how far down the list the
report landed, because a menu row is not a widget and there is nothing under the pointer to ask. A
wheel notch reports as well as a keystroke does: the row did not change but where it is on the
screen did, and the box has to follow it.

The box is painted a layer above a dialog. A box under the menu it belongs to would be covered by
the menu, and dimmed by the wash the menu puts over everything painted below it.

It is sized when the layout asks rather than when it goes up. Where it may sit depends on where the
row it hangs off ends up, and a menu that has only just opened has not been laid out yet. A menu
with a box beside it also leaves twenty columns clear on each side rather than ten, so that there
is somewhere for the box to go on an eighty column terminal. A wide screen never reaches that: the
menu is as wide as its rows and no wider.

## How a creature comes at you

### The angle it comes from

`Descent#toward` used to take the first neighbour, in the order the directions happen to be
declared, that was nearer the goal than the square the creature stood on. A diagonal step costs what
a straight one does, so three or more neighbours are usually the same distance nearer and the
declaration order decided between them. That gave a creature a diagonal leg followed by a straight
one: the same number of turns as a line, and it read as a creature walking at forty-five degrees to
wherever it was going.

`Descent#downhill` now answers every neighbour that is as near as any is, and `Descent.nearest`
picks between them by which one heads most nearly along the line from the creature to the goal.
`Line.step` gives that line, which is Bresenham and is the line an arrow and a thrown dagger already
follow. The diagonal steps are spread along the way instead of taken at one end, so a creature
crosses the ground the way a missile does.

A species that does not path had the same fault for a different reason: it stepped by the sign of
the difference, which is a pure diagonal until one axis lines up. `Pursuit.straight` walks the line
instead.

### Putting a foot wrong

`Species#clumsiness` is how often a creature steps somewhere other than the best square, as a
percentage. It falls as intelligence rises: a slime blunders 15 percent of its steps, a goblin 11
and an orc 8. `Game#stumbles?` rolls it on a `wander` stream of its own with its own counter, so how
many creatures are on the floor and how often they trip changes nothing about what a swing rolls.
`Pursuit` rolls nothing; `Snapshot#stumble` arrives already decided.

A creature putting a foot wrong steps sideways rather than nearer, so what it is chasing gains a
square. `Descent#sideways` answers the neighbours that are neither nearer nor further. There are
none of those in a corridor, and a creature in one walks on properly: nothing is shaken off in a
corridor. A species that does not path has no map to step sideways on and loses the turn instead.

Over forty steps of running away across open ground, that opens a gap of about five squares from a
goblin and four from an orc. That is what makes breaking the line of sight possible in the first
place.

A creature already beside the character still swings. What is being modelled is finding the way, not
fighting.

### Whether it gives up

`Species#persistence` is how many turns a creature goes on looking after it has lost the character:
slime 4, goblin 6, orc 30. `Game#patience` takes the most persistent member of the band, and
`Game::PATIENCE` is only what is left for a band with nobody on the floor to ask.

This is not read off intelligence. Three points of intelligence separate a goblin from an orc and
five times as much patience separates them as well; neither number follows from the other. A goblin
is quick and scatterbrained and gives up; an orc keeps its footing and will not let go. Persistence
is what decides whether a person can run away, and an orc follows a cold trail five times as long as
a goblin.

## Where the camera lets the character get to

The character walks about a box in the middle of the window and the camera holds still. The camera
moves once they reach the edge of that box, and stops once it has run out of floor to scroll onto,
so a character in a corner of the floor stands in a corner of the window. How much blank there is
beyond the edge of the floor is one of the things a roguelike leaks about where you are.

`MapPane#box` is a percentage of the window on each axis rather than a count of cells, and starts
at 50. `MapPane#margin` turns it into the cells kept clear on one side, which is half of whatever
the box leaves over. In a 95 by 35 map pane that is 24 columns and 9 rows, so the character crosses
23 squares from the middle before the camera moves.

A count of cells cannot do this job, and the six cells it used to be were the bug. Six cells is
most of the height of a short terminal and a sliver of a tall one, so the same number gave two
windows two different games; on a wide terminal the character reached the edge of the window before
anything scrolled.

`CellGrid#reveal` therefore takes a margin per axis. A window is much wider than it is tall and a
cell is about twice as tall as it is wide, so the two axes never want the same count. A margin at
least half its axis leaves no position that satisfies it, and that axis centres instead.

The examine cursor is followed the same way. Reading the map from the keyboard wants the same
context around the cursor that walking wants around the character.

## Saved characters

One character is one file, under `$XDG_STATE_HOME/roguelike` when that variable is set and
absolute, and `~/.local/state/roguelike` when it is not. There are three directories under it:
`saves/` holds the characters still being played, `deaths/` the ones who died, and `wins/` the ones
who came out alive. `--saves` prints all three, and whatever is in them.

### What a file holds

The whole `Game` as pretty-printed JSON, under a header naming the character, the build that wrote
it, when it was written, and how far they had got. The header comes first in the file, so `head` on
one says whose it is without reading the rest. One floor is about 270 kilobytes.

Nothing in the file is checked and nothing in it is a secret. A person who wants to edit their
character opens the file and edits it.

Three other ways of saving were weighed. A seed with the list of commands replayed against it makes
a file of a few kilobytes, but every change to a roll, a probability, a domain name or the monster
AI invalidates every save, and this repository changes those numbers constantly. It also costs
about 1.4 milliseconds a turn to load, so the load gets slower the further a run gets. A checkpoint
with the commands since it bounds that cost but inherits the same skew, and buys nothing, because
reading a whole game is already about 1.3 milliseconds. A command log written beside the state file
is still worth having later, for a replay viewer and for running the trial harness over real games
rather than bot games; it is not built.

### When it is written

On the way down a staircase, on the way out of the dungeon, when the run ends, and when the person
quits. Not on every turn: writing costs about a millisecond and a whole file, and a turn is worth
less than that.

A run that is over is written and then retired: the file moves out of `saves/` and takes the time
it ended with it, so `Sparky.json` becomes `Sparky-20260915-234500.json`. One name can end many
times and every ending is kept; a second ending in the same second takes a count as well.

`Save::Store#ended` says which directory it goes to. A character who died goes among the deaths.
Everyone else goes among the wins: a character who climbed down and out won, and one who climbed
back out the way they came in is alive, which is the thing the two directories tell apart.

The name is free once that happens. A person whose character died starts again under the same name,
and the run that ended is still on disk for them to read. Leaving a finished run in `saves/` would
hold a name nobody can play and offer a game that opens on its own ending screen.

A run that ends on a staircase reaches `#keep` twice, once from the command that ended it and once
from the screen that reports it. `Ui::Play` writes it out once, or two endings would be on disk for
one death.

The file is written beside itself and renamed over the old one, so a crash partway through leaves
the last good save where it was rather than half of a new one. A store that will not take the file
says so in the log and the run goes on. Losing the turn a person is playing because a disk is full
is worse than losing the save.

`Ui::Play` holds a `Save::Store` or holds none. A store is the three directories rather than one of
them, so `Save::Store.under` is what builds one. A spec drives one on a temporary directory, so
nothing a spec does can reach a person's own saved characters. `--no-save` plays without one.

### The name

`Player#name` is what the character is called, as it was typed. The file is named after
`Save.slug` of it: a letter, a digit, a dash, an underscore and a dot survive, every other
character becomes one dash, and a run of dashes becomes one. Letters keep their case and keep their
accents, so `Gúnther the 👹` is kept in the file and the file is called `Gúnther-the.json`.

This is not about what a filesystem allows, which is almost anything. It is about a name a person
can type at a shell without quoting it, and one that cannot be mistaken for a path.

Two names can therefore make one file name. A name whose save belongs to somebody else is refused,
and the question goes back up saying who is in the way, so a person who meant to carry that
character on can see how their name is spelled. Nobody types a new character's name expecting to
lose an old character. A file that will not parse counts as taken as well: a file nobody can read
is still a file a new run must not write over. A name with nothing usable in it is refused the same
way.

Only `saves/` is consulted. An ended character holds no name.

### Asking who is playing

The title screen lists whatever is in the store, so a person can see which names are taken before
they answer. `p` then asks the name through `Widgets::Entry`, a modal box with one line typed into
it. The character's own name carries them on, and the floor that was dug for the run is thrown
away. Any other name starts that run under that name, and writes it at once, so a character
exists from the moment they are named. `Escape` puts the title screen back: a person who is not
sure what to type has not decided to play.

`--character NAME` answers both screens from the command line.

`Ui::Play#resume` swaps one game for another. Everything drawn is built from the game on each
refresh, so no pane is rebuilt; what is reset is the state belonging to no game, which is a command
waiting for a direction, a shot being aimed, and whether the screen a run ends with has been put up.

### The first row of the sidebar

`Sparky             Lv 1`. The name is written from the left and the level against the right edge,
through `Ui::Line#put_right`. A right piece is placed when the row is drawn, because where it lands
depends on how wide the row turned out. A left piece is cut one cell short of it and marked, so a
long name gives way to the level rather than pushing it off the row. A character nobody has named
yet reads as a dash.

## What a scroll of magic mapping tells you

The walls, and nothing else. A square is written down when it is rock with something walkable
beside it, so the rooms and the corridors come through as outlines and their floors stay unknown
until somebody walks them.

It used to write down every square on the floor. That made a map that had been read
indistinguishable from a floor that had been walked, which is the one thing a map should not do.
The rock behind the walls is left out too: deep rock is not a wall, and writing it down would draw
the whole floor in one colour.

## The rest of the scrolls

Six more, each doing three things depending on what has touched it.

### Treasure detection

Writes down where every pile of gold on the floor is. Blessed, it brings the lot to the
character's feet instead. Cursed, it ruins half of what it finds, leaving one coin of each ruined
pile behind and saying how much went; what survives is written down like the rest.

### Item detection

Writes down what is lying inside an oval round the character. The oval is `DETECTION_SPAN` of the
floor across and the same share of it down, so it reaches half that far from the character in each
direction. An oval rather than a circle, because a floor is wider than it is tall
and a circle on one reaches the top and bottom edges while leaving the sides alone. Blessed, it
reaches the whole floor. Cursed, it destroys `DETECTION_RUIN` of what it found, rounded up, so it
always destroys something.

Gold is left out. A scroll of treasure detection is what finds that, and a scroll that found both
would make one of the two pointless.

The list names what it destroyed first, in full, and marks it destroyed. A thing that no longer
exists has no secret left to keep. Naming it teaches nothing: `Lore` is not told, so the colour
that kind comes in still means nothing for the rest of the run. `Lore#name` takes an `identified`
argument for exactly this. The rest are named as the character already knows them, nearest first —
nothing in the game has a price yet, so distance is what orders them.

### Darkness

Puts out every sconce, every burning item on the floor and everything the character is carrying
within `DARKNESS`, and takes the glow off those squares. Cursed, it destroys what it puts out
rather than dousing it, and takes the sconces off the walls; a blessing on a carried thing saves
it, and nothing saves what is lying on the floor, because a blessing holds a thing to its owner and
a thing on the floor has none.

Blessed, it survives being read `DARKNESS_KEPT` times in a hundred. It is the only scroll that
does. `Game#use` has already taken it out of the pack, so `#keep_scroll` puts it back.

### Blindness

Blinds the creature it is aimed at. Cursed, it blinds the reader for `BLINDING`. Blessed, it blinds
every creature in sight.

`Player#blinded` and `Monster#blinded` count the turns down, and `Game#blink` passes one of them
each turn. A blind character's `Game#sight` is `Vision.blind`, which holds their own square and
nothing else, so nothing is in line and nothing shows as a shape against a light behind it either.
A blind creature is skipped by `#noticing`, so its band never hears the character.

The character is told when their sight comes back. A creature is not: the character has no way to
tell one that is blind from one that is looking elsewhere.

### Minor teleport

Puts the character on a random square at least `TELEPORT_LEAST` away. Blessed, it puts them where
they said. Cursed, it puts them beside whatever on the floor is worth the most experience, or does
nothing at all when the floor is empty.

### Repair

Takes the damage out of one carried item, leaving it plain rather than better than plain. Mending
undoes wear; it does not make a smith out of the reader, so a masterwork piece is left as it is.

The list offered holds only what is damaged. A condition is written into an item's name, so that is
a list the character can already read off their own pack, and a scroll spent on something whole
would be spent on nothing.

Blessed, it mends everything carried and everything lying on the character's own square, which is
what `Game#within` already answers for a blessed scroll. Cursed, it breaks something whole instead,
picked from what a condition means anything on. A wand is left out of that: the only way a wand is
damaged at all is a cursed one cracking in the hand, and that crack is the way out of the curse.

A letter is mended or broken whole. A stack holds what looks alike, and one arrow of twelve going
dull is not something the character could point at.

### Reading and then aiming

A scroll of blindness and a blessed scroll of minor teleport both want a square, and neither
question can be asked before the scroll is read: what the scroll does depends on the blessing, and
reading it is how the character finds that out.

So `Game#start_aiming_read` spends the scroll and the turn, `Play` puts the targeting cursor up,
and `Game#aim_reading` does the rest with no second turn. It is the shape `#start_reading` and
`#finish_reading` already had for a scroll of blessing, and `Game` holds nothing between the two
calls either way.

Backing out of the aim does what the scroll does with nothing to aim at, which says so. The scroll
is spent whichever way it goes, and being told it found nothing beats losing it in silence.

## Gold underfoot

Stepping onto a square with gold on it puts the gold in the purse. `Game#arrived` does it, before
it describes what is left lying there, and the step onto the square is the turn. Gold is counted
rather than carried, so there is no pack to fill and no way for it to refuse.

Everything else on the square stays where it is and is still picked up with `,`.

A run stops on the line this writes, the same as it stops on "You see a dagger here." Anything
written to the log stops a run, and what is underfoot is what a run is for noticing.

## Ammunition underfoot

The same, for what the readied quiver holds. An arrow fired at something and then walked past is
the whole reason for it.

Only what would sit under the quiver's own letter is taken, which `Item#looks_like?` decides. A `+1`
arrow beside a plain one reads differently in the pack, and taking it would move the quiver's letter
to a stack the character never asked for. A character with an empty quiver picks up nothing.

## Reading the messages again

The log pane is four rows. Three things now keep a message from going past unread.

`Widgets::Pager` holds at a page boundary and writes `--More--` on the last row, which it already
did. A turn that says twelve things shows three at a time and takes any key for the next page.

The wheel scrolls the pane back over what has already been read. `Pager` is a `Scrolls` now, so the
notch is the one the rest of the widgets answer, and `#back` is how many lines above the newest the
window sits. A held page is not scrolled: what is showing then has not been read, and moving it is
how a line goes unread. A notch down while it holds shows the next page, because that is what the
marker is asking for.

The window goes back to the newest line when a line arrives, and when the turn moves on. A pane left
where it was scrolled to would quietly go stale, and a character who has walked three squares is not
reading about the room they left.

`Ctrl+P` puts every message of the run in a box. It is `Ui::HistoryPane`, a `VirtualList` over the
log wrapped to the box, opened on the newest message and scrolled with the arrows, `jk`, the page
keys, the space bar, `Home`, `End` and the wheel. `Escape`, `q` and `Ctrl+P` close it. The lines are
wrapped rather than cut: a message longer than the box is a message with its end missing.

The box is filled from the log each time it opens, so it holds no copy of anything between one
opening and the next.

## The title screen

It is a menu. The first row starts a new character, which is what `Enter` takes. Every row after it
is a saved character to carry on, most recently played first, which is the order `Store#characters`
already answers in. The last row leaves, and so does `Escape`.

The two ends keep their keys whatever is in the store: `a` starts a new character and `Q` leaves.
The saves take the letters left over, so a store with thirty characters in it still has a row that
leaves.

Picking a save carries it on. A name is picked rather than typed, so somebody coming back to a
character no longer has to spell it the way they spelled it the first time.

The seed and the version go in the menu's title, because that is what a bug report needs and the
title screen is where somebody reads it. `Menu::TITLE_SLACK` keeps the box two cells wider than its
own title, which it did not before: a box sized to its title exactly had the last letter of it cut
by the border corner.

## Blessings and curses

A blessing is hidden on each item until the character finds out. There are now three ways they do:
a scroll of identify names one, a scroll of blessing or of remove curse marks what it finds, and
carrying a thing long enough is its own answer.

### A letter holds a list

`Inventory` holds an ordered list under each letter rather than one item. Which letter a thing goes
under is `Item#looks_like?`, which compares only what the character can see: the kind, the `+N`, the
condition, whether it is alight, and the blessing once they know it. Twelve arrows and three more
that differ only in a hidden curse are one row reading "15 arrows".

Inside the letter the items stay apart, decided by `Item#stacks_with?`, which compares the hidden
blessing as well. The list is in the order it was picked up and everything that takes one item takes
the first, so a quiver empties its oldest arrows first.

The letter splits the moment the character works one of them out. What they noticed moves to a
letter of its own. With every letter taken there is nowhere for it to go, so what it was sitting
with goes on the floor and what they noticed keeps the letter.

This replaced a rule that compared the hidden blessing when handing out letters. Two arrows that
differed in a curse took two letters under it, which told the player something differed without
telling them what.

### Handling

`Handling` holds four numbers. A turn in a slot is worth 3 and a turn merely carried is worth 1.
Nothing is noticed below 10, and the roll past that is set so the average at which it is noticed is
100. The roll is geometric, so the median is about 72. A worn item is worked out in about 34 turns
and a carried one in about 100.

`Game#handle_items` runs on every turn, on a stream of its own named by `#handled`, so learning that
a sword is cursed does not shift what the next swing rolls. The rolls are collected before any of
them is acted on, because acting on one moves items about.

### What the character says when they work it out

Only a curse or a blessing.

```text
You realize that an iron spike is cursed!
You realize that 3 iron spikes are blessed!
```

Working out that something is uncursed writes nothing. Almost everything a character carries is
uncursed, and a line for each of them fills the message pane, holds a page behind `--More--` and
stops every run, because anything written to the log stops one. The item still moves to a letter of
its own, so the pack is where an uncursed item is read.

The verb agrees with the count, because one stack of three says "are" and a single spike says "is".
The name leaves the blessing word out, because the sentence is what says it. `Lore#name` takes a
`blessing` argument for that, false meaning leave the word out however much the character knows.

`Game.worked_out` answers the line, or `nil` for an item that turned out to be uncursed.

The character's own kit is known from turn nothing. `Game.outfit` marks the short sword, the
leather armour, the torch and the spikes as blessing-known, so none of them waits on a handling
roll. Somebody has owned their own gear long enough to be sure of it, and there is nothing to learn
from watching the pack stop hedging about a sword the character arrived with.

### What a blessing does to a weapon

`Item#aim` is what an item adds to a swing or a shot landing: the enchantment, the condition, and
`BLESSED_AIM` for a blessing. `Player#to_hit`, `#to_shoot` and `#to_throw` all read it, so a
blessed bow and a blessed arrow each count.

It adds nothing to the damage. `Item#damage` reads the enchantment and the condition and stops
there, so a blessed sword reads as a plain one in the detail pane and lands more often than one.
Nothing shows a to-hit number anywhere, so the bonus is invisible by construction rather than by
being hidden.

`BLESSED_ENCHANTMENTS` leans harder than it did: 85 out of 100 blessed weapons carry a plus, for a
mean of +1.37 against +0.18 on one nobody has touched. A blessing found on the floor is therefore
worth about a point and a half; a blessing put on with a scroll is worth the one point of aim.

### A curse holds what is in a slot

`Item#sticks?` says only that an item is cursed. Whether it can be let go of is `Game`'s to decide,
and the rule is that a curse holds what is in a slot and nothing else. A cursed spike, potion,
scroll, wand or torch drops at will. A cursed sword in the hand does not.

This replaced a rule that read the item's class. The two give the same answer for everything that
can be readied, and the slot rule also covers a wand, which gets into a hand only through a curse.

### What a curse does to a thing that is used

`Blessing#potency` is a percentage: cursed 50, uncursed 100, blessed 200. A cursed potion of healing
puts back half and a blessed one puts back double. The item still works. Using it reveals its
blessing, because what it did gives that away. An uncursed one has nothing to give away and stays
unmarked.

### A cursed wand takes your hand

Zapping a cursed wand works at full strength, and then the wand puts itself in the weapon hand. It
takes the hand that holds a bow when a curse has the weapon hand already, and with both held the zap
is refused before it spends a charge or a turn. Whatever it displaces goes back to being carried.

While it is in the hand it cannot be taken off, dropped or thrown, and swinging it hits like a fist:
`Player#damage` and `#to_hit` treat anything with no dice of its own as bare hands. A wand in the
ranged slot stops the character shooting, which `#cannot_fire` and `#firing_reach` both check for.

There are two ways out. The last charge uncurses it. Each swing has `BRITTLE` in a hundred of
cracking it, and a cracked wand is dormant: it does nothing, holds nothing, and comes off.

`w` needs no change to keep a wand out of the hand by any other route. `Slot.for` already puts a
wand in no slot, so `Play#wield` never offers one.

### The two scrolls

| | cursed | uncursed | blessed |
|---|---|---|---|
| **blessing** | blesses one item it picks itself | marks every blessed and cursed item in the pack; blesses the chosen item | marks them in the pack and on the square; blesses all of them |
| **remove curse** | uncurses one item it picks itself | marks every cursed item in the pack; uncurses the chosen item | marks them in the pack and on the square; uncurses all of them |

A cursed scroll helps rather than harms, and aims badly. Three times in four it draws from the items
it could change. The fourth time, set by `STRAY`, it draws from everything carried and often lands
on something it does nothing to. A cursed scroll of remove curse over a pack with nothing cursed
always reads "to no effect".

A blessed scroll of blessing is what an uncursed one makes of a second scroll of blessing. Two of
them are worth more than one read twice.

### Reading in two halves

The marks are half of what a scroll of blessing does, and picking without them is picking blind. So
`Play` reads the scroll in two calls. `Game#start_reading` uses the scroll up, makes the marks and
spends the turn. `Play` redraws, puts the question up, and calls `Game#finish_reading`.

`Game` holds nothing between the two, so a game saved while the question is up has spent the scroll
and the turn and given up what the second half would have done. Backing out of the question does the
same, and asks first so it is never done by accident.

A scroll of identify stays one call. Its choice needs no marks, and taking a scroll off somebody who
changed their mind would be worse.

## Spikes

An iron spike is a carryable item. It is the first member of `ItemClass::Tool`, which is the class
for a thing used on something else rather than worn, drunk or swung. A tool takes no `+N`, hides
nothing behind an appearance, and `Slot.for` puts it in no slot. Spikes stack, because one spike is
the same as another, so three of them are one inventory entry rather than three letters.

Nothing drives one under a door yet. That verb arrives with bracing and with creatures that open
doors, which are listed below as three entries that have to land together.

The character starts with three. A floor hands them out at a weight of 7 against a table totalling
460, which is 1.5 out of every 100 items it scatters, in stacks of two to four. At that rate a
person who had to find one before learning what it is for would mostly never find one.

## Clicking a menu row

The pointer crossing a row already moves the highlight. A button going down on a row now picks it,
which does what typing that row's letter does. `Menu::Content#handle` moves the highlight first and
then runs `on_click`, which the menu wires to `pick_highlighted`, so the two paths end in the same
place and a row that cannot be picked is left alone by both.

Only the left button, and only the press. A release is not a second answer to a press, and a press
that lands past the last row is not a row. A press that picks is claimed; a bare motion report is
not, because whatever is tracking where the pointer is has to hear about every one of those.

## A name to start with

The name question offers one. `Names.roll` builds it from a syllable start, one or two vowel
groups, and an ending: "Kaeld", "Brizaend", "Shadioss". Nothing shorter than four letters is
offered, because three letters comes out an English word about as often as not. Nothing here holds
state, and it rolls on an `Rng` derived from the run's own seed, so `--seed N` twice offers the same
name twice.

`Names.free` rolls past a name the store already holds, because the question would otherwise refuse
its own offer.

A run that has ended offers the name it ended under, rather than a rolled one. A character who
died or won has had their file moved to `deaths/` or `wins/`, so the name is free again, and
somebody who answered "play again" usually wants the same name. It is offered once: a second
question rolls one, so a person who wanted a change can get past it. A name the store has taken
since is rolled past like any other.

`Session.open` carries it across the loop, because each run is a new `Play`.

The offer sits where the placeholder goes, dimmed, rather than on the line. A name on the line would
have to be deleted before a person could type their own, and most people have their own. `Enter` on
an empty line takes the offer. A question that comes back after a refusal comes back empty, with a
fresh offer.

## Time, speed and ticks

The clock runs in ticks. Every actor gains energy on every tick and every action costs energy.
`Pace::TICK` is 100, which is both what a normal actor gains in a tick and what a one-tick action
costs. `Pace` holds an actor's base speed and its banked energy, and `Player` and `Monster` each
carry one.

Energy rather than division. Dividing a cost by a speed rounds on every action and the error
accumulates, so "twenty percent slower" would stop being twenty percent over a long run. Leftover
energy carries to the next tick instead, and the ratio holds exactly however long the run is. An
actor at 80 takes 8000 actions in 10000 ticks, not 7998.

`Game#spend` is what a player action ends with. It takes the cost off the character and then runs
ticks until the character can act again. One action of theirs is followed by however many actions
everything else has earned in the meantime.

`Game#tick` counts the turn, banks energy, counts the timers down, and then lets every band look and
the awake ones act. `Game#creatures_act` skips a creature that has not banked a tick's worth, and
takes the cost off the ones that do act.

A creature whose band is asleep is held at one action's worth rather than banking. It acts on the
tick it wakes, which is what the order of `#tick` already gave it: a band that notices the character
on a tick swings on that tick. A band that slept for a hundred turns would otherwise wake with a
hundred actions in hand.

An actor is ready when it has banked `TICK` or more, and an action may cost more than that. A
three-tick action leaves the actor two ticks in debt and it pays that off before it acts again. So
an expensive action delays what comes after it rather than requiring a wait in front of it.

Speed is clamped to `Pace::LEAST`. An actor at no speed at all would never act again and the loop in
`#spend` would not end.

`Game#turn` counts ticks rather than player actions. With every actor at normal speed and every
action at one tick those are the same number, which is why nothing else had to change.
`Memory#turn`, sighting ages, `PATIENCE`, `FRESH`, `Species#persistence`, blindness and `Handling`
all keep the units they had. A save written before any of this loads with a pace at normal speed
and an action in hand.

### What each species is worth

| species | speed | actions per hundred of the character's |
| --- | --- | --- |
| character | 100 | 100 |
| goblin | 100 | 100 |
| orc | 95 | 95 |
| slime | 80 | 80 |

A slime can be walked away from. An orc gains a square every twenty turns on somebody who stops,
and a goblin holds whatever distance it has. Walking forty squares away from a creature three
squares behind leaves the slime thirty squares back, the orc four and the goblin three. The slime
loses sight of the character at four squares and gives up, which is `Species#persistence` doing its
own job on top of the speed.

`Game#creatures_act` sorts the awake creatures by square, north to south and west to east.
`Floor#walk` takes a creature out of the table and puts it back, so the order they were held in
followed what had moved rather than what was there. Two creatures never share a square, so the sort
is total.

Two hundred trial runs from seed 5000, at parity against these speeds:

| | parity | speeds |
| --- | --- | --- |
| died | 76% | 76% |
| turns until death, median | 98 | 102 |
| squares from start, median | 17 | 18 |
| killed by an orc | 51 | 42 |
| killed by a goblin | 96 | 104 |

The death rate does not move. `Trial::Bot` never retreats, so a bot that is faster than what is
chasing it walks into the next fight instead of the same one. Orc deaths fall by a fifth, and
goblin deaths rise by the same runs arriving somewhere else to die.

### What an action costs

`Costs` holds the table. Everything costs one tick but getting a suit of body armour on or off,
which costs three. A cap goes on in a turn and chain mail does not, so changing armour with
something in the room is a decision rather than a keystroke.

An action that costs three ticks leaves the character three ticks in debt, and `Game#spend` runs
three ticks to pay it off. Anything standing beside them swings three times. The character is ready
again when the loop stops, so the cost lands after the action rather than as a wait in front of it.

`Trial::Bot` never wears armour, so the trial report cannot see this change. Two hundred runs from
seed 5000 print what they printed for the species speeds.

### The three items that change a speed

A potion of haste adds `Pace::HASTE` to the drinker for `3d6+12` ticks. `Blessing#potency` scales
the duration the way it scales what a potion of healing puts back, so a cursed one lasts half as
long and a blessed one twice. A second draught runs the timer on rather than raising the speed
again: five potions are five times the time, not five times the speed.

A scroll of slow monster takes `Pace::SLOW` off for `4d6+20` ticks. A scroll of haste monster adds
`Pace::HASTE` for the same. Neither duration is scaled, because the blessing already decides who it
lands on.

| | slow monster | haste monster |
| --- | --- | --- |
| uncursed | the creature aimed at | the creature aimed at |
| blessed | every creature in sight | the reader |
| cursed | the reader | every creature in sight |

Both are read and then aimed, which is `Effect#aims_after?` and the path a scroll of blindness
already takes. `Game#target_needed?` needed nothing new: it asks for a square when the scroll is
uncursed and for none otherwise, which is what these two want.

The character is told when their own haste or slow runs out. A creature is not, the same way a
creature is not told about its blindness: the character cannot tell one that has slowed down from
one that is waiting for them.

A creature that has banked more than one action takes them all in the same tick.
`Game#creatures_act` loops while the creature is ready rather than acting once. `Game#tick` banks
energy last, after everything has acted, so nothing spends energy it earned on the tick it is
spending it in.

Two hundred trial runs from seed 5000, with the three kinds in the tables and without them:

| | without | with |
| --- | --- | --- |
| died | 76% | 77% |
| turns until death, median | 102 | 117 |
| squares from start, furthest | 76 | 151 |
| killed by a slime | 7 | 11 |

`Trial::Bot` drinks a potion when it is badly hurt and does not read what it is holding, so it
swallows a potion of haste in place of a heal and covers more ground before it dies. Some of the
rest is the tables having three more kinds in them, which moves what every roll after them lands on.

### Measuring what a speed is worth

`--trial-speed N` moves every species at `N` instead of its own speed. `--trial-cautious` plays
`Trial::Cautious`, which is `Trial::Bot` with one step in front of the swing: below `Bot::HURT` out
of a hundred hit points, with something beside it, it steps to whichever square takes it furthest
from that creature. The plain bot never retreats, so it takes the same beating whether it could
outwalk what is hitting it or not.

Two hundred runs from seed 5000, every species at one speed:

| every species at | died | turns until death, median |
| --- | --- | --- |
| 70 | 71% | 147 |
| 85 | 75% | 97 |
| 100 | 76% | 95 |
| 115 | 78% | 97 |
| 130 | 83% | 93 |

Above 85 the death rate rises about a point for every five points of speed. The shipped speeds come
out at 77%, between the 85 and the 100 rows, because a goblin is at 100 and goblins are most of
what is on a floor.

The same two hundred runs with the bot that backs away:

| | reckless | cautious |
| --- | --- | --- |
| died, shipped speeds | 77% | 79% |
| died, every species at 100 | 76% | 79% |
| turns until death, shipped | 117 | 106 |

Retreating does not pay. A goblin holds whatever distance it has, so backing away from one is
taking hits without giving any, and a goblin is forty-five out of every hundred creatures on a
floor. The speeds here only buy something against a slime, which is the least dangerous of the
three to begin with. Making the difference matter means slowing what is common rather than what is
rare, or giving the character a way to get faster, which is what the potion of haste is.

## Regeneration

`Player#rested` counts ticks since the last wound. `Player#hurt` sets it back to nothing, so a
character being hit once a turn never regenerates. `Game#regenerate` runs on every tick: past
`Game::REST` ticks of going unhurt, the character regenerates one hit point every
`Player#regeneration` ticks.

Regeneration starts ten turns after a wound whatever the character is made of, and the rate after
that comes from constitution. `Advancement.regeneration` is `REGENERATION` less
`REGENERATION_PER_POINT` for each point of the constitution modifier, with a floor of
`REGENERATION_LEAST`.

| constitution | ticks a hit point |
| --- | --- |
| 3 | 32 |
| 6 | 26 |
| 10 | 20 |
| 14 | 14 |
| 18 | 8 |

Constitution already decides how many hit points there are. This is the other half of the same
idea: a tough character has more hit points and regenerates them faster. At average constitution a
character at one hit point out of twelve regenerates to full in two hundred and twenty turns of
going unhurt, which is long enough that walking away from a fight is a decision rather than a free
heal.

It lives in `Advancement` beside the hit point table, because both are constitution turning into
health and neither rolls anything.

Nothing rolls attributes yet. Every character starts at ten across the board, so every character
regenerates a hit point every twenty ticks today, and the table above is waiting for a character
who is not average.

Regeneration writes nothing to the log. A line a turn saying the character is a little better would
fill the log, and anything written to the log stops a run.

Only the character regenerates. A creature that lost the character and healed while it looked for
them would undo what hitting it and walking away buys, which is the one thing a slower creature
leaves open.

Losing hit points stops a run. Gaining one does not, or a character regenerating along a corridor
would stop every twenty steps for good news.

Two hundred trial runs from seed 5000, without regeneration and with it:

| | without | with |
| --- | --- | --- |
| died, the bot that never retreats | 77% | 76% |
| died, the bot that backs away | 79% | 77% |

It is worth more to the bot that retreats, which is what it is for. Scaling the rate by
constitution moves neither number, because every character the trial plays has a constitution of
ten.

## Pointing at a square

Two things ask the same question: where would the character walk to get there, and what does that
look like on the map.

### The route

`Route` floods outward from the character with `Descent`, over `Knowledge` rather than over the
floor. The flood runs once and every question is answered off it. A route to a square is read by
walking downhill from that square, which arrives at the character, and turning the list round.

A band of monsters floods toward what it is chasing. The character is the other way round: they
pick a square and want the squares between. One flood from the character answers any number of
picks, and the fallbacks below need the whole flood anyway.

`Route.chosen` tries three things in order.

1. Over what the character remembers. A square they have never seen is not walked through, and
   neither is a door they remember as shut.
2. Over that plus the squares a line of sight crossed. Light that reached the eye ran through those
   squares, so nothing solid stands in them. This is what reaches a lit room on the far side of a
   dark one: the room is seen and the dark ground between it and the character is not.
3. To whichever square the second flood reached that is nearest the pick. A route to somewhere
   unreachable walks as far as it can rather than refusing.

The inference is written into a copy of `Knowledge` and thrown away. What the character remembers
does not change because they worked out a route. A square on an inferred line is still unseen, and
the map still draws it blank.

The line stops one square short of what was seen. A field of view holds every wall its scan
reached, and a wall is not somewhere to walk. The square at the far end needs nothing from the
inference anyway: looking at it is what put it in `Knowledge`.

Symmetric shadowcasting and Bresenham's line disagree about a square that clips the corner of a
wall, so an inferred route can run into one. `Game#follow` checks each square as it steps onto it
and stops against the wall, which is what it does for a square something has walked onto since.

### Walking it

`Game#follow` is `Game#run` with a list of squares instead of a direction. Every step is a whole
turn, so a route is as dangerous as walking it a key at a time.

A doorway and a junction stop a run. They do not stop a route: the person picked a square on the
far side of both, and a route that stopped at every door would be a key press a door. What stops a
route is what the person had not seen when they picked.

What is lying on the floor was reworked for both. A run used to stop on any message, and walking
onto a square with a dagger on it writes one. `Game` now records which squares the character
remembered something lying on when the run began, and `#told?` subtracts the lines about those
before it decides whether anything was said. The line is still written. Somebody who set a run
going across a square with a dagger drawn on it is not surprised by the dagger, and somebody who
finds one that was not on their map is.

### On the screen

`Play` holds one `Pointing`: the square picked, the squares to walk, and the turn it was worked out
on. A turn passing drops it, because the floor it was worked out over has moved.

The first click on a square lights the way there. A second click on the same square walks it. A
click anywhere else lights the way to that square instead, so changing your mind costs one click
rather than two. A square the character knows nothing about is read out and no more.

`>` and `<` away from a staircase do the same thing without a click. The staircase the character
remembers is lit up, and the way there with it when they know one. A staircase they have seen but
cannot yet reach is still marked: `Route.known` stops at the second try rather than settling for
somewhere near it.

The camera slides a cell at a time rather than jumping, on a timer armed through `App#after`, the
same clock the flames run on. A map that jumps leaves the person hunting for where they were. An
application with no clock finishes the slide at once, which is what a spec sees. The character
moving drops a slide in progress: the window is for them.

`Pager#hold` holds the newest page however few lines arrived, so `The stairs are here.` waits behind
`--More--` until a key is pressed. Nothing else in the game needs one line read before the next
thing happens, so this is the first caller. The key that lets that page go takes the route off the
map with it: reading the line is what the route was up for. `Pager#on_release` is what says so, and
it runs only for a hold somebody asked for. A page held because more lines arrived than fit is
nobody's question.

### One step at a time

A run used to happen inside one key press. `Play` holds no terminal and cannot send a frame partway
through a handler, so the whole thing was drawn once at the end and the character appeared at the
far end of the corridor without having crossed it.

`Game::Walk` is a run in progress: where it is going, how far it has got, what could be seen before
the last step, and which squares had something on them the character already knew about.
`Game#stride` takes one step of one. `Game#run` and `Game#follow` build a walk and stride it until
it stops, which is what a spec and the trial harness want and is what they always did. `Play`
strides it on a timer instead, one step every `STRIDE`, which is about what holding a movement key
down gives.

A walk carries everything one step needs to know about the step before it, so nothing about a run
is kept on the game and a walk abandoned part way leaves nothing behind.

`Ui::Interrupt` holds the keyboard while a run is drawn. It is a widget with no cells that pushes a
focus scope rooted at itself, which is how `Pager` grabs the keyboard while it holds a page:
`Router` reads the top scope's keymap and the chain under it, and a scope rooted at a widget with
neither puts every binding the application has out of reach. Any key then reaches
`Interrupt#handle`, which stops the run and does nothing else. A click does the same.

Both of those push onto one focus stack, and a stack is only unwound from the top, so only one of
them may have a scope up at a time. A run whose steps write a line each would otherwise let the
pane hold part way through and leave the run's own scope buried. `Pager#deferred` is what keeps
them apart: while it is set the pane holds nothing and counts nothing as read, so the lines pile up
unread and the hold happens when the run is over and the person has the keyboard back.

## How well something is made out

Seeing a thing and knowing what it is are two different things, and until now the game treated them
as one. A spear at the far end of a lit hall was drawn as a spear and named "a cursed -2 spear", and
a creature the character could only make out as an outline against a torch behind it was drawn as a
shape and still called a goblin in every readout. `Regard` is the one answer both of those ask for.

`Regard` is a model type rather than a `Ui` one. How near somebody has to stand to read a label is a
rule of the game: it decides what the map draws, what the `Seen` list says, what the `Look` readout
says and what a tooltip says, and those four have to agree. A rule kept in the drawing code would be
four copies of it.

### The four members

`Regard::Nothing` is a thing the character has never laid eyes on. `Regard::Shape` is a size and no
more, which is what a creature showing against light behind it gives. `Regard::Kind` is what sort of
thing it is and nothing about which one: a spear, a scroll, a potion. `Regard::Everything` is what
standing over a thing gives.

The members run from least made out to most, so `Regard#at_least` can take the better of two looks
and `<` compares them. A member is never removed and never reordered: a save file holds the member
name.

### Eight squares

`Regards::READING` is eight. A torch throws light six squares, so a character carrying one makes a
thing out a step or two before they stand on it. A lit room is wider than eight squares across, so
the far side of one still holds things the character can see and cannot name, which is the point: a
room should be worth walking into. Eight is also what a goblin and an orc notice at, so a person
reads a label at about the range they are noticed at.

The constant lives in `Regards` rather than in the enum because an enum body cannot hold one: a name
with a number after it in one is a member of the enum. `Species` and `Kinds` are split the same way.
`Regards.of_item` is the rule itself, and it takes either a number of steps or two squares.

### What is remembered

`Memory` carries a `regard`, which says how well the item on that square was made out. It has a
default of `Regard::Everything`, so a square written before the field existed loads as one the
character made everything out on. That is what those saves meant: the name was written in full
whatever the distance.

`Knowledge#see` takes a regard and `Knowledge#learn` works one out per square from how far it is
from where the creature stands. A worse look never undoes a better one. A square whose item has not
changed keeps the best regard it has ever been seen with, so walking away from a spear the character
has stood over does not turn a cursed -2 spear back into a spear. The item has to be the same one:
a square where somebody swapped the spear for a potion starts again from whatever the new look
gives.

### What the game answers

`Game#regard_of` takes a creature. A creature with light on them is `Regard::Everything`, one
showing against light behind them is `Regard::Shape`, and one that cannot be seen at all is
`Regard::Nothing`. `Game#regard_of_item` takes a square. A square the character can see is answered
by how far off it is, held up against what they remember of it; a square they cannot see is answered
by what they remember alone. Both have an overload taking a `Vision` that has already been worked
out, because working one out is most of what a turn costs and a pane asks this once per row.

### What the names look like

`Lore#name` and `Ui::Naming.short` both take a regard, and both default to `Regard::Everything`.
Nothing that names an item the character is holding passes one, so the pack, every menu and every
message read as they always have. Anything short of `Regard::Everything` writes the kind and no
more: "a spear" rather than "a cursed -2 spear", "a scroll" rather than "a scroll YLOH",
"a potion" rather than "a swirly potion". `Lore.bare_noun` is where that wording lives. A thing that
is what it looks like keeps its own name, because a spear is a spear from any distance; a potion, a
wand and a scroll are a bottle, a stick and a sheet until somebody is near enough to read them.

`Size#label` already wrote a shape in full: "a small shape", "a shape", "a large shape".
`Size#short` writes the same thing for a column, shortened to the three letters the sidebar already
uses for a condition and a blessing: "sml shape", "med shape", "lrg shape".

### What names an item on the floor

The `Look` readout and the `Seen` list both ask `Game#regard_of_item` and hand what it answers to
`Lore#name`. `Look` covers a square the character is pointing at, whether they can see it or only
remember it: `Examiner` asks the game against the field of view the map was drawn from, and
`ExaminePane` writes the name it gets back for the pile that is lying there and for the item the
square remembers alike. `Seen` asks once per item, because each one is lying on a square of its own,
so a spear four squares off and a scroll twelve squares off read differently in the same list.

The `Here` section passes nothing, and neither does the menu that asks which of a pile to pick up.
Both are about the square the character stands on, which is nought steps off and
`Regard::Everything` by the rule. The pack, the equipment slots, every other menu, every tooltip and
every log message pass nothing either: each of those is about a thing the character is holding.

### What names a creature

The `Seen` list, the `Look` readout and the tooltip that hangs off a `Seen` row all ask
`Game#regard_of`, so all three say a size where the map draws a shape. The bar for the creature the
character is fighting asks as well. Each of them is handed the field of view the map was drawn from
rather than working out another, because one cast is most of what a turn costs.

## The creature the character is fighting

The sidebar carries a fourth bar under the character's own three. It is the hit points of the
creature the character last traded blows with, and it is there only while that fight is going on.
A person swinging at something in a dark corridor could read how hurt it was only by counting the
damage numbers in the log. The bar says it.

### Red at full, yellow at zero

`Palette::THREAT` runs the other way from `Palette::HEALTH`. Red is a creature at full strength and
yellow is one about to fall. The character's own bar is green at full because it is about their
safety. This one is about a threat going away, and the two read the same way round once that is
said: green and yellow are good news, red is trouble.

There are three levels rather than the five `HEALTH` has. The bar is one row about one creature and
the only question it answers is how much is left, so the colour has to move far enough to be read
at a glance rather than in small steps.

### What the bar says

The label outside the bar is `vs`, two columns, the way `HP`, `MP` and `XP` are. A creature's name
does not fit in two columns, so it goes inside the bar in front of the count: `goblin 7/12`.

`Ui::Naming.creature` writes it. A creature the character has made out to `Regard::Kind` or better
is named by its species. One they have only made out as an outline is named by `Size#short`: `med
shape 7/12`. That is the same wording the sidebar already uses for a shortened item, so the column
reads the same way down its whole length.

### What counts as an exchange

Every blow either way, landed or missed. A miss is a blow aimed at something, and a person who has
just missed wants to know how much is left in what they missed as much as a person who hit does.

A shot counts too. `Game#hit` is where an arrow, a thrown rock and a bolt from a wand all land, so
hooking that one method covers all three. Shooting a creature across a room is trading blows with
it at a distance, and the reading is worth the same there as it is in reach. A wand of light aimed
at a creature is not a blow and does not go through `Game#hit`, so it raises nothing: the
distinction falls out of the code rather than having to be written down as a rule.

### Eight turns

`Game::FIGHT_LASTS` is eight. A creature that breaks off and comes back inside eight turns is the
same fight rather than a new one. Eight turns is long enough to walk the width of a lit room, so a
creature that has not swung in that time is somewhere else. It is also what a goblin and an orc
notice at, so the bar holds for about as long as the creature would need to close again. Every
exchange either way writes the turn down again, so a fight that goes on holds the bar.

### When the bar goes

`Game#fought` answers the creature while it is worth showing and `nil` otherwise. It is `nil` once
the creature is dead, once it is no longer standing where the game last saw it, and once
`FIGHT_LASTS` turns have gone by. A creature that walks out of sight is still answered: the
character has been hitting it, knows it is there, and how hurt it was is worth reading whether or
not they can see it now.

The "standing where the game last saw it" test is what covers a floor change. The creature is
looked for on the floor the character is on, so one left behind on another floor is not found.
Descending ends the run today and there is no second floor to go to, and the rule is already right
for the day there is.

### Naming the creature across a save

`Game` is `JSON::Serializable` and the floor already holds the creature. A second copy in the save
would load as a second creature, and the bar would follow the copy while the floor ran the
original. `#killer` had the same problem and holds a label rather than a creature.

The creature is named by the square it stands on. Two creatures never share a square, so a square
and the floor the character is on name one of them. `@fought` is the live reference and is not
written out. `Game#fought_at` is the square, and `#tick` writes it again at the end of every turn,
after everything has moved, so it still names the creature after it has walked.
`Game#after_initialize` looks the square up and finds it again. A square with nobody on it means the
creature died or the character went elsewhere while the save was cold, and the fight is over either
way.

`Game#fought_regard` is written out too. It keeps the best look the character has had of the
creature, the way a remembered square keeps the closer of two looks. A creature seen in the light
is the same creature once it steps into the dark, so the bar goes on naming it. A blow at a
different creature starts that again.

All three fields carry defaults in their declarations, so a save written before they existed loads
with no fight going.

### Where the bar sits, and what gives way

The bar is a block of its own between the character's vitals and the row of numbers, so a blank row
keeps the creature's hit points from being read as the character's.

`CharacterPane#fit` gives it up last of all, after the pack, the empty slots, the scores and the
equipment. A person in a fight reads how much is left in the thing hitting them more often than
they read what is in their hands. It does go, though: the level, the hit points and the experience
come before it, and `CharacterPane::LEAST` is what it would have pushed off. An eighty by
twenty-four terminal has room for it. Anything shorter drops it.

`#fit` cannot read the row to find out whether there is a fight, because `#fit` is what decides
whether the row is hidden. `#show` records it in `@fighting`, which is the same arrangement
`@filled` already uses for the equipment rows.

## Drawing a shot

An arrow used to arrive without having travelled. `Game#fire` worked the shot out and applied it
inside one key press, and the screen was drawn once at the end, so the only sign of the shot was a
line in the log and an arrow already lying where it stopped.

`Ui::Play` now draws the missile crossing the squares, one square every `Play::SHOT`. That is
fifteen milliseconds against the forty-five a walked step takes. An arrow crosses ground faster
than a person walks it, and a shot drawn at walking pace reads as a stone rolling.

### A replay rather than a rule

The shot is worked out and applied before anything is drawn. `Game#loose` and `Game#bolt` each
record what flew in `Game#in_flight`, as a `Missile`: the `Flight` it took and the item that took
it. A bolt has no item, because nothing lands on the floor afterwards.

So the picture is a replay. The arrow is already lying where it stopped and whatever it killed is
already gone by the time the first frame is drawn. That is visible for the tenth of a second the
shot is in the air, and it is what keeps every rule in `Game`: a shot drawn first and applied
afterwards would have to hold the keyboard for the length of the animation, because a movement key
pressed part way through would move the character and leave the shot resolving from a square it was
never aimed from.

`Play` holds the missile with `MapPane#mark`, which is what the character is drawn with. A mark is
something standing on a square rather than something written into the floor, and every refresh
clears the marks, so the frame that ends the shot leaves nothing behind.

### Not drawing the shot before last

Every command that might let something fly — `#fire`, `#throw`, `#zap` and `#aim_reading` — clears
`@in_flight` before it does anything else. A command that lets nothing fly then answers `nil` rather
than the shot before it. Reading a scroll at a square is the case that needs it: it takes a target
and sends nothing across the floor.

The animation also gives up when the turn moves on. A key pressed while a missile is in the air
takes a turn of its own, and the floor the shot crossed is gone by then.

## Tooltips on the Here and Seen rows

The `Worn/Wielded` and `Pack` rows raised a tooltip and the `Here` and `Seen` rows did not, which
made the sidebar answer two different ways to the same gesture. Now every row of it answers.

### Rows that take the pointer

`NearbyPane` wrote its rows as `Widgets::Label`, which has nowhere to hang a pointer hook.
They are `Ui::Line` instead, the same widget the character pane writes its rows on, and a `Line`
takes `on_point`. A name too long for the column is now cut with an ellipsis rather than wrapped
away, which is what the rest of the sidebar already did.

The hook goes on the pane rather than on the rows. The character pane holds one row per slot for
the life of the run and `Play` hooks each of them once. `NearbyPane` builds its rows afresh every
turn, so a hook put on a row would be a hook on last turn's row. `NearbyPane#on_point` is read at
the moment the pointer crosses a row, and the pane hands over the row and the lines to write beside
it. `Play#detail` then does what it does for every other sidebar row.

A row about nothing in particular, such as the one saying how much was left out, hands over `nil`
and takes down whatever box was up.

Each row is one cell tall at most and may be squeezed to none. A row that could not be squeezed
would take its cell off the message log on a short screen, which is what the heading of each
section already guards against.

### What a row says

`Ui::Detail` knew about items alone. It knows about four things now:

| Row | What the box says |
| --- | --- |
| Terrain | What it is called, and a sentence about it |
| Fixture | What it is called, lit or not, and a sentence about it |
| Item | Its whole name, what it does, what it weighs, whether it is cursed |
| Creature | Its name, a sentence about it, its hit points, what it is doing |

An item the character has not made everything out of writes its bare kind and one line saying they
are too far off to make out more. A creature they make out only as a shape writes its size and the
sentence the `Look` readout writes for one, and nothing else at all: its species, its hit points and
what it is doing all wait for light on it. A creature they cannot see writes nothing, and the pane
raises no box.

Both panes write the same sentence for a shape because `Detail` reads `ExaminePane::MOVING`. Two
copies of it would drift.

### One field of view per pass

`NearbyPane#show` is already handed the `Vision` the map was drawn from. Every row it writes passes
that same one to `Game#regard_of` and `Game#regard_of_item`, because working a field of view out is
most of what a turn costs and a pane draws twenty rows.

## Marks instead of words in a list

A pack row read `a - a blessed masterwork +1 chain mail (being worn)`. A list of those is hard to
read down. The noun is not in the same place on each row. The article, the count, the blessing, the
condition and the enchantment each come first on some rows. The slot is a phrase at the end of a
line of varying length. Finding the potions in fifteen rows means reading fifteen rows.

Each word with only a few possible values is now a mark in a column of its own.

### The row

```text
⟪ a ✦  a +1 short sword          ⚔ ⟫
  b ✓    masterwork chain mail   ⛊
  c ✘ 23 +1 arrows               ➷
  d      a scroll MUCK
```

The gutter is six cells: the pointer, the key and the blessing mark. The count or the article are
in their own field, right-aligned. The name follows, and the names line up. The slot mark is against
the right edge. The mark facing the pointer is past it.

The gutter does not scroll. A row scrolled sideways slides under it. The key and the mark stay in
place.

### The marks

| Mark | Codepoint | Meaning |
| --- | --- | --- |
| `✦` | U+2726 | blessed |
| `✘` | U+2718 | cursed |
| `✓` | U+2713 | uncursed |
| | | the blessing is not worked out |
| `⚔` | U+2694 | in the hand |
| `➶` | U+27B6 | the ranged weapon in the hand |
| `➷` | U+27B7 | in the quiver |
| `⛊` | U+26CA | worn, in any of the five worn slots |
| `⁕` | U+2055 | a light source that is burning |
| `⟪` | U+27EA | the near edge of the row the pointer or the highlight is on |
| `⟫` | U+27EB | the far edge of that row |

Every item whose blessing is settled has one of the first three marks. An item whose blessing is not
worked out has no mark. Uncursed is the faintest of the three, because most items are uncursed.

Each mark is one cell wide. `⛊` is East Asian Ambiguous. A terminal set to draw ambiguous characters
in two cells draws it in two. termbuf's width policy sets that. `⚔` has `Emoji=Yes` with a text
default. A font stack that substitutes a colour glyph draws it in two cells.

### Colours

The marks are not at full brightness. They sit in a column of their own. They are designed to be
distinctive from each other.

| What | Colour |
| --- | --- |
| blessed | `90B8D8` |
| cursed | `C08098` |
| uncursed | `6A707C` |
| every slot mark | `88A898` |
| burning | `E4A860` |
| the pointer and the mark facing it | `9AA4B4` |

### What the highlight covers

The highlight covers the text. The gutter holds the key and the blessing mark. The colour of the
blessing mark is part of its meaning. Reversing the gutter would invert that colour.

### Where the marks are named

The marks are named in the tooltip on the row. The tooltip gives the mark and the word for it:
`✦ blessed`, `✓ uncursed`, `⚔ weapon in hand`, `⁕ burning`. The column is then readable without a
key elsewhere. An item whose blessing is not worked out has `unknown` alone, because it has no
mark.

The first line of the tooltip names the item without the blessing word. The line under it gives the
blessing.

### The Here and Seen rows

The same two marks go on the row under the pointer. Those rows start `Line::INDENT` cells in. The
cells are kept clear on every row, so a row does not move sideways under the pointer. This costs two
of the sidebar's columns. A name long enough to be cut is cut two cells sooner than before.

The mark facing the pointer uses two cells that would otherwise hold text. A name already at the
edge is cut two cells shorter while the pointer is on it. The tooltip is up then and gives the whole
name.

`NearbyPane` builds its rows again every turn. A rebuild takes the mark off, because the row it was
on no longer exists.

## Asked for, not yet built

Each of these was asked for and written down rather than built at the time. They are in the order
they were raised, not in the order they should be done.

### The Seen list

Hovering a row with the mouse should light the creature's square on the map. The list should be
sorted by how far each creature is from the character.

### An options screen, and a pickup filter

Player preferences need somewhere to live. One of them is what to pick up without being asked.
Rather than a switch for gold, it is an ordered list of rules: gold only, by default, and a person
can add rules like "never pick up a cursed item", "pick up anything better than what I have",
"never pick up a worse weapon", "always pick up anything worth more than 100 gold". What a rule can
say is its own design question.

Another preference: whether a bar's colour comes from the gradient or from the fixed bands.

### The rest of the route on the map

A route is drawn and walked by clicking. Two pieces of what was asked for are not built. The route
should fade after a few seconds with no movement and no other click, rather than waiting for a turn
to pass. Clicking a row of the Seen list should draw a route to that creature.

### A minimap

Braille characters give four by two squares per cell, which is enough to show a 216 by 84 floor in
a corner of the screen. Where the terminal speaks the kitty graphics protocol, draw it as an image
instead.

### Kitty graphics for the bars

Where the protocol is there, a bar could be three layers rather than a row of cells: a gray image
the width of the bar at the lowest z, the filled part sized over it, and the text over that. The
fill would then move by a pixel rather than by a cell.

### A bot that plays well enough to trust

`Trial::Bot` never retreats and never shuts a door, so what it measures is narrow. It needs to shut
doors, brace and spike them, and decide whether a fight is worth having. Shutting doors looks like a
large gain in survival now, and it will not be one once most creatures can open them, so the bot and
the door rules have to arrive together.

### Creatures that open doors

A shut door currently ends a pursuit, because `Knowledge#walkable?` says a shut door cannot be
walked onto and a band paths over what it knows. Most creatures should be able to open one. That is
what makes bracing and spiking a door worth doing.

### An action menu on an inventory letter

`i` lists the pack with a letter against each row and the letters do nothing. A letter should open a
menu of what can be done with that item: equip, take off, wear, quaff, read, throw, inspect,
identify. The menu should be a fixed list with the entries that do not apply dimmed rather than
left out, so the same key is in the same place every time.

### A note on where the game is drifting

Light, stealth, detection range and shutting doors are the levers that move survival most, which
pulls the game toward stealth. Whether that is wanted is open, and it should be looked at again once
creatures have more to do than walk at the character and swing.
