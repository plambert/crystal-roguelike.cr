require "../spec_helper"

Spectator.describe "ants, jellies and flanking" do
  alias Awareness = Roguelike::Awareness
  alias Combat = Roguelike::Combat
  alias Direction = Roguelike::Direction
  alias Event = Roguelike::Event
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Generator = Roguelike::Generator
  alias Kind = Roguelike::Kind
  alias Knowledge = Roguelike::Knowledge
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Rng = Roguelike::Rng
  alias Sharing = Roguelike::Sharing
  alias Species = Roguelike::Species
  alias Spawns = Roguelike::Spawns
  alias World = Roguelike::World

  # An open room, lit, with the character in the middle.
  ROOM = [
    "###############",
    "#.............#",
    "#.............#",
    "#.............#",
    "#.............#",
    "#......<......#",
    "#.............#",
    "#.............#",
    "#.............#",
    "#.............#",
    "###############",
  ]

  # A lit room for the character and a sealed cell beside it. A creature in
  # the cell sees the character and can never reach them.
  CELL = [
    "#################",
    "#.<.....#.......#",
    "#.......#.......#",
    "#.......#.......#",
    "#################",
  ]

  # A game on *lines* with a hunting band of *kind* on each of *spots*.
  #
  # The band has walked the whole floor and last saw the character where
  # they stand. The character has hit points to spare.
  def hunt(lines : Array(String), kind : Kind,
           spots : Array({Int32, Int32})) : {Game, Array(Monster)}
    floor = Playing.daylight Floor.parse("swarm", lines)
    members = spots.map { |spot| Monster.new kind, spot[0], spot[1], "band-one" }
    members.each { |member| floor.place member }

    player = Player.new floor.id, *Game.entrance(floor), hit_points: 5000
    game = Game.new World.new(20260930_u64, {floor.id => floor}), player
    game.enroll

    band = floor.band "band-one"
    raise "the floor has lost the band" unless band

    knowledge = band.knowledge floor.id
    floor.each { |column, row, _tile| knowledge.see floor, column, row }
    knowledge.saw Knowledge::PLAYER, player.x, player.y, game.turn
    band.awareness = Awareness::Hunting

    {game, members}
  end

  # Whether *member* has a bandmate across the character from it.
  def flanking?(game : Game, member : Monster) : Bool
    across = Combat.opposite member.at, game.player.at
    other = game.floor.monster across[0], across[1]
    !other.nil? && other.band == member.band
  end

  # Whether *member* stands beside the character.
  def beside?(game : Game, member : Monster) : Bool
    (member.x - game.player.x).abs <= 1 && (member.y - game.player.y).abs <= 1
  end

  describe "the flanking rule" do
    it "reflects an attacker through the target, diagonals included" do
      expect(Combat.opposite({4, 5}, {5, 5})).to eq({6, 5})
      expect(Combat.opposite({4, 4}, {5, 5})).to eq({6, 6})
      expect(Combat.opposite({6, 4}, {5, 5})).to eq({4, 6})
    end

    it "gives +2 to an attacker with another across the target, and nothing otherwise" do
      target = {5, 5}

      Direction.values.each do |direction|
        attacker = direction.from 5, 5
        across = direction.opposite.from 5, 5

        expect(Combat.flanking(attacker, target) { |spot| spot == across }).to eq 2
        expect(Combat.flanking(attacker, target) { |spot| spot != across }).to eq 0
      end
    end

    it "applies to both attackers of a pair alike" do
      target = {5, 5}
      pair = [{4, 4}, {6, 6}]

      pair.each do |attacker|
        expect(Combat.flanking(attacker, target) { |spot| pair.includes? spot }).to eq Combat::FLANKING
      end
    end
  end

  describe "a character with attackers on opposite sides" do
    it "is told once, and each blow says it came from behind" do
      game, _ = hunt ROOM, Kind::GoblinWarrior, [{6, 5}, {8, 5}]

      10.times { game.wait }

      expect(game.log.lines.count &.==("You are flanked!")).to eq 1
      expect(game.log.lines.any? &.includes?("you from behind")).to be_true
      expect(game.flanked?).to be_true
    end

    it "marks the blow as flanking in its event" do
      game, _ = hunt ROOM, Kind::GoblinWarrior, [{6, 5}, {8, 5}]

      game.perform Roguelike::Action::Wait.new

      attacks = game.events.compact_map &.as?(Event::Attack)
      expect(attacks.size).to eq 2
      expect(attacks.all? { |attack| attack.flanking == true }).to be_true
    end

    it "is not flanked by one creature" do
      game, _ = hunt ROOM, Kind::GoblinWarrior, [{6, 5}]

      10.times { game.wait }

      expect(game.flanked?).to be_false
      expect(game.log.lines.none? &.includes?("from behind")).to be_true
    end
  end

  describe "a band of ants" do
    it "surrounds the character in an open room" do
      game, ants = hunt ROOM, Kind::Ant, [{1, 1}, {2, 1}, {1, 2}, {2, 2}]

      turns = (1..20).find do
        game.wait
        ants.all? { |ant| beside?(game, ant) && flanking?(game, ant) }
      end

      expect(turns).not_to be_nil
      expect(turns.try &.<= 10).to be_true
    end

    it "puts two of three across from each other" do
      game, ants = hunt ROOM, Kind::Ant, [{1, 1}, {2, 1}, {1, 2}]

      turns = (1..20).find do
        game.wait
        ants.count { |ant| beside?(game, ant) && flanking?(game, ant) } >= 2
      end

      expect(turns).not_to be_nil
    end

    it "shares what it knows as a hive" do
      game, _ = hunt ROOM, Kind::Ant, [{1, 1}]

      expect(game.floor.band("band-one").try &.sharing).to eq Sharing::Hive
    end

    it "is placed three to five strong, as a hive, from floor 2" do
      found = [] of Int32

      10.times do |index|
        floor = Generator.floor Rng.new(7000_u64 + index), World.id(2), 2
        counts = Hash(String, Int32).new 0
        floor.each_monster do |_column, _row, creature|
          counts[creature.band] += 1 if creature.kind == Kind::Ant
        end

        counts.each do |band, count|
          expect(floor.band(band).try &.sharing).to eq Sharing::Hive
          found << count
        end
      end

      expect(found).not_to be_empty
      found.each { |count| expect(count).to be_between(3, 5) }
    end

    it "never appears on floor 1" do
      expect(Spawns.weights(1).has_key? Kind::Ant).to be_false
      expect(Spawns.crowd Kind::Ant, 2).to eq 3..5
    end
  end

  describe "a jelly" do
    # A game with a hunting jelly beside the character, who never swings
    # back.
    def cell : {Game, Monster}
      game, members = hunt ROOM, Kind::Jelly, [{8, 5}]
      {game, members.first}
    end

    # Every jelly on the floor.
    def jellies(game : Game) : Array(Monster)
      found = [] of Monster
      game.floor.each_monster { |_column, _row, creature| found << creature if creature.species.jelly? }
      found
    end

    it "splits into a second jelly of its band beside it" do
      game, jelly = cell

      (Game::SPLIT_EVERY - 1).times { game.wait }
      expect(jellies(game).size).to eq 1

      game.wait

      found = jellies game
      expect(found.size).to eq 2
      copy = found.find! { |other| !other.same? jelly }
      expect(copy.band).to eq jelly.band
      expect((copy.x - jelly.x).abs <= 1 && (copy.y - jelly.y).abs <= 1).to be_true
      expect(copy.id).not_to eq 0
    end

    it "stops at the cap" do
      game, _ = cell

      (Game::SPLIT_EVERY * 12).times { game.wait }

      expect(jellies(game).size).to eq Game::JELLIES
    end

    it "does not split at half its hit points or below" do
      game, jelly = cell
      half = jelly.max_hit_points // 2

      # Creatures recover a hit point every ten turns, so the jelly is held
      # at half throughout.
      (Game::SPLIT_EVERY * 2).times do
        jelly.hurt jelly.hit_points - half
        game.wait
      end

      expect(jellies(game).size).to eq 1
    end

    it "splits the same way from the same seed" do
      first, _ = cell
      second, _ = cell

      (Game::SPLIT_EVERY * 4).times do
        first.wait
        second.wait
      end

      expect(jellies(first).map(&.at)).to eq jellies(second).map(&.at)
      expect(first.fingerprint).to eq second.fingerprint
    end
  end

  describe "a save" do
    it "round-trips a split count, a flanked run and a jelly's count" do
      game, members = hunt ROOM, Kind::Jelly, [{8, 5}]
      jelly = members.first
      (Game::SPLIT_EVERY + 5).times { game.wait }

      again = Game.from_json game.to_json

      expect(again.splits).to eq game.splits
      expect(again.splits).to eq 1
      expect(again.floor.monster(jelly.x, jelly.y).try &.bud).to eq jelly.bud
      expect(again.fingerprint).to eq game.fingerprint
    end

    it "keeps a flanked run flanked" do
      game, _ = hunt ROOM, Kind::GoblinWarrior, [{6, 5}, {8, 5}]
      game.wait

      expect(Game.from_json(game.to_json).flanked?).to be_true
    end

    it "loads a run saved before splits and flanking as neither" do
      game, _ = hunt ROOM, Kind::GoblinWarrior, [{6, 5}]
      text = game.to_json

      expect(text).not_to contain "\"splits\""
      expect(text).not_to contain "\"flanked\""
      expect(text).not_to contain "\"bud\""

      again = Game.from_json text
      expect(again.splits).to eq 0
      expect(again.flanked?).to be_false
    end
  end

  describe "a fight with ants" do
    it "plays out the same from the same seed" do
      first, _ = hunt ROOM, Kind::Ant, [{1, 1}, {2, 1}, {1, 2}, {2, 2}]
      second, _ = hunt ROOM, Kind::Ant, [{1, 1}, {2, 1}, {1, 2}, {2, 2}]

      30.times do
        first.wait
        second.wait
      end

      expect(first.fingerprint).to eq second.fingerprint
      expect(first.player.hit_points).to be < 5000
    end
  end
end
