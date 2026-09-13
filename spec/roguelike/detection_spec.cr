require "../spec_helper"

Spectator.describe "noticing the character" do
  alias Awareness = Roguelike::Awareness
  alias Direction = Roguelike::Direction
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Knowledge = Roguelike::Knowledge
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  SEED = 20260912_u64

  # A straight corridor with the character at one end.
  #
  # One square wide, so there is nowhere to walk but toward whatever is at
  # the far end, and nothing but corridor between the two.
  CORRIDOR = [
    "################",
    "#<.............#",
    "################",
  ]

  # Where the character starts in the corridor.
  HERE = {1, 1}

  # A room with the character in it and space to walk round a creature.
  ROOM = [
    "#######",
    "#.....#",
    "#.<.g.#",
    "#.....#",
    "#######",
  ]

  # A game in the room. *ambient* and *torch* work as they do in `#corridor`.
  def room(ambient : Int32 = 0, torch : Bool = false) : {Game, Monster}
    floor = Floor.parse "room", ROOM
    floor.ambient = ambient

    creature = floor.monster(4, 2)
    raise "the room has lost its goblin" unless creature

    player = Player.new floor.id, *Game.entrance(floor)
    player.inventory.add Item.new(Kind::Torch, lit: true) if torch

    {Game.new(World.new(SEED, {floor.id => floor}), player), creature}
  end

  # Walks right round the creature in the room, along the north side and back
  # along the south. Every square on the way is touching it or one off, and
  # none of them is the square it stands on.
  ROUND = [Direction::East, Direction::North, Direction::East, Direction::East,
           Direction::South, Direction::South, Direction::West, Direction::West]

  # A game in the corridor with one creature *away* squares off.
  #
  # *ambient* is the light the floor has of its own: nothing makes a dark
  # corridor. *torch* gives the character a lit one. *stealth* is theirs.
  def corridor(species : Species = Species::Goblin,
               away : Int32 = 12,
               ambient : Int32 = 0,
               torch : Bool = false,
               stealth : Int32 = Roguelike::Attributes::AVERAGE) : {Game, Monster}
    floor = Floor.parse "corridor", CORRIDOR
    floor.ambient = ambient

    creature = Monster.new species, HERE[0] + away, HERE[1], "band-one"
    floor.place creature

    player = Player.new floor.id, *HERE,
      Roguelike::Attributes.new(stealth: stealth)
    player.inventory.add Item.new(Kind::Torch, lit: true) if torch

    {Game.new(World.new(SEED, {floor.id => floor}), player), creature}
  end

  # What the band the creature belongs to knows.
  def awareness(game : Game, creature : Monster) : Awareness
    game.floor.awareness creature
  end

  # Walks *steps* east. A step that says nothing still takes a turn.
  def walk(game : Game, steps : Int32) : Nil
    steps.times { game.step Direction::East }
  end

  describe "a dark corridor" do
    # The whole of the Verify line for this phase, in three examples.
    it "lets a quiet character with no torch walk the length of it" do
      game, creature = corridor stealth: 18

      walk game, 10

      expect(awareness(game, creature)).to eq Awareness::Asleep
      expect(game.player.hit_points).to eq game.player.max_hit_points
    end

    # The torch lights the character brightly enough for the goblin to pick
    # them out from the far end. The character cannot see the goblin at that
    # range, so what they get is the sound of it rather than its name.
    it "wakes the same goblin for a character carrying a torch" do
      game, creature = corridor stealth: 18, torch: true

      walk game, 10

      expect(awareness(game, creature)).to eq Awareness::Hunting
      expect(game.log.lines).to contain "You hear something stir."
    end

    it "wakes an orc either way" do
      dark, orc = corridor Species::Orc, stealth: 18
      lit, other = corridor Species::Orc, stealth: 18, torch: true

      walk dark, 8
      walk lit, 8

      expect(awareness(dark, orc)).to eq Awareness::Hunting
      expect(awareness(lit, other)).to eq Awareness::Hunting
    end
  end

  describe "a dim corridor" do
    # A floor with a glimmer of its own lights the character wherever they
    # stand, so stealth is the only thing left that hides them.
    it "notices a loud character further off than a quiet one" do
      loud, first = corridor ambient: 1, stealth: 4
      quiet, second = corridor ambient: 1, stealth: 18

      walk loud, 3
      walk quiet, 3

      expect(awareness(loud, first)).to eq Awareness::Hunting
      expect(awareness(quiet, second)).to eq Awareness::Asleep
    end

    it "notices the quiet character once they are close enough" do
      game, creature = corridor ambient: 1, stealth: 18

      walk game, 8

      expect(awareness(game, creature)).to eq Awareness::Hunting
    end
  end

  describe "a band that has noticed" do
    it "writes down where the character was" do
      game, creature = corridor ambient: 1

      walk game, 5

      band = game.floor.band creature.band
      seen = band.try &.knowledge(game.floor.id).sighting(Knowledge::PLAYER)

      expect(seen).not_to be_nil
      expect(seen.try &.at).to eq game.player.at
    end

    it "keeps its own knowledge apart from the creature's" do
      game, creature = corridor ambient: 1

      walk game, 5

      band = game.floor.band creature.band
      expect(band.try &.knowledge(game.floor.id).sightings.empty?).to be_false
      expect(creature.knowledge(game.floor.id).sightings.empty?).to be_true
    end

    it "loses the character when it cannot see them any more" do
      game, creature = corridor ambient: 1

      walk game, 8
      expect(awareness(game, creature)).to eq Awareness::Hunting

      game.floor.ambient = 0
      game.step Direction::West

      expect(awareness(game, creature)).to eq Awareness::Alert
    end

    it "stays awake once it has woken" do
      game, creature = corridor ambient: 1

      walk game, 8
      game.floor.ambient = 0
      game.step Direction::West

      expect(game.awake? creature).to be_true
    end
  end

  describe "a band that has not noticed" do
    # A creature that has not noticed the character does not swing at them,
    # however close they walk.
    it "does not swing at a character walking round it in the dark" do
      game, creature = room

      ROUND.each { |direction| game.step direction }

      swung = game.log.lines.any? &.starts_with?("The goblin")

      expect(awareness(game, creature)).to eq Awareness::Asleep
      expect(game.player.hit_points).to eq game.player.max_hit_points
      expect(game.turn).to eq ROUND.size
      expect(swung).to be_false
    end

    # The same walk with a lit torch. The goblin is standing right there.
    it "swings at the same character carrying a torch" do
      game, creature = room torch: true

      ROUND.each { |direction| game.step direction }

      expect(awareness(game, creature)).not_to eq Awareness::Asleep
      expect(game.player.hit_points).to be < game.player.max_hit_points
    end

    # A stabbed goblin in a dark corridor knows something is there. It still
    # cannot see what, so it ends the turn looking rather than hunting.
    it "wakes when it is hit" do
      game, creature = corridor away: 1

      expect(awareness(game, creature)).to eq Awareness::Asleep

      game.attack creature

      expect(game.awake? creature).to be_true
      expect(awareness(game, creature)).to eq Awareness::Alert
      expect(game.log.lines).to contain "The goblin notices you."
    end

    # It cannot see who hit it. It knows which side the blow came from, so it
    # swings back at the dark.
    it "swings back at a character it cannot see" do
      game, creature = corridor away: 1

      before = game.player.hit_points
      30.times do
        break if game.player.hit_points < before

        game.attack creature
      end

      expect(game.player.hit_points).to be < before
      expect(game.log.lines.any? &.starts_with?("The goblin")).to be_true
    end

    it "hunts what it can see when it is hit" do
      game, creature = corridor away: 1, ambient: 1

      game.floor.band(creature.band).try &.awareness = Awareness::Asleep
      game.attack creature

      expect(awareness(game, creature)).to eq Awareness::Hunting
    end
  end

  describe "what the character hears" do
    it "names a creature they can see" do
      game, _ = corridor ambient: 1

      walk game, 5

      expect(game.log.lines).to contain "The goblin notices you."
    end

    # An orc in a dark corridor notices the character long before the
    # character can see the orc.
    it "does not name one they cannot see" do
      game, _ = corridor Species::Orc, away: 6

      game.step Direction::East

      expect(game.log.lines).to contain "You hear something stir."
      expect(game.log.lines.none? &.includes?("orc")).to be_true
    end

    it "says it once rather than every turn" do
      game, _ = corridor ambient: 1

      walk game, 8

      said = game.log.lines.count &.== "The goblin notices you."
      expect(said).to eq 1
    end
  end

  describe "serialization" do
    it "carries the awareness through" do
      game, creature = corridor ambient: 1
      walk game, 5

      again = Game.from_json game.to_json
      band = again.floor.band creature.band

      expect(band.try &.awareness).to eq Awareness::Hunting
    end
  end
end
