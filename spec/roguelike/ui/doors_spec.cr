require "../../spec_helper"

Spectator.describe "doors, stairs and leaving" do
  alias Terrain = Roguelike::Terrain
  alias Outcome = Roguelike::Outcome

  # A game on *map*, with the character at *x*, *y*, wired the way `Session`
  # wires it.
  def room(map : String, x : Int32, y : Int32) : Playing::Run
    level = Roguelike::Level.parse "room", map
    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"room" => level}),
      Roguelike::Player.new("room", x, y)

    Playing.open game
  end

  describe "walking into a shut door" do
    it "opens it and stays put" do
      run = room "#####\n#<+.#\n#####", 1, 1

      run.press "l"

      expect(run.game.level.terrain(2, 1)).to eq Terrain::OpenDoor
      expect(run.at).to eq({1, 1})
      expect(run.turn).to eq 1
    end

    it "draws the door open" do
      run = room "#####\n#<+.#\n#####", 1, 1

      run.press "l"

      expect(run.row(1)[0, 5]).to eq "#@'.#"
    end
  end

  describe "o" do
    it "opens the one shut door beside the character" do
      run = room "#####\n#<+.#\n#####", 1, 1

      run.press "o"

      expect(run.game.level.terrain(2, 1)).to eq Terrain::OpenDoor
      expect(run.turn).to eq 1
    end

    it "says so when there is nothing to open" do
      run = room "###\n#<#\n###", 1, 1

      run.press "o"

      expect(run.said).to contain "nothing to open"
      expect(run.turn).to eq 0
    end

    # One door needs no question. More than one does.
    it "asks which way when there is more than one door" do
      run = room "#+#\n#<+\n###", 1, 1

      run.press "o"

      expect(run.play.pending).to eq Roguelike::Ui::Pending::Open
      expect(run.said).to contain "Which way?"
      expect(run.turn).to eq 0
    end

    it "opens the door the next key names" do
      run = room "#+#\n#<+\n###", 1, 1

      run.press "o"
      run.press "k"

      expect(run.game.level.terrain(1, 0)).to eq Terrain::OpenDoor
      expect(run.game.level.terrain(2, 1)).to eq Terrain::ClosedDoor
      expect(run.play.pending).to be_nil
    end

    it "does not move the character while it waits for a direction" do
      run = room "#+#\n#<+\n###", 1, 1

      run.press "o"
      run.press "k"

      expect(run.at).to eq({1, 1})
    end

    it "says so when the direction holds no door" do
      run = room "#+#\n#<+\n###", 1, 1

      run.press "o"
      run.press "h"

      expect(run.said).to contain "nothing to open that way"
    end

    it "gives the keys back after Escape" do
      run = room "#+#\n#<+\n###", 1, 1

      run.press "o"
      run.press "Escape"
      expect(run.play.pending).to be_nil

      run.press "l"
      expect(run.game.level.terrain(2, 1)).to eq Terrain::OpenDoor
    end
  end

  describe "c" do
    it "closes the one open door beside the character" do
      run = room "#####\n#<'.#\n#####", 1, 1

      run.press "c"

      expect(run.game.level.terrain(2, 1)).to eq Terrain::ClosedDoor
      expect(run.turn).to eq 1
    end

    it "says so when there is nothing to close" do
      run = room "#####\n#<+.#\n#####", 1, 1

      run.press "c"

      expect(run.said).to contain "nothing to close"
    end
  end

  describe ">" do
    it "wins the run from the down staircase" do
      run = room "###\n#>#\n###", 1, 1

      run.press ">"

      expect(run.game.outcome).to eq Outcome::Won
      expect(run.prompt.asking?).to be_true
      expect(run.prompt.question).to contain "You win"
    end

    it "ends the run once the win is acknowledged" do
      run = room "###\n#>#\n###", 1, 1

      run.press ">"
      expect(run.finished?).to be_false

      run.press "Enter"
      expect(run.finished?).to be_true
    end

    it "says so anywhere else, and does not win" do
      run = room "###\n#<#\n###", 1, 1

      run.press ">"

      expect(run.game.outcome).to eq Outcome::Playing
      expect(run.said).to contain "no staircase down"
      expect(run.finished?).to be_false
    end
  end

  describe "<" do
    it "asks before leaving" do
      run = room "###\n#<#\n###", 1, 1

      run.press "<"

      expect(run.prompt.asking?).to be_true
      expect(run.game.outcome).to eq Outcome::Playing
    end

    it "leaves on yes" do
      run = room "###\n#<#\n###", 1, 1

      run.press "<"
      run.press "y"
      run.press "Enter"

      expect(run.game.outcome).to eq Outcome::Left
      expect(run.finished?).to be_true
    end

    it "stays on no" do
      run = room "###\n#<#\n###", 1, 1

      run.press "<"
      run.press "n"

      expect(run.game.outcome).to eq Outcome::Playing
      expect(run.finished?).to be_false
      expect(run.prompt.asking?).to be_false
    end

    it "says so anywhere else" do
      run = room "###\n#.#\n###", 1, 1

      run.press "<"

      expect(run.prompt.asking?).to be_false
      expect(run.said).to contain "no staircase up"
    end
  end

  describe "Q" do
    it "asks before leaving" do
      run = Playing.open

      run.press "Q"

      expect(run.prompt.asking?).to be_true
      expect(run.finished?).to be_false
    end

    it "returns to the game on no" do
      run = Playing.open
      start = run.at

      run.press "Q"
      run.press "n"
      run.press "l"

      expect(run.finished?).to be_false
      expect(run.at).to eq({start[0] + 1, start[1]})
    end

    it "leaves on yes" do
      run = Playing.open

      run.press "Q"
      run.press "y"

      expect(run.finished?).to be_true
    end

    # A prompt that let other keys through would walk the character while the
    # person was answering a question.
    it "swallows a movement key while the question is up" do
      run = Playing.open
      start = run.at

      run.press "Q"
      run.press "l"

      expect(run.at).to eq start
      expect(run.prompt.asking?).to be_true
    end
  end

  # The walk the phase is for: out of the starting room, across the level, and
  # down the staircase at the far end.
  describe "a whole run on the shipped level" do
    # South out of room A through the door at 10,9, down the corridor into
    # room D, east along the corridor at row 20, through the door at 54,20
    # into room C, and up to the staircase. A shut door takes two presses of
    # the same key. One opens it. The next walks through it.
    WALK = "nnnnnjjjjjnlllnnnnn" + "l" * 43 + "u"

    it "opens a door, crosses the level, and wins" do
      run = Playing.open

      WALK.each_char { |key| run.press key.to_s }

      expect(run.game.standing_on).to eq Terrain::StairsDown
      expect(run.game.outcome).to eq Outcome::Playing

      run.press ">"
      expect(run.game.outcome).to eq Outcome::Won
      expect(run.prompt.question).to contain "You win"

      run.press "Enter"
      expect(run.finished?).to be_true
    end

    it "leaves the doors it opened open" do
      run = Playing.open

      WALK.each_char { |key| run.press key.to_s }

      expect(run.game.level.terrain(10, 9)).to eq Terrain::OpenDoor
      expect(run.game.level.terrain(54, 20)).to eq Terrain::OpenDoor
    end

    it "takes one turn for each key that did something" do
      run = Playing.open

      WALK.each_char { |key| run.press key.to_s }

      expect(run.turn).to eq WALK.size
    end
  end

  describe "drawn" do
    it "draws what it drew last time with a question up" do
      run = Playing.open
      run.press "Q"
      drawn = run.text

      expect(drawn).to eq Fixture.expected("screen/quit-prompt.txt", drawn)
    end
  end
end
