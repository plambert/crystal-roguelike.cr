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

## Ground rules

These hold from Phase 0 and are not revisited.

* **One seed, many streams.** A run has one seed and `--seed N` reproduces it exactly, which is
  what makes every later phase testable. It does not have one sequence: `Rng#derive(domain, id)`
  picks an independent PCG32 stream from a stable hash of the name, so what a level, a loot
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
  snapshot spec this way. Nothing needs a tty to test.
* **The model knows nothing about the screen.** Level, player, monsters and items have no
  reference to `TermBuf`. Widgets read the model and draw it. A spec runs a hundred turns with no
  widget tree at all.
* **Turns, not frames.** The loop is `App#wait`, which blocks on the event channel. Nothing
  redraws on a clock. Animation and regeneration are driven by `App#after` timers that arrive on
  the same channel, in order with the keystrokes.
* **Build for 24-bit colour and check the fallback.** Styles carry true colour; termbuf reduces
  at encode time. Each phase that adds colour is also run once under
  `TERMBUF_CAPS=none,+color256` to confirm it is still readable.
* **`shard.yml` names dependencies as `github:`.** Transport is ssh, set once and globally with
  `git config --global url."git@github.com:".insteadOf "https://github.com/"`, which covers
  transitive dependencies as well. Naming a git URL in `shard.yml` does not, and collides with
  the `github:` a dependency's own `shard.yml` uses for the same shard.

## Architecture

