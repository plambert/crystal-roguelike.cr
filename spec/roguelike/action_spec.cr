require "../spec_helper"

# A run that keeps every action that reached the one entry point.
#
# A run of several steps is the case this is for. Counting at the seam is
# what says the steps went through `#perform`; counting where the character
# ended up would pass just as well if they had gone round it.
class Counted < Roguelike::Game
  @[JSON::Field(ignore: true)]
  getter taken : Array(Roguelike::Action) = [] of Roguelike::Action

  def perform(action : Roguelike::Action) : Roguelike::Verdict
    @taken << action
    super
  end
end

Spectator.describe Roguelike::Action do
  alias Action = Roguelike::Action
  alias Direction = Roguelike::Direction
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Slot = Roguelike::Slot
  alias Species = Roguelike::Species
  alias Terrain = Roguelike::Terrain

  # One lit room with a shut door one square north of the character and an
  # open one one square south, the staircase up under them and the one down
  # beside them.
  #
  # Everything a verb needs is within a square, so `Game#legal` has an answer
  # of every shape to give.
  ROOM = ["##########",
          "#..+.....#",
          "#..<>....#",
          "#..'.....#",
          "##########"]

  # Where the character stands.
  HERE = {3, 2}

  # A run on `ROOM` carrying *items*, with a dagger and a rock underfoot.
  def stocked(items : Array(Item) = kit) : Roguelike::Game
    floor = Playing.daylight Roguelike::Floor.parse("room", ROOM)
    player = Roguelike::Player.new "room", *HERE
    items.each { |item| player.inventory.add item }

    game = Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"room" => floor}), player)
    floor.drop HERE[0], HERE[1], Item.new(Kind::Dagger)
    floor.drop HERE[0], HERE[1], Item.new(Kind::Rock)
    game
  end

  # Something of every shape a verb can name.
  def kit : Array(Item)
    [Item.new(Kind::ShortSword),
     Item.new(Kind::LeatherArmour),
     Item.new(Kind::Torch, lit: true),
     Item.new(Kind::HealingPotion),
     Item.new(Kind::IdentifyScroll),
     Item.new(Kind::BlessingScroll),
     Item.new(Kind::StrikingWand)]
  end

  # *game* written out, which is every field of it that a save holds.
  def state(game : Roguelike::Game) : String
    game.to_json
  end

  # A copy of *game* that shares nothing with it.
  def copy(game : Roguelike::Game) : Roguelike::Game
    Roguelike::Game.from_json game.to_json
  end

  # A lit corridor with the character at the west end and nothing on it, so
  # a run down it stops only when it reaches the far wall.
  HALL = ["############",
          "#..........#",
          "############"]

  # A run on `HALL` that counts what reaches `#perform`.
  def hall : Counted
    floor = Playing.daylight Roguelike::Floor.parse("hall", HALL)

    Counted.new Roguelike::World.new(Playing::SEED, {"hall" => floor}),
      Roguelike::Player.new("hall", 1, 1)
  end

  # A run with a scroll of blessing read and its question still up.
  def waiting : Roguelike::Game
    game = stocked
    game.perform Action::Read.new('f')
    game
  end

  # One of every verb, so nothing can be added without a line here.
  def every_verb : Array(Action)
    [Action::Move.new(Direction::NorthEast),
     Action::Wait.new,
     Action::Open.new(Direction::North),
     Action::Close.new(Direction::South),
     Action::PickUp.new,
     Action::PickUp.new(1),
     Action::Drop.new('d'),
     Action::Wield.new('a'),
     Action::Wear.new('b'),
     Action::Remove.new(Slot::Melee),
     Action::Quaff.new('d'),
     Action::Read.new('e', 'a'),
     Action::Zap.new('g', {5, 2}),
     Action::Apply.new(item: 'c'),
     Action::Apply.new(at: {2, 3}),
     Action::Fire.new({6, 2}),
     Action::Throw.new('a', {6, 2}),
     Action::Descend.new,
     Action::Ascend.new,
     Action::Choose.new('a'),
     Action::Choose.new,
     Action::Aim.new({6, 2}),
     Action::Aim.new] of Action
  end

  describe "serializing" do
    it "round-trips every verb through JSON" do
      every_verb.each do |action|
        text = action.to_json
        back = Action.from_json text

        expect(back.class).to eq action.class
        expect(back.to_json).to eq text
      end
    end

    it "names the verb in a field of its own" do
      expect(JSON.parse(Action::Wait.new.to_json)["t"]).to eq "wait"
      expect(JSON.parse(Action::PickUp.new.to_json)["t"]).to eq "pickup"
      expect(JSON.parse(Action::Remove.new(Slot::Head).to_json)["t"]).to eq "remove"
    end

    it "writes a direction the way the protocol does" do
      expect(Action::Move.new(Direction::NorthEast).to_json)
        .to eq %({"t":"move","dir":"ne"})
      expect(Action::Move.new(Direction::South).to_json)
        .to eq %({"t":"move","dir":"s"})
    end

    it "reads a direction back off its short name" do
      found = Action.from_json %({"t":"move","dir":"sw"})

      expect(found.as(Action::Move).dir).to eq Direction::SouthWest
    end

    it "refuses a direction it does not know" do
      expect { Action.from_json %({"t":"move","dir":"up"}) }
        .to raise_error JSON::ParseException
    end

    it "writes a slot in lower case" do
      expect(Action::Remove.new(Slot::Ranged).to_json)
        .to eq %({"t":"remove","slot":"ranged"})
    end

    it "writes a square as a pair" do
      expect(Action::Fire.new({4, 9}).to_json)
        .to eq %({"t":"fire","target":[4,9]})
    end
  end

  describe "#legal" do
    it "offers every verb the run allows" do
      game = stocked
      game.floor.place Monster.new(Species::Goblin, 6, 2, "band-one")
      found = game.legal.map &.class

      expect(found).to contain Action::Move
      expect(found).to contain Action::Wait
      expect(found).to contain Action::Open
      expect(found).to contain Action::Close
      expect(found).to contain Action::PickUp
      expect(found).to contain Action::Drop
      expect(found).to contain Action::Wield
      expect(found).to contain Action::Wear
      expect(found).to contain Action::Quaff
      expect(found).to contain Action::Read
      expect(found).to contain Action::Zap
      expect(found).to contain Action::Apply
      expect(found).to contain Action::Throw
      expect(found).to contain Action::Ascend
    end

    it "offers the staircase the character is standing on and no other" do
      game = stocked

      expect(game.legal.map &.class).not_to contain Action::Descend

      game.perform Action::Move.new(Direction::East)

      expect(game.legal.map &.class).to contain Action::Descend
      expect(game.legal.map &.class).not_to contain Action::Ascend
    end

    it "offers to take off what is readied" do
      game = stocked

      expect(game.legal.map &.class).not_to contain Action::Remove

      game.perform Action::Wield.new('a')

      expect(game.legal.compact_map { |action| action.as?(Action::Remove).try &.slot })
        .to eq [Slot::Melee]
    end

    it "offers no step into a wall" do
      game = stocked
      game.player.move_to({1, 1})
      ways = game.legal.compact_map { |action| action.as?(Action::Move).try &.dir }

      expect(ways).not_to contain Direction::West
      expect(ways).not_to contain Direction::North
      expect(ways).to contain Direction::East
    end

    it "offers a step into a creature, which is a swing at it" do
      game = stocked
      game.floor.place Monster.new(Species::Goblin, 4, 2, "band-one")
      ways = game.legal.compact_map { |action| action.as?(Action::Move).try &.dir }

      expect(ways).to contain Direction::East
    end

    it "offers nothing to shoot with an empty quiver" do
      game = stocked
      game.floor.place Monster.new(Species::Goblin, 6, 2, "band-one")

      expect(game.legal.map &.class).not_to contain Action::Fire
    end

    it "offers a shot at each creature in sight once the bow is readied" do
      game = stocked kit + [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: 5)]
      game.wield 'h'
      game.wield 'i'
      game.floor.place Monster.new(Species::Goblin, 6, 2, "band-one")

      shots = game.legal.compact_map { |action| action.as?(Action::Fire).try &.target }

      expect(shots).to eq [{6, 2}]
    end

    it "offers a throw at each creature in sight and none with nothing in sight" do
      game = stocked
      expect(game.legal.map &.class).not_to contain Action::Throw

      game.floor.place Monster.new(Species::Goblin, 6, 2, "band-one")

      expect(game.legal.map &.class).to contain Action::Throw
    end

    it "offers nothing at all once the run is over" do
      game = stocked
      game.player.move_to({4, 2})
      game.descend

      expect(game.over?).to be_true
      expect(game.legal).to be_empty
    end

    it "offers only the answer while a scroll is waiting for one" do
      game = stocked
      game.perform Action::Read.new('f')

      expect(game.asking).not_to be_nil
      expect(game.legal.map(&.class).uniq!).to eq [Action::Choose]
    end
  end

  describe "#perform" do
    it "takes every action #legal offers" do
      game = stocked
      game.floor.place Monster.new(Species::Goblin, 6, 2, "band-one")

      game.legal.each do |action|
        found = copy(game).perform action

        expect(found.allowed).to be_true, "refused #{action.to_json}"
      end
    end

    # The question is not in the save, so a copy of the run has already given
    # it up. Each answer is tried on a run played up to the question again.
    it "takes every action #legal offers while a scroll is waiting" do
      waiting.legal.each do |action|
        found = waiting.perform action

        expect(found.allowed).to be_true, "refused #{action.to_json}"
      end
    end

    # This is what `Game#start_reading` already said: the two halves hold
    # nothing between them. A run written out with the question up has spent
    # the scroll and the turn and has given up what the second half would
    # have done. Moving the scroll onto `Game#asking` did not change it.
    it "gives the question up when the run is written out and read back" do
      game = waiting
      expect(game.asking).not_to be_nil
      spent = game.turn

      back = copy game

      expect(back.asking).to be_nil
      expect(back.turn).to eq spent
      expect(back.perform(Action::Choose.new('a')).refused?).to be_true
    end

    it "refuses the wrong kind of answer to a waiting scroll" do
      game = waiting
      before = state game

      expect(game.perform(Action::Aim.new({5, 2})).refused?).to be_true
      expect(state game).to eq before
      expect(game.asking).not_to be_nil
    end

    # The sample is one of each shape of refusal: a letter holding nothing, a
    # letter holding the wrong kind of thing, a square with no pile on it, a
    # slot with nothing in it, a sconce out of reach, and an answer to a
    # question nobody asked.
    it "refuses an action the run does not allow, and spends nothing on it" do
      refused = [Action::Quaff.new('z'),
                 Action::Quaff.new('a'),
                 Action::Read.new('a'),
                 Action::Zap.new('a'),
                 Action::Drop.new('z'),
                 Action::Wield.new('z'),
                 Action::Wear.new('z'),
                 Action::Remove.new(Slot::Head),
                 Action::PickUp.new(9),
                 Action::Apply.new(item: 'a'),
                 Action::Apply.new(at: {8, 3}),
                 Action::Throw.new('z', {6, 2}),
                 Action::Choose.new('a'),
                 Action::Aim.new({6, 2})] of Action

      refused.each do |action|
        game = stocked
        before = state game
        turn = game.turn

        found = game.perform action

        expect(found.refused?).to be_true, "took #{action.to_json}"
        expect(game.turn).to eq turn
        expect(state game).to eq before
      end
    end

    it "refuses everything once the run is over" do
      game = stocked
      game.player.move_to({4, 2})
      game.descend
      before = state game

      expect(game.perform(Action::Wait.new).refused?).to be_true
      expect(state game).to eq before
    end

    it "refuses to take one of a pile without saying which" do
      game = stocked
      before = state game

      expect(game.perform(Action::PickUp.new).refused?).to be_true
      expect(state game).to eq before
    end

    it "takes the only thing underfoot without being told which" do
      game = stocked
      game.floor.items(*HERE).dup.each { |item| game.floor.take HERE[0], HERE[1], item }
      game.floor.drop HERE[0], HERE[1], Item.new(Kind::Rock)

      expect(game.perform(Action::PickUp.new).allowed).to be_true
      expect(game.floor.items?(*HERE)).to be_false
    end

    it "answers what a move came to" do
      game = stocked

      expect(game.perform(Action::Move.new(Direction::East)).step)
        .to eq Roguelike::Step::Moved
      expect(game.perform(Action::Move.new(Direction::North)).step)
        .to eq Roguelike::Step::Moved
    end

    it "lets a rule refuse without calling the action illegal" do
      game = stocked
      turn = game.turn

      # There is no door east of the character. `Game#open` says so and
      # spends no turn, and that is its answer rather than a refusal here.
      found = game.perform Action::Open.new(Direction::East)

      expect(found.allowed).to be_true
      expect(game.turn).to eq turn
      expect(game.log.last?.to_s).to contain "nothing to open"
    end
  end

  describe "a scripted game" do
    # Everything below is played twice: once by calling the verbs the way
    # `Ui::Play` used to, and once through `#perform`. The two runs must end
    # on the same state, which is what says `#perform` routes and decides
    # nothing.
    it "reaches the same state through #perform as through the verbs" do
      direct = stocked
      direct.pick_up direct.here.first
      direct.step Direction::East
      direct.wait
      direct.wield 'a'
      direct.wear 'b'
      direct.quaff 'd'
      direct.step Direction::West
      direct.open Direction::North
      direct.drop 'd'
      direct.take_off Slot::Melee

      routed = stocked
      [Action::PickUp.new(0),
       Action::Move.new(Direction::East),
       Action::Wait.new,
       Action::Wield.new('a'),
       Action::Wear.new('b'),
       Action::Quaff.new('d'),
       Action::Move.new(Direction::West),
       Action::Open.new(Direction::North),
       Action::Drop.new('d'),
       Action::Remove.new(Slot::Melee)].each { |action| routed.perform action }

      expect(routed.turn).to eq direct.turn
      expect(state routed).to eq state direct
    end

    it "reads a scroll that asks afterwards the same way either road" do
      direct = stocked
      scroll = direct.start_reading 'f'
      direct.finish_reading scroll.as(Item), 'a'

      routed = stocked
      routed.perform Action::Read.new('f')
      routed.perform Action::Choose.new('a')

      expect(routed.asking).to be_nil
      expect(state routed).to eq state direct
    end

    it "reads a scroll that names its item up front the same way either road" do
      direct = stocked
      direct.read 'e', 'd'

      routed = stocked
      routed.perform Action::Read.new('e', 'd')

      expect(state routed).to eq state direct
    end
  end
  describe "a run" do
    # A run is not an action of its own. Every step of one is, and each has
    # to reach the same entry point a key press reaches, or a replay records
    # a run as nothing at all and the character is somewhere else on
    # playback.
    it "takes every step through the one entry point" do
      game = hall
      walk = game.running Direction::East
      while game.stride walk
      end

      expect(walk.steps).to be > 1
      expect(game.taken.size).to eq walk.steps
      expect(game.taken.map &.class).to eq Array.new(walk.steps, Action::Move)
      expect(game.taken.compact_map { |one| one.as?(Action::Move).try &.dir }.uniq!)
        .to eq [Direction::East]
    end

    it "leaves the character where the run took them" do
      game = hall
      start = game.player.at

      walk = game.running Direction::East
      while game.stride walk
      end

      expect(game.player.at).to eq({start[0] + walk.steps, start[1]})
      expect(game.turn).to eq walk.steps
    end

    it "counts a route the same way" do
      game = hall
      route = [{1, 1}, {2, 1}, {3, 1}, {4, 1}]

      walk = game.walking route
      while game.stride walk
      end

      expect(game.taken.map &.class).to eq Array.new(walk.steps, Action::Move)
      expect(game.player.at).to eq({4, 1})
    end
  end
end
