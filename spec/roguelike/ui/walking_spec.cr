require "../../spec_helper"

Spectator.describe "a run drawn a step at a time" do
  alias Game = Roguelike::Game

  # A hall the character can walk the length of, with no junction in it.
  HALL = [
    "###############",
    "#<............#",
    "###############",
  ]

  # A run on `HALL` with a clock a spec fires by hand.
  def walking(columns : Int32 = 60, rows : Int32 = 20) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("hall", HALL)
    run = Playing.open Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}),
      Roguelike::Player.new("hall", *Game.entrance(floor),
        hit_points: 40)), columns, rows, clock: true
    run.clear_monsters
    run
  end

  # Where *spot* of the floor is drawn.
  def on_screen(run : Playing::Run, spot : {Int32, Int32}) : {Int32, Int32}
    found = run.map.screen_of spot[0], spot[1]
    raise "#{spot} is not on the screen" unless found

    found
  end

  describe "G" do
    it "takes one step and then waits" do
      run = walking

      run.press "G", "l"

      expect(run.at).to eq({2, 1})
      expect(run.play.walking?).to be_true
    end

    it "takes one more step for each tick of the clock" do
      run = walking

      run.press "G", "l"
      run.tick
      run.tick

      expect(run.at).to eq({4, 1})
    end

    it "takes one turn a step" do
      run = walking
      before = run.turn

      run.press "G", "l"
      run.tick

      expect(run.turn).to eq before + 2
    end

    it "goes to the end when the clock is left to run" do
      run = walking

      run.press "G", "l"
      run.run_timers

      expect(run.at).to eq({13, 1})
      expect(run.play.walking?).to be_false
    end

    it "arms nothing more once it has stopped" do
      run = walking

      run.press "G", "l"
      run.run_timers

      expect(run.armed).to be_empty
    end

    # A walk that could not take a step at all never starts.
    it "does not start against a wall" do
      run = walking

      run.press "G", "h"

      expect(run.play.walking?).to be_false
      expect(run.said).to eq "The granite blocks your way."
    end
  end

  describe "a key pressed while a walk is going" do
    it "stops the walk" do
      run = walking

      run.press "G", "l"
      run.tick
      run.press "j"

      expect(run.play.walking?).to be_false
    end

    it "leaves the character where the walk had got to" do
      run = walking

      run.press "G", "l"
      run.tick
      here = run.at
      run.press "j"

      expect(run.at).to eq here
    end

    it "does not do what the key usually does" do
      run = walking

      run.press "G", "l"
      run.tick
      before = run.turn
      run.press "i"

      expect(run.menu.showing?).to be_false
      expect(run.turn).to eq before
    end

    it "takes no more steps once it is stopped" do
      run = walking

      run.press "G", "l"
      run.tick
      run.press "j"
      here = run.at
      run.run_timers

      expect(run.at).to eq here
    end

    it "gives the keyboard back" do
      run = walking

      run.press "G", "l"
      run.press "j"
      before = run.at
      run.press "l"

      expect(run.at).to eq({before[0] + 1, before[1]})
    end

    it "says nothing about having been stopped" do
      run = walking
      run.press "G", "l"
      said = run.said

      run.press "j"

      expect(run.said).to eq said
    end
  end

  # The pane and the walk both push a focus scope. Only one of them may have
  # one up at a time, or the one underneath can never take its own away.
  describe "messages piling up during a walk" do
    # A hall with something lying on every square the walk crosses, all of it
    # already on the character's map. Each square writes a line and none of
    # them stops the walk.
    #
    # The kinds alternate because `MessageLog#add` drops a line identical to
    # the one before it, and a hall of daggers would collapse into one line.
    def littered : Playing::Run
      run = walking
      (2..12).each do |column|
        kind = column.even? ? Roguelike::ItemKind::Dagger : Roguelike::ItemKind::Cap
        run.game.floor.drop column, 1, Roguelike::Item.new(kind)
      end
      run.play.refresh
      run
    end

    it "holds nothing while the walk is going" do
      run = littered

      run.press "G", "l"
      run.tick
      run.tick
      run.tick
      run.tick
      run.tick

      expect(run.play.walking?).to be_true
      expect(run.pager.holding?).to be_false
    end

    it "holds once the walk is over" do
      run = littered

      run.press "G", "l"
      run.run_timers

      expect(run.play.walking?).to be_false
      expect(run.pager.holding?).to be_true
    end

    it "gives the keyboard back once the page is let go" do
      run = littered
      run.press "G", "l"
      run.run_timers

      while run.pager.holding?
        run.press "Space"
      end

      before = run.at
      run.press "h"

      expect(run.at).to eq({before[0] - 1, before[1]})
    end
  end

  describe "a route walked by clicking" do
    it "is drawn a step at a time as well" do
      run = walking
      spot = on_screen run, {10, 1}

      run.click spot[0], spot[1]
      run.click spot[0], spot[1]

      expect(run.at).to eq({2, 1})
      expect(run.play.walking?).to be_true
    end

    it "arrives when the clock is left to run" do
      run = walking
      spot = on_screen run, {10, 1}

      run.click spot[0], spot[1]
      run.click spot[0], spot[1]
      run.run_timers

      expect(run.at).to eq({10, 1})
    end

    it "stops on a key" do
      run = walking
      spot = on_screen run, {10, 1}

      run.click spot[0], spot[1]
      run.click spot[0], spot[1]
      run.tick
      run.press "j"
      here = run.at
      run.run_timers

      expect(run.at).to eq here
      expect(here[0]).to be < 10
    end
  end

  # A run that has been played a long time has a full log. Every line it
  # writes then drops the oldest one, so the log stops growing.
  describe "a route walked in a run with a full log" do
    # A run whose log holds every line it keeps, with a dagger on one square
    # of the hall. The character remembers the dagger.
    def crowded : Playing::Run
      run = walking
      run.game.floor.drop 6, 1, Roguelike::Item.new(Roguelike::ItemKind::Dagger)
      run.play.refresh

      Roguelike::MessageLog::LIMIT.times do |count|
        run.game.log.lines << "Line #{count}."
      end

      # The person reads what the pane holds. The keyboard and the mouse go
      # back to the map once they have.
      run.play.refresh
      while run.pager.holding?
        run.press "Enter"
      end

      run
    end

    it "crosses an item the character remembers" do
      run = crowded
      spot = on_screen run, {10, 1}

      run.click spot[0], spot[1]
      run.click spot[0], spot[1]
      run.run_timers

      expect(run.at).to eq({10, 1})
    end
  end
end
