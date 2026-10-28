require "../../spec_helper"

Spectator.describe "pointing at a square" do
  alias Game = Roguelike::Game
  alias Play = Roguelike::Ui::Play

  # A hall with the way up at the west end and the way down at the east.
  HALL = [
    "###############",
    "#<...........>#",
    "###############",
  ]

  # A hall with no way down at all.
  BLIND = [
    "###############",
    "#<............#",
    "###############",
  ]

  # A hall far wider than the window it is played in.
  LONG = [
    "#" * 200,
    "#<" + ("." * 196) + ">#",
    "#" * 200,
  ]

  # A run on *lines* with the character on the up staircase.
  #
  # *lit* is daylight. A run without it is dark, and the character carries no
  # light, so they see their own square and no other.
  def walking(lines : Array(String) = HALL,
              columns : Int32 = 60, rows : Int32 = 20,
              lit : Bool = true, clock : Bool = false) : Playing::Run
    floor = Roguelike::Floor.parse "hall", lines
    Playing.daylight floor if lit
    run = Playing.open Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}),
      Roguelike::Player.new("hall", *Game.entrance(floor),
        hit_points: 40)), columns, rows, clock: clock
    run.clear_monsters
    run
  end

  # Where *spot* of the floor is drawn.
  def on_screen(run : Playing::Run, spot : {Int32, Int32}) : {Int32, Int32}
    found = run.map.screen_of spot[0], spot[1]
    raise "#{spot} is not on the screen" unless found

    found
  end

  describe "> away from the staircase" do
    it "says where the stairs are" do
      run = walking

      run.press ">"

      expect(run.said).to eq "The stairs are here."
    end

    it "lights the staircase up" do
      run = walking

      run.press ">"

      expect(run.map.highlighted? 13, 1).to be_true
    end

    it "lights the way there up" do
      run = walking

      run.press ">"

      expect(run.map.highlighted? 7, 1).to be_true
    end

    it "leaves the character's own square alone" do
      run = walking

      run.press ">"

      expect(run.map.highlighted? 1, 1).to be_false
    end

    it "takes no turn" do
      run = walking
      before = run.turn

      run.press ">"

      expect(run.turn).to eq before
    end

    it "says where the stairs are without taking the keyboard" do
      run = walking
      before = run.turn

      run.press ">"
      run.press "."

      expect(run.log).to contain "The stairs are here."
      expect(run.turn).to eq before + 1
    end

    it "keeps the highlight up until something else happens" do
      run = walking

      run.press ">"
      run.press "Space"

      expect(run.map.highlighted? 13, 1).to be_true
    end

    it "leaves it off once a turn has been taken" do
      run = walking

      run.press ">"
      run.press "Space"
      run.press "l"

      expect(run.map.highlights).to be_empty
    end

    # The key that lets the page go does nothing else. It does not walk.
    it "takes no turn when the page is let go" do
      run = walking
      before = run.turn

      run.press ">"
      run.press "Space"

      expect(run.turn).to eq before
    end

    # The staircase is a hundred and ninety squares east of a window sixty
    # wide, so nothing points at it until the camera gets there.
    it "brings a staircase off the window into view" do
      run = walking LONG

      expect(run.map.screen_of 197, 1).to be_nil
      run.press ">"

      expect(run.map.screen_of 197, 1).not_to be_nil
    end

    it "keeps one camera glide chain when a canceled route is drawn again" do
      run = walking LONG, clock: true
      wait = Play::GLIDE

      run.press ">"
      stale = run.armed_for(wait).first
      before = run.map.camera

      run.press "Escape"
      run.press ">"
      expect(run.armed_for(wait).size).to eq 1
      run.session.send TermBuf::Input::Events::Timer.new(stale)
      expect(run.map.camera).to eq before
      expect(run.armed_for(wait).size).to eq 1

      run.session.tick wait
      expect(run.map.camera).not_to eq before
      expect(run.armed_for(wait).size).to eq 1

      run.run_timers
      expect(run.map.screen_of 197, 1).not_to be_nil
      expect(run.armed_for(wait)).to be_empty
    end

    it "cancels a queued camera glide when the game is replaced" do
      run = walking LONG, clock: true
      run.press ">"
      stale = run.armed_for(Play::GLIDE).first
      replacement = Game.start(Roguelike::Rng.new(31_u64))

      run.play.resume replacement
      expect(run.map.floor).to be replacement.floor
      expect(run.armed_for(Play::GLIDE)).to be_empty
      camera = run.map.camera
      run.session.send TermBuf::Input::Events::Timer.new(stale)
      expect(run.map.camera).to eq camera
    end

    it "says so when the character has never seen one" do
      run = walking BLIND

      run.press ">"

      expect(run.said).to eq "There is no staircase down here."
      expect(run.map.highlights).to be_empty
    end

    it "walks to the stairs on the second press without taking them" do
      run = walking
      run.press ">"
      run.press ">"

      expect(run.at).to eq({13, 1})
      expect(run.game.outcome.playing?).to be_true
      run.press ">"
      expect(run.game.outcome.won?).to be_true
    end

    it "shares the preview with a subsequent click" do
      run = walking
      run.press ">"
      spot = on_screen run, {13, 1}
      run.click spot[0], spot[1]

      expect(run.at).to eq({13, 1})
      expect(run.game.outcome.playing?).to be_true
    end

    it "follows a clicked staircase preview with the key" do
      run = walking
      spot = on_screen run, {13, 1}
      run.click spot[0], spot[1]
      run.press ">"

      expect(run.at).to eq({13, 1})
      expect(run.game.outcome.playing?).to be_true
    end

    it "previews again after the route expires" do
      run = walking clock: true
      run.press ">"
      run.session.tick Play::ROUTE_FADE
      run.press ">"

      expect(run.at).to eq({1, 1})
      expect(run.turn).to eq 0
      expect(run.map.highlighted? 13, 1).to be_true
    end

    it "previews again after Escape cancels the route" do
      run = walking
      run.press ">", "Escape", ">"

      expect(run.at).to eq({1, 1})
      expect(run.turn).to eq 0
      expect(run.map.highlighted? 13, 1).to be_true
    end

    it "does not reuse a preview on another floor at the same turn" do
      run = walking
      run.press ">"
      floor = Playing.daylight Roguelike::Floor.parse("other", HALL)
      replacement = Game.new(
        Roguelike::World.new(Playing::SEED, {"other" => floor}),
        Roguelike::Player.new("other", 1, 1, hit_points: 40))
      run.play.resume replacement
      run.press ">"

      expect(run.at).to eq({1, 1})
      expect(run.turn).to eq 0
      expect(run.map.highlighted? 13, 1).to be_true
    end

    it "does not find an unseen staircase through the floor's truth" do
      run = walking lit: false
      run.press ">"

      expect(run.at).to eq({1, 1})
      expect(run.turn).to eq 0
      expect(run.map.highlights).to be_empty
      expect(run.said).to eq "There is no staircase down here."
    end
  end

  describe "< away from the staircase" do
    it "points at the way up" do
      run = walking
      run.play.game.player.move_to({7, 1})
      run.play.refresh

      run.press "<"

      expect(run.said).to eq "The stairs are here."
      expect(run.map.highlighted? 1, 1).to be_true
    end

    it "walks to the way up on the second press without leaving" do
      run = walking
      run.game.player.move_to({7, 1})
      run.play.refresh
      run.press "<", "<"

      expect(run.at).to eq({1, 1})
      expect(run.game.outcome.playing?).to be_true
      expect(run.prompt.asking?).to be_false
    end

    it "replaces a preview when the other staircase is selected" do
      run = walking
      run.game.player.move_to({7, 1})
      run.play.refresh
      run.press ">", "<"

      expect(run.at).to eq({7, 1})
      expect(run.map.highlighted? 1, 1).to be_true
      expect(run.map.highlighted? 13, 1).to be_false
    end
  end

  describe "> on the staircase" do
    it "still takes it" do
      run = walking
      run.play.game.player.move_to({13, 1})
      run.play.refresh

      run.press ">"

      expect(run.game.outcome.won?).to be_true
    end
  end

  describe "clicking a square" do
    it "draws the way there" do
      run = walking
      spot = on_screen run, {10, 1}

      run.click spot[0], spot[1]

      expect(run.map.highlighted? 10, 1).to be_true
      expect(run.map.highlighted? 5, 1).to be_true
    end

    # The way stays up until it is walked or the character does something
    # else.
    it "leaves the way up" do
      run = walking
      spot = on_screen run, {10, 1}

      run.click spot[0], spot[1]

      expect(run.map.highlighted? 10, 1).to be_true
    end

    it "takes no turn for the first click" do
      run = walking
      before = run.turn
      spot = on_screen run, {10, 1}

      run.click spot[0], spot[1]

      expect(run.turn).to eq before
    end

    it "walks it on the second click" do
      run = walking
      spot = on_screen run, {10, 1}

      run.click spot[0], spot[1]
      run.click spot[0], spot[1]

      expect(run.at).to eq({10, 1})
    end

    it "takes the highlight off once it has been walked" do
      run = walking
      spot = on_screen run, {10, 1}

      run.click spot[0], spot[1]
      run.click spot[0], spot[1]

      expect(run.map.highlights).to be_empty
    end

    # Changing your mind costs one click, not two.
    it "draws a new way when the second click is elsewhere" do
      run = walking
      first = on_screen run, {10, 1}
      second = on_screen run, {5, 1}

      run.click first[0], first[1]
      run.click second[0], second[1]

      expect(run.at).to eq({1, 1})
      expect(run.map.highlighted? 10, 1).to be_false
      expect(run.map.highlighted? 5, 1).to be_true
    end

    it "does nothing for a click on the character's own square" do
      run = walking
      spot = on_screen run, {1, 1}

      run.click spot[0], spot[1]

      expect(run.map.highlights).to be_empty
    end

    # A wall is not somewhere to walk, and nothing is drawn to it.
    it "does nothing for a click on a wall" do
      run = walking
      spot = on_screen run, {5, 0}

      run.click spot[0], spot[1]

      expect(run.map.highlights).to be_empty
    end

    it "does nothing for a click on a square nobody has seen" do
      run = walking lit: false
      spot = on_screen run, {10, 1}

      run.click spot[0], spot[1]

      expect(run.map.highlights).to be_empty
    end

    it "still points the readout at what was clicked" do
      run = walking
      spot = on_screen run, {10, 1}

      run.click spot[0], spot[1]

      expect(run.examiner.spot).to eq({10, 1})
    end
  end
end
