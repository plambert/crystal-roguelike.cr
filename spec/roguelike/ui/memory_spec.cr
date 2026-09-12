require "../../spec_helper"

Spectator.describe "what the character remembers" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Ui = Roguelike::Ui

  # Two rooms joined by a corridor longer than a torch reaches. The character
  # starts in the left room with a lit torch.
  HALL = [
    "##################",
    "#...##############",
    "#.<.+............#",
    "#...##############",
    "##################",
  ]

  # Walking east from the up staircase. The second press opens the door and
  # takes a turn without moving, so a walk of *steps* squares needs one more
  # press than that.
  def walk_east(run : Playing::Run, steps : Int32) : Nil
    (steps + 1).times { run.press "l" }
  end

  # The style one cell of the buffer was drawn in. `Cell#style` is an id into
  # the buffer's own table.
  def drawn_style(run : Playing::Run, x : Int32, y : Int32) : TermBuf::Style
    found = run.buffer.hit x, y
    raise "nothing is drawn at #{x},#{y}" unless found

    run.buffer.styles[found.cell.style]
  end

  def walking(lines : Array(String) = HALL) : Playing::Run
    floor = Roguelike::Floor.parse "hall", lines
    player = Roguelike::Player.new "hall", *Roguelike::Game.entrance(floor)
    player.inventory.add Playing.torch

    Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}), player), 40, 16
  end

  describe "a room walked through" do
    # Its shape stays on the map after the character has gone.
    it "keeps its shape on the map" do
      run = walking

      walk_east run, 14

      expect(run.at).to eq({16, 2})
      expect(run.game.sight.includes?(1, 1)).to be_false
      expect(run.game.knowledge.seen?(1, 1)).to be_true
      expect(run.row(1)[1]).to eq '.'
    end

    it "is drawn dimmer than the square the character stands on" do
      run = walking

      walk_east run, 14

      here = drawn_style run, 16, 2
      away = drawn_style run, 1, 1

      expect(away).not_to eq here
      expect(away.foreground.red).to be < here.foreground.red
    end

    it "draws nothing for a square never seen" do
      run = walking

      expect(run.game.knowledge.seen?(16, 2)).to be_false
      expect(run.row(2)[16]?).to be_nil
    end
  end

  describe "an item in a room walked out of" do
    # It is remembered as it was and not updated while out of sight.
    it "stays where it was after it is taken away" do
      run = walking
      run.game.floor.drop 1, 1, Item.new Kind::Dagger
      run.play.refresh
      run.render

      walk_east run, 14
      expect(run.row(1)[1]).to eq ')'

      run.game.floor.clear_items 1, 1
      run.play.refresh
      run.render

      expect(run.game.floor.items(1, 1)).to be_empty
      expect(run.row(1)[1]).to eq ')'
    end

    it "is forgotten once the character sees it gone" do
      run = walking
      run.game.floor.drop 1, 1, Item.new Kind::Dagger
      run.play.refresh
      run.render
      expect(run.row(1)[1]).to eq ')'

      run.game.floor.clear_items 1, 1
      run.play.refresh
      run.render

      expect(run.row(1)[1]).to eq '.'
    end
  end

  describe "a door shut behind the character" do
    it "is remembered open until it is seen again" do
      run = walking

      walk_east run, 14
      run.game.floor.set 4, 2, Roguelike::Terrain::ClosedDoor
      run.play.refresh
      run.render

      expect(run.game.knowledge[4, 2].try &.terrain).to eq Roguelike::Terrain::OpenDoor
      expect(run.row(2)[4]).to eq '\''
    end
  end

  # A blend computing a colour per cell interns a style per cell, and a style
  # table only grows. The ramp answers the same style for the same step every
  # time, so the table settles.
  describe "the style table" do
    it "stops growing once the walk has covered the map once" do
      run = walking [
        "####################",
        "#..................#",
        "#.<................#",
        "#..................#",
        "####################",
      ]

      # One pass each way puts every look at every step it will ever reach.
      18.times { run.press "l" }
      18.times { run.press "h" }
      settled = run.buffer.styles.size

      4.times do
        18.times { run.press "l" }
        18.times { run.press "h" }
      end

      expect(run.buffer.styles.size).to eq settled
    end

    it "settles at a size a person could count" do
      run = walking

      walk_east run, 14

      expect(run.buffer.styles.size).to be < 60
    end
  end

  describe "Game#look" do
    it "records what it answers" do
      run = walking
      run.game.knowledge.forget

      seen = run.game.look

      expect(run.game.knowledge.size).to eq seen.size
    end

    it "stamps the turn a square was seen on" do
      run = walking

      run.press "o"
      run.press "l"

      expect(run.game.knowledge[3, 2].try &.turn).to eq run.turn
    end
  end

  describe "Game#sight" do
    # A spec reading the field of view should not change what is remembered.
    it "records nothing" do
      run = walking
      run.game.knowledge.forget

      run.game.sight

      expect(run.game.knowledge.empty?).to be_true
    end
  end

  describe "the examine pane" do
    it "says what a remembered square looked like" do
      run = walking
      walk_east run, 14

      run.hover 1, 1

      expect(run.examine.what.text).to eq "stone floor"
      expect(run.examine.detail.text).to eq Ui::ExaminePane::REMEMBERED
    end

    it "names what was lying there when it was last seen" do
      run = walking
      run.game.floor.drop 1, 1, Item.new Kind::Dagger
      run.play.refresh
      walk_east run, 14
      run.game.floor.clear_items 1, 1
      run.play.refresh
      run.render

      run.hover 1, 1

      expect(run.examine.litter.hidden?).to be_false
      expect(run.examine.litter.text).to contain "dagger"
    end

    it "still refuses a square the character has never seen" do
      run = walking

      run.hover 16, 2

      expect(run.examine.what.text).to eq Ui::ExaminePane::UNSEEN
      expect(run.examine.detail.text).to be_empty
    end

    it "says what is there now for a square in sight" do
      run = walking

      run.hover 2, 2

      expect(run.examine.what.text).to eq "staircase up"
      expect(run.examine.detail.text).not_to eq Ui::ExaminePane::REMEMBERED
    end
  end

  describe "drawn" do
    it "draws what it drew last time from the far room" do
      run = walking
      walk_east run, 14
      drawn = run.text

      expect(drawn).to eq Fixture.expected("screen/remembered.txt", drawn)
    end
  end
end
