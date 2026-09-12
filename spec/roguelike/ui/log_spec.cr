require "../../spec_helper"

Spectator.describe "the message log" do
  alias Direction = Roguelike::Direction

  describe "what the game says" do
    it "greets the person at the start" do
      run = Playing.open

      expect(run.log.first).to contain "dungeon"
    end

    it "names what blocked a step" do
      run = Playing.open
      20.times { run.press "k" }

      expect(run.said).to eq "The granite blocks your way."
    end

    it "says nothing new for a wall bumped twice" do
      run = Playing.open
      before = run.log.size

      5.times { run.press "k" }

      expect(run.log.size).to eq before + 1
    end

    it "says so when a door opens" do
      run = Playing.open
      16.times { run.press "l" }

      expect(run.log).to contain "You open the door."
    end

    # Fifteen presses stop beside the door. The fifteenth opened it. A
    # sixteenth would walk onto it, and a character standing in a doorway has
    # no door beside them to close.
    it "says so when a door closes" do
      run = Playing.open
      15.times { run.press "l" }
      run.press "c"

      expect(run.said).to eq "You close the door."
    end

    it "says what the character walked onto" do
      run = Playing.open
      run.press "l"
      run.press "h"

      expect(run.said).to contain "staircase leading up"
    end
  end

  describe "the pane" do
    it "draws the messages" do
      run = Playing.open

      expect(run.rows[20]).to contain "dungeon"
    end

    it "wraps a message longer than the pane" do
      run = Playing.open columns: 40, rows: 20
      run.game.say "A single message that runs on far past the width of a " \
                   "pane only forty columns across."
      run.play.refresh
      run.render

      expect(run.pager.lines.size).to be > 1
    end

    # A turn that produces six lines in a four row pane loses two of them
    # without a pager.
    it "holds at a page boundary when a burst arrives" do
      run = Playing.open
      6.times { |number| run.game.say "Something number #{number} happened." }
      run.play.refresh
      run.render

      expect(run.pager.holding?).to be_true
      expect(run.rows[23]).to contain "--More--"
    end

    it "shows the rest on a key" do
      run = Playing.open
      6.times { |number| run.game.say "Something number #{number} happened." }
      run.play.refresh
      run.render

      run.press "l"

      expect(run.pager.holding?).to be_false
    end

    # A pager that let other keys through would walk the character while the
    # person was reading.
    it "swallows the key that clears it" do
      run = Playing.open
      start = run.at
      8.times { |number| run.game.say "Something number #{number} happened." }
      run.play.refresh
      run.render

      run.press "l"

      expect(run.at).to eq start
    end

    it "gives the keys back once the reading is done" do
      run = Playing.open
      start = run.at
      6.times { |number| run.game.say "Something number #{number} happened." }
      run.play.refresh
      run.render

      run.press "l"
      run.press "l"

      expect(run.at).to eq({start[0] + 1, start[1]})
    end
  end

  describe "drawn" do
    it "draws what it drew last time with a page held" do
      run = Playing.open
      6.times { |number| run.game.say "Something number #{number} happened." }
      run.play.refresh
      drawn = run.text

      expect(drawn).to eq Fixture.expected("screen/log-more.txt", drawn)
    end
  end
end
