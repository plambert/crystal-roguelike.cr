require "../spec_helper"

Spectator.describe "achievements" do
  alias Achievement = Roguelike::Achievement
  alias Action = Roguelike::Action
  alias Event = Roguelike::Event
  alias Fingerprint = Roguelike::Fingerprint
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Kind = Roguelike::Kind
  alias Player = Roguelike::Player
  alias Placards = Roguelike::Ui::Placards
  alias Sustenance = Roguelike::Sustenance
  alias World = Roguelike::World

  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "############",
  ]

  # A starving orc in a lit hall, over an orc corpse.
  #
  # No human creature spawns, so the character is made an orc to stand a
  # corpse of their own species underfoot.
  def among_orcs : Game
    floor = Playing.daylight Floor.parse("hall", HALL)
    player = Player.new floor.id, 1, 1
    player.sustenance.hunger = Sustenance::STARVING
    player.species = "orc"
    game = Game.new World.new(Playing::SEED, {floor.id => floor}), player
    game.floor.drop 1, 1, Game.remains_of(Kind::Orc).first
    game.enroll
    game
  end

  def earned_at(time : Time, name : String = Achievement::CANNIBAL, turn : Int32 = 7) : Achievement
    Achievement.new name, turn, time
  end

  describe Roguelike::Player do
    it "starts with none" do
      expect(Player.new("hall", 1, 1).achievements).to be_empty
    end

    it "earns each one once, in order" do
      player = Player.new "hall", 1, 1
      first = Time.utc 2026, 11, 3, 12, 0, 0
      expect(player.earn earned_at(first)).to be_true
      expect(player.earn earned_at(first + 1.minute)).to be_false
      expect(player.earn earned_at(first, "later", 9)).to be_true

      expect(player.achievements.map(&.name)).to eq [Achievement::CANNIBAL, "later"]
      expect(player.achievements.first.earned).to eq first
    end

    it "keeps the list through a save" do
      player = Player.new "hall", 1, 1
      player.earn earned_at(Time.utc 2026, 11, 3, 12, 0, 0)
      loaded = Player.from_json(player.to_json).achievements

      expect(loaded.map { |found| {found.name, found.turn} }).to eq [{Achievement::CANNIBAL, 7}]
      expect(loaded.first.earned).to eq Time.utc(2026, 11, 3, 12, 0, 0)
    end

    it "writes no list for a character who has earned nothing, and loads an old save with none" do
      json = Player.new("hall", 1, 1).to_json
      expect(json).not_to contain "achievements"
      expect(Player.from_json(json).achievements).to be_empty
    end
  end

  describe "the fingerprint" do
    it "leaves the wall clock time out of the streamed scheme" do
      one = Player.new "hall", 1, 1
      other = Player.new "hall", 1, 1
      one.earn earned_at(Time.utc 2026, 11, 3, 12, 0, 0)
      other.earn earned_at(Time.utc 2027, 1, 1, 0, 0, 0)

      expect(Fingerprint.streamed one).to eq Fingerprint.streamed(other)
      expect(Fingerprint.streaming { one.to_json }).not_to contain "earned"
      expect(one.to_json).to contain "earned"
    end

    it "still counts the name and the turn" do
      one = Player.new "hall", 1, 1
      other = Player.new "hall", 1, 1
      time = Time.utc 2026, 11, 3, 12, 0, 0
      one.earn earned_at(time, turn: 7)
      other.earn earned_at(time, turn: 8)

      expect(Fingerprint.streamed one).not_to eq Fingerprint.streamed(other)
    end
  end

  describe "cannibal" do
    it "is earned with the turn and the time the first meal of one's own kind was eaten" do
      game = among_orcs
      before = Time.utc
      game.perform Action::Eat.new(game.here.first.id)
      after = Time.utc

      found = game.player.achievements
      expect(found.map(&.name)).to eq [Achievement::CANNIBAL]
      expect(found.first.turn).to eq 0
      expect(found.first.earned).to be >= before
      expect(found.first.earned).to be <= after

      events = game.events.select(Event::Achieved).map(&.as(Event::Achieved))
      expect(events.map { |event| {event.name, event.turn} }).to eq [{Achievement::CANNIBAL, 0}]
      expect(game.log.lines).to contain "You earn an achievement: cannibal."
    end

    it "is earned only once" do
      game = among_orcs
      game.floor.drop 1, 1, Game.remains_of(Kind::Orc).first
      game.enroll
      2.times { game.perform Action::Eat.new(game.here.first.id) }

      expect(game.player.achievements.size).to eq 1
      expect(game.events.any?(Event::Achieved)).to be_false
    end
  end

  describe "the screens" do
    it "lists them under the scores in the character pane" do
      game = among_orcs
      run = Playing.open game, 80, 40
      expect(run.play.character.achieved.hidden?).to be_true

      run.game.perform Action::Eat.new(run.game.here.first.id)
      run.play.refresh

      pane = run.play.character
      expect(pane.achieved.hidden?).to be_false
      expect(pane.achieved.text).to eq "Achievements"
      expect(pane.achievements.map &.text).to eq ["cannibalturn 0"]
    end

    it "lists them on the screen a run ends with" do
      game = among_orcs
      expect(Placards.ending(game).any?(&.includes? "You earned")).to be_false

      game.perform Action::Eat.new(game.here.first.id)
      lines = Placards.ending game
      at = lines.index("You earned:")
      expect(at).not_to be_nil
      expect(lines[(at || 0) + 1]).to eq "  cannibal, on turn 0"
    end
  end
end
