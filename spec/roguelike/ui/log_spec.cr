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
      20.times { run.press "h" }

      expect(run.said).to eq "The granite blocks your way."
    end

    # A sconce stands on the floor rather than in the wall, so the character
    # walks right up to it and stands under it.
    it "lets the character stand on a sconce square" do
      run = Playing.open
      20.times { run.press "k" }

      expect(run.at).to eq({6, 2})
      expect(run.game.floor.fixture(6, 2)).not_to be_nil
      expect(run.said).to eq "The granite blocks your way."
    end

    it "says nothing new for a wall bumped twice" do
      run = Playing.open
      run.clear_monsters
      before = run.log.size

      5.times { run.press "k" }

      expect(run.log.size).to eq before + 1
    end

    it "says so when a door opens" do
      run = Playing.open
      run.clear_monsters
      16.times { run.press "l" }

      expect(run.log).to contain "You open the door."
    end

    # Fifteen presses stop beside the door. The fifteenth opened it. A
    # sixteenth would walk onto it, and a character standing in a doorway has
    # no door beside them to close.
    it "says so when a door closes" do
      run = Playing.open
      run.clear_monsters
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
      run.game.log.add "A single message that runs on far past the width of a " \
                       "pane only forty columns across."
      run.play.refresh
      run.render

      expect(run.pager.lines.size).to be > 1
    end

    # A turn that produces six lines in a four row pane loses two of them
    # without a pager.
    it "holds at a page boundary when a burst arrives" do
      run = Playing.open
      6.times { |number| run.game.log.add "Something number #{number} happened." }
      run.play.refresh
      run.render

      expect(run.pager.holding?).to be_true
      expect(run.rows[23]).to contain "--More--"
    end

    it "shows the rest on a key" do
      run = Playing.open
      6.times { |number| run.game.log.add "Something number #{number} happened." }
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
      8.times { |number| run.game.log.add "Something number #{number} happened." }
      run.play.refresh
      run.render

      run.press "l"

      expect(run.at).to eq start
    end

    # The case that asked for this: one scroll says a dozen things, and the
    # pane is four rows.
    it "holds on the list a scroll of item detection writes" do
      kinds = [Roguelike::ItemKind::Dagger, Roguelike::ItemKind::Mace,
               Roguelike::ItemKind::Cap, Roguelike::ItemKind::Boots]

      game = Playing.field columns: 40, rows: 20
      x, y = game.player.at
      12.times do |number|
        game.floor.drop x - 2 + (number % 5), y - 1 + (number // 5),
          Roguelike::Item.new(kinds[number % 4], enchantment: number % 3)
      end
      letter = game.player.inventory.add(
        Roguelike::Item.new Roguelike::ItemKind::DetectionScroll)

      run = Playing.open game
      run.press "r"
      run.press letter.to_s

      expect(run.pager.holding?).to be_true
      expect(run.rows[23]).to contain "--More--"

      lines = [] of String
      while run.pager.holding?
        lines.concat run.pager.showing
        run.press "Enter"
      end
      lines.concat run.pager.showing

      # Nothing the scroll said went past unseen, which is the whole point
      # of holding.
      everything = run.game.log.lines
      everything.each { |said| expect(lines).to contain said }
    end

    it "gives the keys back once the reading is done" do
      run = Playing.open
      start = run.at
      6.times { |number| run.game.log.add "Something number #{number} happened." }
      run.play.refresh
      run.render

      run.press "l"
      run.press "l"

      expect(run.at).to eq({start[0] + 1, start[1]})
    end
  end

  describe "scrolling the pane" do
    # Where a notch of the wheel lands on the log pane of an eighty by
    # twenty-four window.
    OVER_THE_LOG = {10, 21}

    # A run with *count* messages said and every held page read.
    def talkative(count : Int32 = 12) : Playing::Run
      run = Playing.open
      run.clear_monsters
      count.times { |number| run.game.log.add "Something number #{number} happened." }
      run.play.refresh
      run.render

      while run.pager.holding?
        run.press "."
      end

      run
    end

    it "shows the lines above the pane on a notch of the wheel" do
      run = talkative
      newest = run.rows[23]

      3.times { run.wheel *OVER_THE_LOG, up: true }

      expect(run.pager.back).to eq 3
      expect(run.rows[23]).not_to eq newest
    end

    it "comes back down on a notch the other way" do
      run = talkative
      3.times { run.wheel *OVER_THE_LOG, up: true }

      3.times { run.wheel *OVER_THE_LOG, up: false }

      expect(run.pager.back).to eq 0
    end

    it "walks the character nowhere" do
      run = talkative
      start = run.at

      run.wheel *OVER_THE_LOG, up: true

      expect(run.at).to eq start
    end

    it "goes back to the newest when a turn says something" do
      run = talkative
      3.times { run.wheel *OVER_THE_LOG, up: true }

      run.press "."

      expect(run.pager.back).to eq 0
      expect(run.rows[23]).to contain run.said
    end
  end

  # A long run has a full log. Every line added then drops the oldest, so the
  # log stops growing while the fight goes on writing.
  describe "a fight late in a run" do
    alias Creature = Roguelike::Kind
    alias Item = Roguelike::Item
    alias Kind = Roguelike::ItemKind
    alias Monster = Roguelike::Monster

    # A lit hall with the character at the west end.
    HALL = [
      "##############",
      "#............#",
      "#............#",
      "#............#",
      "##############",
    ]

    # Enough hit points that nobody dies.
    PLENTY = 5_000

    # An orc archer at *at*, with a bow and arrows.
    def archer(at : {Int32, Int32}) : Monster
      creature = Monster.new Creature::OrcArcher, at[0], at[1], "archers",
        hit_points: PLENTY
      creature.outfit [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: 20)]
      creature
    end

    # A run with a bow readied, three archers hunting the character, and a
    # log already full.
    def fight : Playing::Run
      floor = Playing.daylight Roguelike::Floor.parse("hall", HALL)
      player = Roguelike::Player.new "hall", 1, 2, hit_points: PLENTY
      player.inventory.add Item.new(Kind::Bow)
      player.inventory.add Item.new(Kind::Arrow, count: 20)

      run = Playing.open Roguelike::Game.new(
        Roguelike::World.new(Playing::SEED, {"hall" => floor}), player)
      run.press "w", "a"
      run.press "w", "b"

      game = run.game
      [{9, 1}, {10, 2}, {9, 3}].each { |spot| game.floor.place archer(spot) }
      band = game.floor.band("archers") || raise "the floor has lost the band"
      knowledge = band.knowledge game.floor.id
      game.floor.each { |column, row, _tile| knowledge.see game.floor, column, row }
      knowledge.saw Roguelike::Knowledge::PLAYER, *game.player.at, game.turn
      band.awareness = Roguelike::Awareness::Hunting

      Roguelike::MessageLog::LIMIT.times do |number|
        game.log.add "Something earlier, number #{number}."
      end
      run.play.refresh
      run.pager.catch_up
      run.render
      run
    end

    # Reads every held page, then fires once. Returns how many lines the
    # shot and the turn after it wrote.
    def volley(run : Playing::Run) : Int32
      while run.pager.holding?
        run.press "Enter"
      end

      run.press "f"
      before = run.game.log.written
      run.press "Enter"
      run.game.log.written - before
    end

    it "holds on the lines a volley writes" do
      run = fight

      # The archers take a few turns to pick up arrows and come into range.
      wrote = 0
      10.times do
        wrote = volley run
        break if wrote > run.pager.rows
      end
      expect(wrote).to be > run.pager.rows

      expect(run.pager.holding?).to be_true
      expect(run.rows[23]).to contain "--More--"

      pages = [] of String
      while run.pager.holding?
        pages.concat run.pager.showing
        run.press "Enter"
      end

      # The last view keeps older lines above the newest for context.
      rest = run.pager.showing
      pages.concat rest[(rest.index(pages.last) || -1) + 1..]

      # Every line of the volley shows, in order, with none skipped between
      # one page and the next.
      expect(pages).to eq run.game.log.lines.last(wrote)
    end
  end

  describe "drawn" do
    it "draws what it drew last time with a page held" do
      run = Playing.open
      6.times { |number| run.game.log.add "Something number #{number} happened." }
      run.play.refresh
      drawn = run.text

      expect(drawn).to eq Fixture.expected("screen/log-more.txt", drawn)
    end
  end
end
