require "../spec_helper"
require "../support/scripted"

# What a run reports, in fields rather than in English.
#
# Every line the model writes to the message log has an event beside it. A bot
# reads the events. `bots/PROTOCOL.md` section 5.2 asks for that, and it asks
# that no event hold a fact the character cannot know.
Spectator.describe Roguelike::Event do
  alias Action = Roguelike::Action
  alias Direction = Roguelike::Direction
  alias Event = Roguelike::Event
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Rng = Roguelike::Rng
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  # The seed every example here runs on.
  SEED = 20260911_u64

  # One room with the staircase down one square east of the character.
  ROOM = ["##########",
          "#........#",
          "#..<>....#",
          "#........#",
          "##########"]

  # Where the character stands.
  HERE = {3, 2}

  # The staircase down, one square east.
  STAIRS = {4, 2}

  # A run on `ROOM`, lit unless *dark*, carrying *items*.
  #
  # The block puts whatever the example needs on the floor.
  #
  # `Game.new` gives out no ids. `Game.start` is what calls `#enroll`, and a
  # floor built by hand has not been through it. Everything is in place before
  # the call, so every item and every creature here has an id.
  def room(items : Array(Item) = [] of Item, dark : Bool = false,
           & : Floor -> _) : Game
    floor = Floor.parse "room", ROOM
    floor.ambient = 1 unless dark
    yield floor

    player = Player.new floor.id, *HERE
    items.each { |item| player.inventory.add item }

    game = Game.new World.new(SEED, {floor.id => floor}), player,
      lore: Roguelike::Lore.roll(Rng.new(SEED))
    game.enroll
    game
  end

  # The events of one scripted run, played through `Game#perform`.
  #
  # `Scripted::MOVES` is the move list the fingerprint spec walks. A digit is
  # a direction and a dot is a turn spent standing still.
  def scripted : Array(Event)
    game = Game.dug Rng.new(SEED)
    found = [] of Event

    Scripted::MOVES.each_char do |move|
      action = if move == '.'
                 Action::Wait.new.as(Action)
               else
                 Action::Move.new(Direction.new(move - '0')).as(Action)
               end

      game.perform action
      found.concat game.events
    end

    found
  end

  describe "a scripted run" do
    it "reports what happened" do
      expect(scripted).not_to be_empty
    end

    # A turn spent standing still and a hit point regenerated write no line.
    # A line a turn would stop every walk and every rest, so both are events
    # and nothing else.
    it "names the line each event was written beside" do
      found = scripted.reject(Event::Waited).reject(Event::Healed)

      expect(found).not_to be_empty
      expect(found.compact_map(&.text).size).to eq found.size
    end

    it "writes no line beside a turn spent standing still" do
      found = scripted.compact_map &.as?(Event::Waited)

      expect(found).not_to be_empty
      expect(found.compact_map(&.text)).to be_empty
    end

    it "round-trips every event it produced" do
      scripted.each do |event|
        back = Event.from_json event.to_json

        expect(back.class).to eq event.class
        expect(back.to_json).to eq event.to_json
      end
    end

    it "names what happened in a field of its own" do
      kinds = scripted.map { |event| JSON.parse(event.to_json)["kind"].as_s }

      expect(kinds).not_to be_empty
      expect(kinds.any?(&.empty?)).to be_false
    end
  end

  describe "one action" do
    it "reports the ground and then what lies on it" do
      dagger = Item.new Kind::Dagger
      game = room(&.drop(STAIRS[0], STAIRS[1], dagger))
      game.perform Action::Move.new(Direction::East)

      expect(game.events.map(&.class)).to eq [Event::Ground, Event::Pile]
    end

    it "names every thing in the pile by its id" do
      dagger = Item.new Kind::Dagger
      rock = Item.new Kind::Rock
      game = room do |floor|
        floor.drop STAIRS[0], STAIRS[1], dagger
        floor.drop STAIRS[0], STAIRS[1], rock
      end
      game.perform Action::Move.new(Direction::East)

      pile = game.events.compact_map(&.as?(Event::Pile)).first
      expect(pile.at).to eq STAIRS
      expect(pile.things.map(&.item)).to eq [dagger.id, rock.id]
      expect(pile.things.map(&.name)).to eq ["a dagger", "a rock"]
    end

    it "empties the list before the next action" do
      game = room do |floor|
        floor.drop STAIRS[0], STAIRS[1], Item.new(Kind::Dagger)
      end
      game.perform Action::Move.new(Direction::East)
      expect(game.events).not_to be_empty

      game.perform Action::Wait.new
      expect(game.events.any?(Event::Pile)).to be_false
    end

    it "reports a door the character opened" do
      floor = Floor.parse "door", ["#####",
                                   "#.+.#",
                                   "#####"]
      floor.ambient = 1
      game = Game.new World.new(SEED, {floor.id => floor}),
        Player.new(floor.id, 1, 1)
      game.enroll
      game.perform Action::Move.new(Direction::East)

      door = game.events.compact_map(&.as?(Event::Door)).first
      expect(door.at).to eq({2, 1})
      expect(door.open?).to be_true
    end

    it "reports a step that went nowhere" do
      game = room { }
      game.perform Action::Move.new(Direction::North)
      game.perform Action::Move.new(Direction::North)

      blocked = game.events.compact_map(&.as?(Event::Blocked)).first
      expect(blocked.dir).to eq Direction::North
      expect(blocked.terrain).to eq "granite"
      expect(blocked.creature).to be_nil
    end

    it "reports a blow and what it took off" do
      creature = Monster.new Species::Goblin, STAIRS[0], STAIRS[1], "band-one"
      game = room(&.place(creature))
      game.perform Action::Move.new(Direction::East)

      blow = game.events.compact_map(&.as?(Event::Attack)).first
      expect(blow.attacker).to be_nil
      expect(blow.target).to eq creature.id
      expect(blow.damage.nil?).to eq !blow.hit?
    end
  end

  describe "what the character cannot know" do
    it "gives a potion its appearance until it is drunk" do
      potion = Item.new Kind::HealingPotion
      game = room [potion] { }
      look = game.lore.appearance(Kind::HealingPotion).to_s
      game.perform Action::Quaff.new(potion.id)

      drunk = game.events.compact_map(&.as?(Event::Used)).first
      found = game.events.compact_map(&.as?(Event::Identified)).first

      expect(look).not_to be_empty
      expect(drunk.verb.drink?).to be_true
      expect(drunk.name.includes?(look)).to be_true
      expect(drunk.name.includes?("healing")).to be_false
      expect(found.name.includes?("healing")).to be_true
      expect(found.appearance).to eq look
    end

    it "does not name a creature the character cannot see" do
      creature = Monster.new Species::Goblin, STAIRS[0], STAIRS[1], "band-one"
      game = room(dark: true, &.place(creature))
      game.run Direction::East

      blocked = game.events.compact_map(&.as?(Event::Blocked)).first
      expect(blocked.unseen?).to be_true
      expect(blocked.creature).to be_nil
    end

    it "names a creature the character can see" do
      creature = Monster.new Species::Goblin, STAIRS[0], STAIRS[1], "band-one"
      game = room(&.place(creature))
      game.run Direction::East

      blocked = game.events.compact_map(&.as?(Event::Blocked)).first
      expect(blocked.unseen?).to be_false
      expect(blocked.creature).to eq creature.id
    end

    it "carries no hit points for a creature" do
      creature = Monster.new Species::Goblin, STAIRS[0], STAIRS[1], "band-one"
      game = room(&.place(creature))
      game.perform Action::Move.new(Direction::East)

      blow = game.events.compact_map(&.as?(Event::Attack)).first
      expect(JSON.parse(blow.to_json).as_h.keys).not_to contain "hit_points"
    end
  end

  describe "serializing" do
    it "names the kind in a field of its own" do
      door = Event::Door.new({1, 2}, open: true)

      expect(JSON.parse(door.to_json)["kind"]).to eq "door"
      expect(JSON.parse(Event::Looming.new.to_json)["kind"]).to eq "looming"
    end

    it "writes an enum as a word" do
      refused = Event::Refused.new :pack_full

      expect(JSON.parse(refused.to_json)["reason"]).to eq "pack_full"
    end

    it "writes a direction the way an action writes one" do
      blocked = Event::Blocked.new Direction::NorthEast

      expect(JSON.parse(blocked.to_json)["dir"]).to eq "ne"
    end
  end
end