Four decisions that cost almost nothing now and are expensive to retrofit. Each exists because of
something in [Long-term direction](#long-term-direction).

### Levels persist, so the model serializes from the start

Levels are not thrown away when they are left, and eventually they live in a save file. So the
world is a `World` holding `Level`s by id, and every type in the model round-trips through
serialization from Phase 3 onward, with a spec that says so.

The constraint that follows, and the one that bites if it is found late: **nothing in the model
holds a `Proc` or a closure**. Behaviour is named — an enum, a symbol, a registry key — and
looked up. A monster's attack pattern, an item's effect and a trap's trigger are all identifiers,
not blocks.

Save and load themselves are future work. Serializability is not.

### Belief is modelled apart from truth

What is on a level and what somebody thinks is on a level are two different things, and the
second one is where the interesting behaviour lives. So there is a `Knowledge` type from the
first moment anything needs to remember a level: terrain seen, where things were when last seen,
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
| `w` `W` `T` | Wield a weapon, wear armour, take armour off |
| `q` `r` `z` | Quaff a potion, read a scroll, zap a wand |
| `f` `t` | Fire the ranged weapon, throw something |
| `a` | Apply — light a torch or a candle, light a wall sconce |
| `o` `c` | Open, close |
| `x` | Examine — move the cursor without the mouse |
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
| Single-key prompt | Phase 6 | `[yn]` on one line, no button group, no Tab |
| Paged message line | Phase 7 | `--More--` held at a page boundary |
| Accelerator menus | Phase 10 | A list addressed by letter rather than filtered |
| Quantized style ramp | Phase 14 | A `Blend` over N fixed steps, so styles stay interned |

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

### Phase 3 — Terrain and a hand-built level

* **Build** — A `Terrain` enum: `Granite`, `Sandstone`, `Shale` (three rock walls, identical in
  behaviour for now, distinct in colour), `StoneFloor`, `DirtFloor`, `ClosedDoor`, `OpenDoor`,
  `StairsUp`, `StairsDown`. Each carries the character a level file writes it as, a label, a
  description, whether it blocks movement and whether it blocks sight — but not a glyph or a
  style, which are the screen's and live in `Ui::Palette`, per the rule that the model knows
  nothing about the screen. A `World` holding `Level`s by id; a `Level` holding a grid of `Tile`,
  loaded from a plain-text map file under `data/levels/` so the fixture is readable and diffable
  and read into the binary at build time so the game runs from anywhere. The level drawn through
  `CellGrid`, by way of a `Ui::LevelCells` adapter that keeps `Level` free of the widget layer.
  Serialization for everything so far, with the terrain stored as the same text a level file
  holds.
* **Verify** — The test level loads and renders, walls in three colours, doors and stairs
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
* **Verify** — Walk around the test level in all eight directions. Walking into a wall does not
  move and does not burn a turn. The camera holds still until the player nears an edge, then
  follows. A spec feeds a scripted key sequence into the app and asserts the final position and
  turn count.

### Phase 6 — Doors, stairs, and winning

* **Build** — Walking into a closed door opens it and costs the turn; `o` and `c` do it
  deliberately. `>` on the down stairs ends the game as a win; `<` on the up stairs leaves. A
  one-line `[yn]` prompt — the first extraction candidate — behind `Q` and behind `<`.
* **Verify** — A scripted sequence opens a door, crosses the level, descends, and the win screen
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
  and a condition of damaged, plain, or masterwork. Naming that composes all of it — "a damaged
  short sword", "a masterwork +1 chain mail", "a swirly potion" before it is identified and "a
  potion of healing" after.
* **Verify** — Specs on naming across the combinations, including the article. Specs that the
  appearance mapping is stable within a seed and differs between seeds. A spec that generating
  ten thousand items under a seed produces the same multiset every time.

### Phase 10 — Floor items, pick up, drop, gold

* **Build** — Items lying on the level, drawn on the map under the player, and named in the
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

## Part 4: Sight and light

The largest part, split so that each step is visible on its own.

### Phase 12 — Field of view

* **Build** — Symmetric shadowcasting from the player over the terrain's sight-blocking flag.
  Everything within the field of view is drawn; everything outside it is blank. No light yet —
  the whole level is treated as lit.
* **Verify** — Standing in a room, the room is visible and the corridor behind the door is not.
  Standing in a corridor, sight runs its length and stops at the corner. Specs against fixture
  maps with the expected visible set written out as a second text file, so a change to the
  algorithm shows as a diff of two maps.

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

### Phase 14 — Knowledge and remembered terrain

The phase that introduces the type monster bands will use in Phase 19.

* **Build** — `Knowledge`: what somebody believes about a level — which tiles they have seen and
  what was on them, where things were when last seen, and how many turns ago each of those was.
  The player gets one. Terrain once seen is remembered and drawn dim; items and monsters are
  remembered as they were, and are not updated while out of sight. The quantized style ramp — the
  fourth extraction candidate — giving a fixed number of steps between lit, dim and unseen, so
  the style table stays bounded no matter how many frames run.
* **Verify** — Walk through a room and out; its shape stays on the map, dimmed, and the item that
  was in it is still drawn where it was even after it is moved. A spec asserts the style table
  stops growing after the first few frames of a long walk. A spec round-trips `Knowledge` through
  serialization.

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

## Part 5: Things that fight back

### Phase 16 — Monsters on the map

* **Build** — A `Monster` with a species, hit points, attributes, a position, a `band` and a
  `faction`. Three species: slime, goblin, orc, each with a glyph, colour and base statistics.
  Placed on the level from the map file, each in a band of one. They block movement and are
  drawn, and the examine pane names them. No behaviour at all.
* **Verify** — All three appear, in the right colours, and hovering one describes it. Walking into
  one is refused with a message. A spec snapshots a level with one of each and round-trips it
  through serialization.

### Phase 17 — Melee combat, death, experience

* **Build** — Walking into a monster attacks it. To-hit from dexterity, weapon and enchantment
  against armour class; damage from the weapon, strength, enchantment and condition. Hit points
  fall, messages say what happened, a monster at zero dies and is removed. The player at zero
  dies and the game ends. Experience awarded per species, driving the levelling from Phase 8.
* **Verify** — Kill a slime with a short sword; the messages read correctly, experience is
  awarded, the level rises at the threshold. Die to an orc and get the death screen. Specs run a
  fixed seed through a hundred exchanges and assert the exact sequence, so a change to the combat
  maths shows as a diff.

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

### Phase 19 — Pathfinding and pursuit

* **Build** — A band's `Knowledge` of the level, seeded with the tiles its monsters have seen. A
  Dijkstra map computed over what the band knows rather than over the truth, which every hunting
  monster descends. Attack when adjacent. Lose the player after a number of turns without seeing
  them and go to the last known square. Slimes do not path — they step toward the player and stop
  at walls. Every AI decision is a function from a snapshot to an `Action`, per the architecture
  rule.
* **Verify** — A goblin on the far side of a wall walks around it rather than into it. Breaking
  line of sight and moving makes it go to where the player was, then give up. A goblin that has
  never seen a shortcut does not use it. Specs on the Dijkstra map over fixture levels, and a
  spec that a hundred turns of pursuit terminates and costs no more than a bounded amount of
  work.

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

### Phase 23 — Running

* **Build** — `G` plus a direction moves repeatedly until something is worth stopping for: a
  monster comes into view, an item or a door or stairs is reached, a corridor branches, hit
  points change, or a message is printed. Each step is a full turn, so monsters act.
* **Verify** — Run down a corridor and stop at the junction. Run into a room and stop at the
  doorway. Run with a goblin in a side passage and stop when it appears. A spec asserts the stop
  condition for each case on a fixture level.

### Phase 24 — Level generation

Everything before this runs on hand-built levels, which is what makes them testable. The
generator comes last because by now it is clear what it has to place.

* **Build** — Rooms and corridors from the seeded RNG. Doors where a corridor meets a room. Up
  and down stairs in different rooms. Rock type varying by region. Items, gold, monsters, bands
  and light sources placed to a density that scales with nothing yet, since there is one floor.
* **Verify** — `--seed N` twice gives the identical level. A spec generates a thousand seeded
  levels and asserts for each: every floor tile is reachable from the up stairs, both staircases
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
| Item variants: appearance, `+N`, damaged and masterwork | 9 |
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

* Levels persist in the save file rather than being regenerated. Leaving and returning finds
  what was left.
* Enemies respawn, and a level is not truly safe until whatever is producing them is found and
  dealt with — hidden spawners, nests, unsealed passages.
* Shortcuts matter, because the alternative is walking the same floors repeatedly. Portals are
  placed by the player, where and when they choose, rather than arriving as a teleport spell.
* The best treasure is not portable: ore seams and resource points that have to be found, cleared
  a path to, and then worked by NPCs recruited in town and escorted back.
* Enemies travel between levels, set up new bases, and lay traps in the direction they expect the
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

### The machinery that needs

* Planning in a `Fiber::ExecutionContext::Parallel`, off the fiber that owns the model and off
  the one that draws, sized by `--threads`.
* Plans that span several turns, each carrying the preconditions it depends on, validated by the
  owner each turn and cancelled when a dependency no longer holds.
* A monster with no plan ready takes a cheap default action rather than stalling the turn, so a
  fleeing player never waits on a planner.

### A place to come back to

* A town level whose shops and residents are attracted by what the player does and what they are
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
* A full-screen map view for a level larger than the pane.
* A message history screen.
* Mouse support for targeting and for the inventory, which `CellGrid#cell_at` already allows.
* Glyph and colour themes.
* A `--replay` mode that re-runs a recorded key sequence against a seed, which would make every
  bug report reproducible.
* Move each of the five general-purpose pieces to `termbuf-widgets.cr` once settled, with the
  specs written here.
