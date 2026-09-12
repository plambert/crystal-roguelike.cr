require "../../spec_helper"

Spectator.describe "doors, stairs and leaving" do
  alias Terrain = Roguelike::Terrain
  alias Outcome = Roguelike::Outcome

  # A game on *map*, with the character at *x*, *y*, wired the way `Session`
  # wires it.
  def room(map : String, x : Int32, y : Int32) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("room", map)
    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"room" => floor}),
      Roguelike::Player.new("room", x, y)

    Playing.open game
  end

  describe "walking into a shut door" do
    it "opens it and stays put" do
      run = room "#####\n#<+.#\n#####", 1, 1

      run.press "l"

      expect(run.game.floor.terrain(2, 1)).to eq Terrain::OpenDoor
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

      expect(run.game.floor.terrain(2, 1)).to eq Terrain::OpenDoor
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

      expect(run.game.floor.terrain(1, 0)).to eq Terrain::OpenDoor
      expect(run.game.floor.terrain(2, 1)).to eq Terrain::ClosedDoor
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
      expect(run.game.floor.terrain(2, 1)).to eq Terrain::OpenDoor
    end
  end

  describe "c" do
    it "closes the one open door beside the character" do
      run = room "#####\n#<'.#\n#####", 1, 1

      run.press "c"

      expect(run.game.floor.terrain(2, 1)).to eq Terrain::ClosedDoor
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

  # The walk the phase is for: out of the starting room, across the floor, and
  # down the staircase at the far end.
  describe "a whole run on the shipped floor" do
    # South out of room A through the door at 10,9, down the corridor and
    # through the four way junction at 10,12, on into room D, east along the
    # corridor at row 20, through the door at 54,20 into room C, and up to the
    # staircase. A shut door takes two presses of the same key. One opens it.
    # The next walks through it. There are four doors on the way.
    WALK = "nnnnnjjjjjjjnlllnnnnn" + "l" * 43 + "u"

    it "opens a door, crosses the floor, and wins" do
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

      [{10, 9}, {10, 11}, {10, 13}, {54, 20}].each do |spot|
        expect(run.game.floor.terrain(spot[0], spot[1])).to eq Terrain::OpenDoor
      end
    end

    it "takes one turn for each key that did something" do
      run = Playing.open

      WALK.each_char { |key| run.press key.to_s }

      expect(run.turn).to eq WALK.size
    end
  end

  # Four shut doors around one square. `o` and `c` cannot guess which.
  describe "the four way junction on the shipped floor" do
    # From the up staircase down to the junction at 10,12. Two doors on the
    # way, at 10,9 and 10,11. Each takes one key to open and one to walk
    # through.
    TO_JUNCTION = "nnnnnjjjj"

    it "puts the character between four doors" do
      run = Playing.open
      TO_JUNCTION.each_char { |key| run.press key.to_s }

      expect(run.at).to eq({10, 12})
      expect(run.game.doors(Terrain::ClosedDoor).size).to eq 3
    end

    it "asks which door to open" do
      run = Playing.open
      TO_JUNCTION.each_char { |key| run.press key.to_s }

      run.press "o"

      expect(run.play.pending).to eq Roguelike::Ui::Pending::Open
      expect(run.said).to contain "Which way?"
    end

    it "opens the one the next key names" do
      run = Playing.open
      TO_JUNCTION.each_char { |key| run.press key.to_s }

      run.press "o"
      run.press "h"

      expect(run.game.floor.terrain(9, 12)).to eq Terrain::OpenDoor
      expect(run.game.floor.terrain(11, 12)).to eq Terrain::ClosedDoor
    end

    # A person asked which way has to see which way.
    it "lights up every door that answers" do
      run = Playing.open
      TO_JUNCTION.each_char { |key| run.press key.to_s }

      run.press "o"

      expect(run.map.highlights.to_a.sort).to eq [{9, 12}, {10, 13}, {11, 12}]
    end

    it "lights up nothing once the question is answered" do
      run = Playing.open
      TO_JUNCTION.each_char { |key| run.press key.to_s }

      run.press "o"
      run.press "h"

      expect(run.map.highlights).to be_empty
    end

    it "lights up nothing after Escape" do
      run = Playing.open
      TO_JUNCTION.each_char { |key| run.press key.to_s }

      run.press "o"
      run.press "Escape"

      expect(run.map.highlights).to be_empty
    end

    it "lights up the open doors for c, not the shut ones" do
      run = Playing.open
      TO_JUNCTION.each_char { |key| run.press key.to_s }
      run.press "o"
      run.press "h"
      run.press "o"
      run.press "l"

      run.press "c"

      # The north door counts too. Walking through it left it open.
      expect(run.map.highlights.to_a.sort).to eq [{9, 12}, {10, 11}, {11, 12}]
    end

    it "leaves the door's own glyph showing under the highlight" do
      run = Playing.open
      TO_JUNCTION.each_char { |key| run.press key.to_s }

      run.press "o"
      spot = run.map.grid.view_of 11, 12
      raise "the door is not in view" unless spot

      expect(run.row(spot[1])[spot[0]]).to eq '+'
    end

    it "asks which door to close once two are open" do
      run = Playing.open
      TO_JUNCTION.each_char { |key| run.press key.to_s }

      run.press "o"
      run.press "h"
      run.press "o"
      run.press "l"
      run.press "c"

      expect(run.play.pending).to eq Roguelike::Ui::Pending::Close
    end
  end

  describe "a question on the screen" do
    # The style of one cell before the question and after it.
    def style_at(run : Playing::Run, x : Int32, y : Int32) : UInt32?
      run.buffer.hit(x, y).try &.cell.style
    end

    it "draws a box in the middle rather than against an edge" do
      run = Playing.open
      run.press "Q"

      boxed = run.rows.find &.includes?("Really leave")
      raise "no question was drawn" unless boxed

      left = boxed.index('│')
      right = boxed.rindex('│')
      raise "no box was drawn" unless left && right

      expect(left).to be > 0
      expect(right).to be < 79
      expect(right).to be > left
    end

    # Readable around it, and dimmed. The glyphs stay where they were.
    it "dims what is behind it without covering it" do
      run = Playing.open
      wall = style_at run, 2, 2
      character = style_at run, 6, 5
      logged = style_at run, 1, 20

      run.press "Q"

      expect(style_at(run, 2, 2)).not_to eq wall
      expect(style_at(run, 6, 5)).not_to eq character
      expect(style_at(run, 1, 20)).not_to eq logged
      expect(run.row(5)[6]).to eq '@'
    end

    # A box is drawn in the middle of the screen. A character standing in the
    # middle of the map pane would be behind it, and a person answering a
    # question about what is around them has to see what is around them.
    # One open room, large enough that the camera can put the character
    # anywhere in the window. On the shipped floor the character starts near a
    # corner and the camera cannot centre them at all.
    def middled : Playing::Run
      run = Playing.open Playing.field
      run.map.center_on run.at[0], run.at[1]
      run.render
      run
    end

    it "moves the camera so the character is not behind the box" do
      run = middled

      run.press "Q"

      spot = run.map.grid.view_of run.at[0], run.at[1]
      raise "the character left the window" unless spot

      boxed = run.rows.index &.includes?("Really leave")
      raise "no question was drawn" unless boxed

      expect((spot[1] - boxed).abs).to be > 1
    end

    it "leaves the character in view" do
      run = middled

      run.press "Q"

      expect(run.map.grid.view_of(run.at[0], run.at[1])).not_to be_nil
      expect(run.map.mark?(run.at[0], run.at[1])).not_to be_nil
    end

    it "puts the camera back once the question is answered" do
      run = middled
      before = run.map.camera

      run.press "Q"
      expect(run.map.camera).not_to eq before

      run.press "n"
      expect(run.map.camera).to eq before
    end

    # The character starts near the top left corner of the shipped floor. The
    # box covers the middle of the screen and never reaches them.
    it "does not move the camera for a character already clear of the box" do
      run = Playing.open
      before = run.map.camera

      run.press "Q"

      expect(run.map.camera).to eq before
    end

    it "puts the screen back when the question goes" do
      run = Playing.open
      wall = style_at run, 2, 2

      run.press "Q"
      run.press "n"

      expect(style_at(run, 2, 2)).to eq wall
    end

    # A catcher answers every point the overlay did not. A click behind a
    # modal question reaches nothing.
    it "takes a click that lands behind it" do
      run = Playing.open
      run.press "Q"

      run.hover 6, 5

      expect(run.examiner.spot).to be_nil
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
